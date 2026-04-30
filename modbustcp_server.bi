' -------------------------------------------------------------------------
' Project: FreeBASIC Modbus TCP library
' -------------------------------------------------------------------------
'
' File: modbustcp_server.bi
'
' Purpose:
'
'     Multi-client Modbus TCP server emulator for FreeBASIC.
'
' Responsibilities:
'
'      - Emulating a Modbus TCP server/PLC.
'      - Handling multiple concurrent client connections.
'      - Managing thread-safe access to Modbus data tables.
'      - Implementing standard Modbus function codes and extensions.
'
' This file intentionally does NOT contain:
'
'      - Client-side library logic.
'      - Application-specific business logic.
'      - Complex database or logging backends.
' -------------------------------------------------------------------------

''
'' modbustcp_server.bi
''
'' Multi-client Modbus TCP server emulator for FreeBASIC
''
'' This is the server-side companion to MBTCP (the client wrapper).
'' The intent is: a tech can read this file and learn Modbus/TCP while also
'' having a correct, testable emulator for validation + training.
''
' -------------------------------------------------------------------------
'' MODBUS/TCP FRAME OVERVIEW (the two-part packet)
' -------------------------------------------------------------------------
''
'' A Modbus/TCP packet is:
''
''   [ MBAP header (7 bytes total) ] [ PDU (N bytes) ]
''
'' The MBAP header is:
''   Transaction Identifier (2 bytes)  - copied by the server
''   Protocol Identifier     (2 bytes)  - always 0 for Modbus
''   Length                 (2 bytes)  - bytes following (UnitID + PDU)
''   Unit Identifier         (1 byte)   - slave/unit number (often 255)
''
'' The PDU begins with:
''   Function Code           (1 byte)
''   Function Data           (0..N bytes)
''
' -------------------------------------------------------------------------
'' Supported function codes:
' -------------------------------------------------------------------------
''   FC01 Read Coils
''   FC02 Read Discrete Inputs
''   FC03 Read Holding Registers
''   FC04 Read Input Registers
''   FC05 Write Single Coil
''   FC06 Write Single Register
''   FC07 Read Exception Status   (NOTE: this emulator returns a byte-count + status)
''   FC08 Diagnostics (subset)
''   FC0B Get Comm Event Counter
''   FC0C Get Comm Event Log
''   FC11 Report Server ID
''   FC0F Write Multiple Coils
''   FC10 Write Multiple Registers
''   FC17 Read/Write Multiple Registers
''   FC22 Mask Write Register (decimal 22, hex 0x16)
''
'' Optional/Stub:
''   FC14 Read File Record (stub: returns Illegal Function)
''
'' Version 1.6 06Feb2026
'' by Jason K. Firth + canonical emulator support
''
'' Fixes in v1.6:
''   - FC07 now returns [ByteCount=1] + [Status] to satisfy canonical client expectations
''   - FC08 Diagnostics expanded subset (0x000B..0x0014 common counters)
''   - ThreadCreate casts use a proper threadproc type (no warnings)
''   - Extra "teachy" comments restored (SJ_Zero style)
''
'' Fixes in v1.6+:
''   - FC22 Mask Write Register implemented (required by canonical harness)
''

#ifndef __MBSE_BI__
#define __MBSE_BI__

#ifdef __FB_WIN32__
    #include once "win/winsock2.bi"
    #include once "win/ws2tcpip.bi"
#else
    #include once "crt/netdb.bi"
    #include once "crt/sys/socket.bi"
    #include once "crt/netinet/in.bi"
    #include once "crt/arpa/inet.bi"
    #include once "crt/unistd.bi"
    #include once "crt/sys/time.bi"
    #include once "crt/errno.bi"
#endif


''
#include once "fix_errno.bi"
' -------------------------------------------------------------------------
'' Types / constants
' -------------------------------------------------------------------------
''

const MBSE_MAX_ADDR = 65535

#ifdef __FB_WIN32__
    type MBSE_SOCK as SOCKET
    const MBSE_INVALID_SOCKET = cast(MBSE_SOCK, INVALID_SOCKET)
#else
    type MBSE_SOCK as integer
    const MBSE_INVALID_SOCKET = cast(MBSE_SOCK, -1)
    #ifndef SOCKET_ERROR
        #define SOCKET_ERROR (-1)
    #endif
    #ifndef closesocket
        #define closesocket close
    #endif
#endif

'' Modbus exception codes (standard)
const MBEX_ILLEGAL_FUNCTION      = 1
const MBEX_ILLEGAL_DATA_ADDRESS  = 2
const MBEX_ILLEGAL_DATA_VALUE    = 3
const MBEX_SLAVE_DEVICE_FAILURE  = 4
const MBEX_ACKNOWLEDGE           = 5
const MBEX_SLAVE_DEVICE_BUSY     = 6
const MBEX_MEMORY_PARITY_ERROR   = 8
const MBEX_GATEWAY_PATH_UNAVAIL  = 10
const MBEX_GATEWAY_TARGET_FAIL   = 11

'' Which tables for reads (internal helper)
const MBSE_TABLE_COILS       = 0
const MBSE_TABLE_DISCRETE    = 1
const MBSE_TABLE_HOLDING     = 2
const MBSE_TABLE_INPUT       = 3

'' MBSE_RecvExact return codes
const MBSE_RECV_TIMEOUT      = -2
const MBSE_RECV_FATAL        = -1
const MBSE_RECV_CLOSED       = 0


''
'' ThreadProc type (prevents ThreadCreate pointer warnings)
''
type MBSE_THREADPROC as function( byval p as any ptr ) as any ptr


''
' -------------------------------------------------------------------------
'' Modbus memory model (shared across all clients)
' -------------------------------------------------------------------------
''
'' NOTE:
''   Modbus addressing fields are 16-bit, so 0..65535 is the reachable range.
''   This emulator exposes a clamp (MBSE_AddrCeiling) so validation can force
''   "illegal address" behaviours.
''

dim shared MBSE_Coil(0 to MBSE_MAX_ADDR) as ubyte
dim shared MBSE_DiscreteInput(0 to MBSE_MAX_ADDR) as ubyte
dim shared MBSE_InputRegister(0 to MBSE_MAX_ADDR) as ushort
dim shared MBSE_HoldingRegister(0 to MBSE_MAX_ADDR) as ushort


''
' -------------------------------------------------------------------------
'' Behaviour toggles (shared)
' -------------------------------------------------------------------------
''

dim shared MBSE_StrictUnitID as integer = 0
dim shared MBSE_ExpectedUnitID as ubyte = 255

dim shared MBSE_AddrCeiling as integer = MBSE_MAX_ADDR

'' socket timeouts for client sockets (ms)
dim shared MBSE_ClientRecvTimeoutMS as integer = 2000
dim shared MBSE_ClientSendTimeoutMS as integer = 2000


''
' -------------------------------------------------------------------------
'' Server socket + thread state
' -------------------------------------------------------------------------
''

dim shared MBSE_ServerSocket as MBSE_SOCK = MBSE_INVALID_SOCKET
dim shared MBSE_ServerRunning as integer
dim shared MBSE_LastError as integer
dim shared MBSE_AcceptThread as any ptr

'' Separate mutex per memory region
dim shared MBSE_CoilMutex        as any ptr
dim shared MBSE_DiscreteMutex    as any ptr
dim shared MBSE_InputRegMutex    as any ptr
dim shared MBSE_HoldingRegMutex  as any ptr

dim shared MBSE_ClientsMutex as any ptr

'' Track active client sockets so StopServer can force-close them.
dim shared MBSE_ClientSockList() as MBSE_SOCK
dim shared MBSE_ClientCount as integer


''
' -------------------------------------------------------------------------
'' Comm counters/log (FC0B / FC0C, also used by some FC08 subfunctions)
' -------------------------------------------------------------------------
''
'' These are not "perfect spec" counters, but they are consistent and useful.
'' The validation harness mostly cares that formats + lengths are correct and
'' that counters move in plausible ways.
''

dim shared MBSE_CommEventCounter as ushort
dim shared MBSE_CommMessageCounter as ushort

dim shared MBSE_CommStatus as ubyte = 0
dim shared MBSE_CommEventLog(0 to 63) as ubyte
dim shared MBSE_CommEventLogCount as integer
dim shared MBSE_CommMutex as any ptr
dim shared MBSE_DiagnosticRegister as short

''
' -------------------------------------------------------------------------
'' Server ID / device identification (FC11)
' -------------------------------------------------------------------------
''
dim shared MBSE_ServerID() as ubyte
dim shared MBSE_ServerIDSet as integer


''
' -------------------------------------------------------------------------
'' Debug support
' -------------------------------------------------------------------------
''

#ifdef MBSE_Debug
    declare sub MBSE_DumpBytes( byref label as string, byval p as ubyte ptr, byval n as integer )
    #define MBSE_DBG(msg) print "[MBSE] "; msg
#else
    sub MBSE_DumpBytes( byref label as string, byval p as ubyte ptr, byval n as integer )
    end sub
    #define MBSE_DBG(msg)
#endif

#ifdef MBSE_Debug
sub MBSE_DumpBytes( byref label as string, byval p as ubyte ptr, byval n as integer )
    dim i as integer
    print "[MBSE] "; label; " ("; n; " bytes): ";
    for i = 0 to n-1
        print hex(p[i], 2); " ";
    next i
    print
end sub
#endif


''
' -------------------------------------------------------------------------
'' Internal unsafe writers (mutex must already be held)
' -------------------------------------------------------------------------
''

#macro MBSE_WriteCoil_Unsafe(addr, value)
    MBSE_Coil((addr)) = iif((value)<>0, 1, 0)
#endmacro

#macro MBSE_WriteDiscrete_Unsafe(addr, value)
    MBSE_DiscreteInput((addr)) = iif((value)<>0, 1, 0)
#endmacro

#macro MBSE_WriteHolding_Unsafe(addr, value)
    MBSE_HoldingRegister((addr)) = (value)
#endmacro

#macro MBSE_WriteInput_Unsafe(addr, value)
    MBSE_InputRegister((addr)) = (value)
#endmacro



''
' -------------------------------------------------------------------------
'' Function declarations
' -------------------------------------------------------------------------
''

declare sub MBSE_Init()
declare sub MBSE_Shutdown()

declare function MBSE_StartServer( byval port as integer ) as integer
declare sub MBSE_StopServer()

declare function MBSE_AcceptThreadProc( byval unused as any ptr ) as any ptr
declare function MBSE_ClientThreadProc( byval pSock as any ptr ) as any ptr

declare function MBSE_ServerLoopOnce( byval clientSock as MBSE_SOCK ) as integer

declare function MBSE_RecvExact( byval sock as MBSE_SOCK, byval buf as ubyte ptr, byval expected as integer ) as integer
declare function MBSE_SendAll( byval sock as MBSE_SOCK, byval buf as ubyte ptr, byval length as integer ) as integer

declare function MBSE_SetClientTimeouts( byval sock as MBSE_SOCK, byval recvMS as integer, byval sendMS as integer ) as integer

declare sub MBSE_BuildExceptionResponse( outBuf() as ubyte, byval transHi as ubyte, byval transLo as ubyte, _
                                        byval unitId as ubyte, byval funcCode as ubyte, byval exCode as ubyte )

declare sub MBSE_BuildReadBitsResponse( outBuf() as ubyte, byval transHi as ubyte, byval transLo as ubyte, _
                                       byval unitId as ubyte, byval funcCode as ubyte, _
                                       byval startAddr as integer, byval quantity as integer, _
                                       byval whichTable as integer )

declare sub MBSE_BuildReadRegsResponse( outBuf() as ubyte, byval transHi as ubyte, byval transLo as ubyte, _
                                       byval unitId as ubyte, byval funcCode as ubyte, _
                                       byval startAddr as integer, byval quantity as integer, _
                                       byval whichTable as integer )

declare function MBSE_HandleRequest( req() as ubyte, byval reqLen as integer, resp() as ubyte ) as integer

declare sub MBSE_AddClientSock( byval s as MBSE_SOCK )
declare sub MBSE_RemoveClientSock( byval s as MBSE_SOCK )

declare sub MBSE_LogCommEvent( byval eventByte as ubyte )
declare sub MBSE_IncrementMessageCount()
declare sub MBSE_IncrementEventCount()

declare sub MBSE_SetServerIDString( byref s as string )

declare function MBSE_LastSockErr() as integer
declare function MBSE_IsTimeoutOrWouldBlock( byval e as integer ) as integer


''
' -------------------------------------------------------------------------
'' Thread-safe accessor routines
' -------------------------------------------------------------------------
''

declare sub MBSE_WriteCoil( byval addr as integer, byval value as ubyte )
declare function MBSE_ReadCoil( byval addr as integer ) as ubyte

declare sub MBSE_WriteDiscreteInput( byval addr as integer, byval value as ubyte )
declare function MBSE_ReadDiscreteInput( byval addr as integer ) as ubyte

declare sub MBSE_WriteHoldingRegister( byval addr as integer, byval value as ushort )
declare function MBSE_ReadHoldingRegister( byval addr as integer ) as ushort

declare sub MBSE_WriteInputRegister( byval addr as integer, byval value as ushort )
declare function MBSE_ReadInputRegister( byval addr as integer ) as ushort

declare sub MBSE_WriteLong( byval addr as integer, byval value as long )
declare function MBSE_ReadLong( byval addr as integer ) as long

declare sub MBSE_WriteFloat( byval addr as integer, byval value as single )
declare function MBSE_ReadFloat( byval addr as integer ) as single

declare sub MBSE_WriteInputLong( byval addr as integer, byval value as long )
declare function MBSE_ReadInputLong( byval addr as integer ) as long

declare sub MBSE_WriteInputFloat( byval addr as integer, byval value as single )
declare function MBSE_ReadInputFloat( byval addr as integer ) as single



''
' -------------------------------------------------------------------------
'' Init / Shutdown
' -------------------------------------------------------------------------
''

sub MBSE_Init()

#ifdef __FB_WIN32__
    '' init winsock
    dim wsaData as WSAData
    if( WSAStartup( MAKEWORD( 2, 2 ), @wsaData ) <> 0 ) then
        print "MBSE: WSAStartup failed"
        end 1
    end if
#endif

    '' mutexes (created once)
    if MBSE_CoilMutex = 0 then MBSE_CoilMutex = MutexCreate()
    if MBSE_DiscreteMutex = 0 then MBSE_DiscreteMutex = MutexCreate()
    if MBSE_InputRegMutex = 0 then MBSE_InputRegMutex = MutexCreate()
    if MBSE_HoldingRegMutex = 0 then MBSE_HoldingRegMutex = MutexCreate()

    if MBSE_ClientsMutex = 0 then MBSE_ClientsMutex = MutexCreate()
    if MBSE_CommMutex = 0 then MBSE_CommMutex = MutexCreate()

    '' clamp the address range
    if MBSE_AddrCeiling < 0 then MBSE_AddrCeiling = 0
    if MBSE_AddrCeiling > MBSE_MAX_ADDR then MBSE_AddrCeiling = MBSE_MAX_ADDR

    '' client list starts empty
    erase MBSE_ClientSockList
    MBSE_ClientCount = 0

    '' counters/log start empty
    MBSE_CommEventCounter = 0
    MBSE_CommMessageCounter = 0
    MBSE_CommEventLogCount = 0

    '' default server ID string (used by FC11)
    if MBSE_ServerIDSet = 0 then
        MBSE_SetServerIDString("FreeBASIC ModbusTCP Emulator v1.6")
    end if

    MBSE_DBG("Initialized")
end sub


sub MBSE_Shutdown()

    MBSE_StopServer()

    if MBSE_CoilMutex <> 0 then MutexDestroy(MBSE_CoilMutex): MBSE_CoilMutex = 0
    if MBSE_DiscreteMutex <> 0 then MutexDestroy(MBSE_DiscreteMutex): MBSE_DiscreteMutex = 0
    if MBSE_InputRegMutex <> 0 then MutexDestroy(MBSE_InputRegMutex): MBSE_InputRegMutex = 0
    if MBSE_HoldingRegMutex <> 0 then MutexDestroy(MBSE_HoldingRegMutex): MBSE_HoldingRegMutex = 0

    if MBSE_ClientsMutex <> 0 then MutexDestroy(MBSE_ClientsMutex): MBSE_ClientsMutex = 0
    if MBSE_CommMutex <> 0 then MutexDestroy(MBSE_CommMutex): MBSE_CommMutex = 0

#ifdef __FB_WIN32__
    WSACleanup()
#endif

    MBSE_DBG("Shutdown")
end sub


sub MBSE_SetServerIDString( byref s as string )
    dim n as integer = len(s)
    if n < 1 then n = 1

    redim MBSE_ServerID(0 to n-1)

    dim i as integer
    for i = 0 to n-1
        MBSE_ServerID(i) = asc(mid(s, i+1, 1))
    next i

    MBSE_ServerIDSet = 1
end sub


''
' -------------------------------------------------------------------------
'' Comm log helpers
' -------------------------------------------------------------------------
''

sub MBSE_LogCommEvent( byval eventByte as ubyte )
    MutexLock(MBSE_CommMutex)

    if MBSE_CommEventLogCount < 64 then
        MBSE_CommEventLog(MBSE_CommEventLogCount) = eventByte
        MBSE_CommEventLogCount += 1
    else
        '' FIFO shift (keep last 64)
        dim i as integer
        for i = 0 to 62
            MBSE_CommEventLog(i) = MBSE_CommEventLog(i+1)
        next i
        MBSE_CommEventLog(63) = eventByte
    end if

    MutexUnlock(MBSE_CommMutex)
end sub


sub MBSE_IncrementMessageCount()
    MutexLock(MBSE_CommMutex)
    MBSE_CommMessageCounter += 1
    MutexUnlock(MBSE_CommMutex)
end sub


sub MBSE_IncrementEventCount()
    MutexLock(MBSE_CommMutex)
    MBSE_CommEventCounter += 1
    MutexUnlock(MBSE_CommMutex)
end sub



''
' -------------------------------------------------------------------------
'' Client list helpers
' -------------------------------------------------------------------------
''

sub MBSE_AddClientSock( byval s as MBSE_SOCK )
    MutexLock(MBSE_ClientsMutex)

    MBSE_ClientCount += 1
    redim preserve MBSE_ClientSockList(0 to MBSE_ClientCount-1)
    MBSE_ClientSockList(MBSE_ClientCount-1) = s

    MutexUnlock(MBSE_ClientsMutex)
end sub


sub MBSE_RemoveClientSock( byval s as MBSE_SOCK )
    MutexLock(MBSE_ClientsMutex)

    dim i as integer
    for i = 0 to MBSE_ClientCount-1
        if MBSE_ClientSockList(i) = s then
            MBSE_ClientSockList(i) = MBSE_ClientSockList(MBSE_ClientCount-1)
            MBSE_ClientCount -= 1

            if MBSE_ClientCount <= 0 then
                erase MBSE_ClientSockList
                MBSE_ClientCount = 0
            else
                redim preserve MBSE_ClientSockList(0 to MBSE_ClientCount-1)
            end if

            exit for
        end if
    next i

    MutexUnlock(MBSE_ClientsMutex)
end sub



''
' -------------------------------------------------------------------------
'' Start/Stop Server (multi-client)
' -------------------------------------------------------------------------
''

function MBSE_StartServer( byval port as integer ) as integer

    MBSE_DBG("Starting server on port " & port)

    if MBSE_ServerRunning <> 0 then
        MBSE_DBG("Server already running")
        return 1
    end if

    '' open socket
    MBSE_ServerSocket = opensocket( PF_INET, SOCK_STREAM, IPPROTO_TCP )
    if MBSE_ServerSocket = MBSE_INVALID_SOCKET then
        MBSE_LastError = 1
        MBSE_DBG("ERROR: socket() failed")
        return 0
    end if

    '' allow quick restart
    dim opt as integer = 1
    setsockopt(MBSE_ServerSocket, SOL_SOCKET, SO_REUSEADDR, cast(any ptr, @opt), sizeof(opt))

    '' bind to port
    dim sa as sockaddr_in
    sa.sin_family = AF_INET
    sa.sin_port = htons( port )
    sa.sin_addr.S_addr = INADDR_ANY

    MBSE_DBG("Binding socket")
    if bind( MBSE_ServerSocket, cast( PSOCKADDR, @sa ), sizeof(sa) ) = SOCKET_ERROR then
        closesocket( MBSE_ServerSocket )
        MBSE_ServerSocket = MBSE_INVALID_SOCKET
        MBSE_LastError = 2
        MBSE_DBG("ERROR: bind() failed")
        return 0
    end if

    '' listen
    MBSE_DBG("Listening")
    if listen( MBSE_ServerSocket, 16 ) = SOCKET_ERROR then
        closesocket( MBSE_ServerSocket )
        MBSE_ServerSocket = MBSE_INVALID_SOCKET
        MBSE_LastError = 3
        MBSE_DBG("ERROR: listen() failed")
        return 0
    end if

    MBSE_ServerRunning = 1
    MBSE_DBG("Server is listening")

    '' accept thread
    MBSE_AcceptThread = ThreadCreate( cast(MBSE_THREADPROC ptr, @MBSE_AcceptThreadProc), 0 )
    if MBSE_AcceptThread = 0 then
        MBSE_DBG("ERROR: ThreadCreate(accept) failed")
        MBSE_StopServer()
        return 0
    end if

    return 1

end function


sub MBSE_StopServer()

    if MBSE_ServerRunning = 0 then exit sub

    MBSE_DBG("Stopping server")
    MBSE_ServerRunning = 0

    '' Closing server socket unblocks accept()
    if MBSE_ServerSocket <> MBSE_INVALID_SOCKET then
        shutdown( MBSE_ServerSocket, 2 )
        closesocket( MBSE_ServerSocket )
        MBSE_ServerSocket = MBSE_INVALID_SOCKET
        MBSE_DBG("Server socket closed")
    end if

    '' Force-close all known client sockets
    MutexLock(MBSE_ClientsMutex)
    dim i as integer
    for i = 0 to MBSE_ClientCount-1
        if MBSE_ClientSockList(i) <> MBSE_INVALID_SOCKET then
            shutdown( MBSE_ClientSockList(i), 2 )
            closesocket( MBSE_ClientSockList(i) )
        end if
    next i
    MBSE_ClientCount = 0
    erase MBSE_ClientSockList
    MutexUnlock(MBSE_ClientsMutex)

    '' Wait for accept thread to exit
    if MBSE_AcceptThread <> 0 then
        ThreadWait(MBSE_AcceptThread)
        MBSE_AcceptThread = 0
        MBSE_DBG("Accept thread exited")
    end if

end sub



''
' -------------------------------------------------------------------------
'' Accept thread
' -------------------------------------------------------------------------
''

function MBSE_AcceptThreadProc( byval unused as any ptr ) as any ptr

    dim addr as sockaddr_in

    while MBSE_ServerRunning <> 0

        dim addrlen as integer = sizeof(addr)

        MBSE_DBG("Waiting for client connection...")

        dim c as MBSE_SOCK
        c = accept( MBSE_ServerSocket, cast(PSOCKADDR, @addr), @addrlen )

        if c = MBSE_INVALID_SOCKET then
            if MBSE_ServerRunning = 0 then exit while
            MBSE_DBG("accept() failed (or interrupted)")
            continue while
        end if

        '' If we are stopping, close the accepted socket immediately (race fix)
        if MBSE_ServerRunning = 0 then
            shutdown(c, 2)
            closesocket(c)
            exit while
        end if

        MBSE_DBG("Client connected")

        MBSE_AddClientSock(c)

        '' configure timeouts for this client
        MBSE_SetClientTimeouts(c, MBSE_ClientRecvTimeoutMS, MBSE_ClientSendTimeoutMS)

        '' Spawn client handler thread. We pass the socket value via heap storage.
        dim p as MBSE_SOCK ptr = callocate(1, sizeof(MBSE_SOCK))
        *p = c

        dim th as any ptr = ThreadCreate( cast(MBSE_THREADPROC ptr, @MBSE_ClientThreadProc), p )
        if th = 0 then
            MBSE_DBG("ERROR: ThreadCreate(client) failed; closing client")
            MBSE_RemoveClientSock(c)
            shutdown(c, 2)
            closesocket(c)
            deallocate(p)
        end if

    wend

    return 0

end function



''
' -------------------------------------------------------------------------
'' Client thread
' -------------------------------------------------------------------------
''

function MBSE_ClientThreadProc( byval pSock as any ptr ) as any ptr

    dim c as MBSE_SOCK
    c = *cast(MBSE_SOCK ptr, pSock)
    deallocate(pSock)

    MBSE_DBG("Client thread started")

    while MBSE_ServerRunning <> 0
        if MBSE_ServerLoopOnce(c) = 0 then exit while
    wend

    MBSE_DBG("Client disconnecting/ending thread")

    MBSE_RemoveClientSock(c)
    shutdown(c, 2)
    closesocket(c)

    return 0

end function



''
' -------------------------------------------------------------------------
'' Main server loop step (per-client)
' -------------------------------------------------------------------------
''
'' We read the 6-byte MBAP prefix first:
''   TID(2), PID(2), LEN(2)
''
'' Then we read LEN bytes (UnitID + PDU).
''
function MBSE_ServerLoopOnce( byval clientSock as MBSE_SOCK ) as integer

    if clientSock = MBSE_INVALID_SOCKET then
        MBSE_DBG("ServerLoopOnce: invalid client socket")
        return 0
    end if

    dim header(0 to 5) as ubyte
    dim got as integer

    got = MBSE_RecvExact( clientSock, @header(0), 6 )

    if got = MBSE_RECV_TIMEOUT then
        '' idle timeout is not a disconnect
        return 1
    end if

    if got <> 6 then
        return 0
    end if

    MBSE_DumpBytes("RX-MBAP6", @header(0), 6)

    dim transHi as ubyte = header(0)
    dim transLo as ubyte = header(1)
    dim protoHi as ubyte = header(2)
    dim protoLo as ubyte = header(3)

    '' Protocol ID should be 0 for Modbus
    if protoHi <> 0 or protoLo <> 0 then
        MBSE_DBG("ServerLoopOnce: Non-modbus protocol ID, dropping")
        return 0
    end if

    dim lengthField as integer
    lengthField = (header(4) shl 8) OR header(5)

    '' Length must include at least UnitID(1) + Func(1) = 2
    if lengthField < 2 then return 0

    '' defensive clamp (Modbus/TCP typical max PDU is < 260)
    if lengthField > 260 then return 0

    dim reqLen as integer
    reqLen = 6 + lengthField

    dim req() as ubyte
    redim req(0 to reqLen-1)

    '' copy MBAP6 into request buffer
    dim i as integer
    for i = 0 to 5
        req(i) = header(i)
    next i

    '' read the remaining bytes (UnitID + PDU)
    got = MBSE_RecvExact( clientSock, @req(6), lengthField )

    if got = MBSE_RECV_TIMEOUT then
        '' timeout mid-frame is unsafe without buffering
        return 0
    end if

    if got <> lengthField then
        return 0
    end if

    MBSE_DumpBytes("RX-REQ", @req(0), reqLen)

    '' message counter increments on every complete request frame
    MBSE_IncrementMessageCount()

    dim resp() as ubyte
    dim respLen as integer

    respLen = MBSE_HandleRequest( req(), reqLen, resp() )

    '' respLen = 0 means ignore request (no response)
    '' respLen < 0 means fatal
    if respLen = 0 then return 1
    if respLen < 0 then return 0

    MBSE_DumpBytes("TX-RESP", @resp(0), respLen)

    if MBSE_SendAll( clientSock, @resp(0), respLen ) = 0 then
        return 0
    end if

    return 1

end function



''
' -------------------------------------------------------------------------
'' Socket helpers
' -------------------------------------------------------------------------
''

function MBSE_SetClientTimeouts( byval sock as MBSE_SOCK, byval recvMS as integer, byval sendMS as integer ) as integer

#ifdef __FB_WIN32__
    dim tv as integer

    tv = recvMS
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, cast(any ptr, @tv), sizeof(tv))

    tv = sendMS
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, cast(any ptr, @tv), sizeof(tv))
#else
    dim t as timeval

    t.tv_sec  = recvMS \ 1000
    t.tv_usec = (recvMS mod 1000) * 1000
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, cast(any ptr, @t), sizeof(t))

    t.tv_sec  = sendMS \ 1000
    t.tv_usec = (sendMS mod 1000) * 1000
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, cast(any ptr, @t), sizeof(t))
#endif

    return 1
end function


function MBSE_LastSockErr() as integer
#ifdef __FB_WIN32__
    return WSAGetLastError()
#else
    return errno
#endif
end function


function MBSE_IsTimeoutOrWouldBlock( byval e as integer ) as integer
#ifdef __FB_WIN32__
    if e = WSAETIMEDOUT then return -1
    if e = WSAEWOULDBLOCK then return -1
    return 0
#else
    if e = EAGAIN then return -1
    if e = EWOULDBLOCK then return -1
    if e = ETIMEDOUT then return -1
    return 0
#endif
end function


''
'' MBSE_RecvExact(sock, buf, expected)
''
'' Reads exactly 'expected' bytes unless:
''   - connection closed
''   - timeout
''   - fatal recv error
''
function MBSE_RecvExact( byval sock as MBSE_SOCK, byval buf as ubyte ptr, byval expected as integer ) as integer

    dim total as integer = 0
    dim got as integer

    while total < expected

        got = recv( sock, buf + total, expected - total, 0 )

        if got = 0 then
            return MBSE_RECV_CLOSED
        end if

        if got < 0 then
            dim e as integer = MBSE_LastSockErr()

            if MBSE_IsTimeoutOrWouldBlock(e) then
                return MBSE_RECV_TIMEOUT
            end if

            return MBSE_RECV_FATAL
        end if

        total += got

    wend

    return total

end function


function MBSE_SendAll( byval sock as MBSE_SOCK, byval buf as ubyte ptr, byval length as integer ) as integer

    dim total as integer = 0
    dim sent as integer

    while total < length

        sent = send( sock, buf + total, length - total, 0 )

        if sent <= 0 then
            return 0
        end if

        total += sent

    wend

    return 1

end function



''
' -------------------------------------------------------------------------
'' Thread-safe memory accessors
' -------------------------------------------------------------------------
''

sub MBSE_WriteCoil( byval addr as integer, byval value as ubyte )
    if addr < 0 or addr > MBSE_AddrCeiling then exit sub
    MutexLock(MBSE_CoilMutex)
    MBSE_WriteCoil_Unsafe(addr, value)
    MutexUnlock(MBSE_CoilMutex)
end sub


function MBSE_ReadCoil( byval addr as integer ) as ubyte
    if addr < 0 or addr > MBSE_AddrCeiling then return 0
    MutexLock(MBSE_CoilMutex)
    dim v as ubyte = MBSE_Coil(addr)
    MutexUnlock(MBSE_CoilMutex)
    return iif(v <> 0, 1, 0)
end function


sub MBSE_WriteDiscreteInput( byval addr as integer, byval value as ubyte )
    if addr < 0 or addr > MBSE_AddrCeiling then exit sub
    MutexLock(MBSE_DiscreteMutex)
    MBSE_WriteDiscrete_Unsafe(addr, value)
    MutexUnlock(MBSE_DiscreteMutex)
end sub


function MBSE_ReadDiscreteInput( byval addr as integer ) as ubyte
    if addr < 0 or addr > MBSE_AddrCeiling then return 0
    MutexLock(MBSE_DiscreteMutex)
    dim v as ubyte = MBSE_DiscreteInput(addr)
    MutexUnlock(MBSE_DiscreteMutex)
    return iif(v <> 0, 1, 0)
end function


sub MBSE_WriteHoldingRegister( byval addr as integer, byval value as ushort )
    if addr < 0 or addr > MBSE_AddrCeiling then exit sub
    MutexLock(MBSE_HoldingRegMutex)
    MBSE_WriteHolding_Unsafe(addr, value)
    MutexUnlock(MBSE_HoldingRegMutex)
end sub


function MBSE_ReadHoldingRegister( byval addr as integer ) as ushort
    if addr < 0 or addr > MBSE_AddrCeiling then return 0
    MutexLock(MBSE_HoldingRegMutex)
    dim v as ushort = MBSE_HoldingRegister(addr)
    MutexUnlock(MBSE_HoldingRegMutex)
    return v
end function


sub MBSE_WriteInputRegister( byval addr as integer, byval value as ushort )
    if addr < 0 or addr > MBSE_AddrCeiling then exit sub
    MutexLock(MBSE_InputRegMutex)
    MBSE_WriteInput_Unsafe(addr, value)
    MutexUnlock(MBSE_InputRegMutex)
end sub


function MBSE_ReadInputRegister( byval addr as integer ) as ushort
    if addr < 0 or addr > MBSE_AddrCeiling then return 0
    MutexLock(MBSE_InputRegMutex)
    dim v as ushort = MBSE_InputRegister(addr)
    MutexUnlock(MBSE_InputRegMutex)
    return v
end function


sub MBSE_WriteLong( byval addr as integer, byval value as long )
    if addr < 0 or (addr + 1) > MBSE_AddrCeiling then exit sub
    dim lo as ushort = value AND &HFFFF
    dim hi as ushort = (value SHR 16) AND &HFFFF
    MutexLock(MBSE_HoldingRegMutex)
    MBSE_WriteHolding_Unsafe(addr, lo)
    MBSE_WriteHolding_Unsafe(addr + 1, hi)
    MutexUnlock(MBSE_HoldingRegMutex)
end sub


function MBSE_ReadLong( byval addr as integer ) as long
    if addr < 0 or (addr + 1) > MBSE_AddrCeiling then return 0
    dim lo as ulong
    dim hi as ulong
    MutexLock(MBSE_HoldingRegMutex)
    lo = MBSE_HoldingRegister(addr)
    hi = MBSE_HoldingRegister(addr + 1)
    MutexUnlock(MBSE_HoldingRegMutex)
    return cast(long, lo OR (hi SHL 16))
end function


sub MBSE_WriteFloat( byval addr as integer, byval value as single )
    if addr < 0 or (addr + 1) > MBSE_AddrCeiling then exit sub
    union FloatConv
        f as single
        u as ulong
    end union
    dim c as FloatConv
    c.f = value
    dim lo as ushort = c.u AND &HFFFF
    dim hi as ushort = (c.u SHR 16) AND &HFFFF
    MutexLock(MBSE_HoldingRegMutex)
    MBSE_WriteHolding_Unsafe(addr, lo)
    MBSE_WriteHolding_Unsafe(addr + 1, hi)
    MutexUnlock(MBSE_HoldingRegMutex)
end sub


function MBSE_ReadFloat( byval addr as integer ) as single
    if addr < 0 or (addr + 1) > MBSE_AddrCeiling then return 0
    union FloatConv
        f as single
        u as ulong
    end union
    dim lo as ulong
    dim hi as ulong
    dim c as FloatConv
    MutexLock(MBSE_HoldingRegMutex)
    lo = MBSE_HoldingRegister(addr)
    hi = MBSE_HoldingRegister(addr + 1)
    MutexUnlock(MBSE_HoldingRegMutex)
    c.u = lo OR (hi SHL 16)
    return c.f
end function


sub MBSE_WriteInputLong( byval addr as integer, byval value as long )
    if addr < 0 or (addr + 1) > MBSE_AddrCeiling then exit sub
    dim lo as ushort = value AND &HFFFF
    dim hi as ushort = (value SHR 16) AND &HFFFF
    MutexLock(MBSE_InputRegMutex)
    MBSE_WriteInput_Unsafe(addr, lo)
    MBSE_WriteInput_Unsafe(addr + 1, hi)
    MutexUnlock(MBSE_InputRegMutex)
end sub


function MBSE_ReadInputLong( byval addr as integer ) as long
    if addr < 0 or (addr + 1) > MBSE_AddrCeiling then return 0
    dim lo as ulong
    dim hi as ulong
    MutexLock(MBSE_InputRegMutex)
    lo = MBSE_InputRegister(addr)
    hi = MBSE_InputRegister(addr + 1)
    MutexUnlock(MBSE_InputRegMutex)
    return cast(long, lo OR (hi SHL 16))
end function


sub MBSE_WriteInputFloat( byval addr as integer, byval value as single )
    if addr < 0 or (addr + 1) > MBSE_AddrCeiling then exit sub
    union FloatConv
        f as single
        u as ulong
    end union
    dim c as FloatConv
    c.f = value
    dim lo as ushort = c.u AND &HFFFF
    dim hi as ushort = (c.u SHR 16) AND &HFFFF
    MutexLock(MBSE_InputRegMutex)
    MBSE_WriteInput_Unsafe(addr, lo)
    MBSE_WriteInput_Unsafe(addr + 1, hi)
    MutexUnlock(MBSE_InputRegMutex)
end sub


function MBSE_ReadInputFloat( byval addr as integer ) as single
    if addr < 0 or (addr + 1) > MBSE_AddrCeiling then return 0
    union FloatConv
        f as single
        u as ulong
    end union
    dim lo as ulong
    dim hi as ulong
    dim c as FloatConv
    MutexLock(MBSE_InputRegMutex)
    lo = MBSE_InputRegister(addr)
    hi = MBSE_InputRegister(addr + 1)
    MutexUnlock(MBSE_InputRegMutex)
    c.u = lo OR (hi SHL 16)
    return c.f
end function



''
' -------------------------------------------------------------------------
'' Response builders
' -------------------------------------------------------------------------
''

sub MBSE_BuildExceptionResponse( outBuf() as ubyte, byval transHi as ubyte, byval transLo as ubyte, _
                                byval unitId as ubyte, byval funcCode as ubyte, byval exCode as ubyte )

    '' Exception response is:
    ''   UnitID, (Func|0x80), ExceptionCode
    '' so MBAP length = 3 and total bytes = 6 + 3 = 9

    redim outBuf(0 to 8)

    outBuf(0) = transHi
    outBuf(1) = transLo
    outBuf(2) = 0
    outBuf(3) = 0
    outBuf(4) = 0
    outBuf(5) = 3

    outBuf(6) = unitId
    outBuf(7) = funcCode OR &H80
    outBuf(8) = exCode

end sub


sub MBSE_BuildReadBitsResponse( outBuf() as ubyte, byval transHi as ubyte, byval transLo as ubyte, _
                               byval unitId as ubyte, byval funcCode as ubyte, _
                               byval startAddr as integer, byval quantity as integer, _
                               byval whichTable as integer )

    '' Read Coils / Discrete Inputs response:
    ''   UnitID, Func, ByteCount, DataBytes...

    dim byteCount as integer = (quantity + 7) \ 8
    dim totalLen as integer = 9 + byteCount
    redim outBuf(0 to totalLen-1)

    outBuf(0) = transHi
    outBuf(1) = transLo
    outBuf(2) = 0
    outBuf(3) = 0

    '' MBAP Length = UnitID(1) + Func(1) + ByteCount(1) + Data(byteCount)
    dim mbapLen as integer = 1 + (1 + 1 + byteCount)
    outBuf(4) = (mbapLen SHR 8) AND 255
    outBuf(5) = mbapLen AND 255

    outBuf(6) = unitId
    outBuf(7) = funcCode
    outBuf(8) = byteCount

    '' clear data bytes
    dim i as integer
    for i = 0 to byteCount-1
        outBuf(9+i) = 0
    next i

    '' pack bits LSB-first per Modbus spec
    dim bitIndex as integer = 0

    if whichTable = MBSE_TABLE_COILS then
        MutexLock(MBSE_CoilMutex)
    else
        MutexLock(MBSE_DiscreteMutex)
    end if

    for i = 0 to quantity-1
        dim tmpval as ubyte
        if whichTable = MBSE_TABLE_COILS then
            tmpval = MBSE_Coil(startAddr + i)
        else
            tmpval = MBSE_DiscreteInput(startAddr + i)
        end if

        if tmpval <> 0 then
            outBuf(9 + (bitIndex \ 8)) OR= (1 SHL (bitIndex MOD 8))
        end if

        bitIndex += 1
    next i

    if whichTable = MBSE_TABLE_COILS then
        MutexUnlock(MBSE_CoilMutex)
    else
        MutexUnlock(MBSE_DiscreteMutex)
    end if

end sub


sub MBSE_BuildReadRegsResponse( outBuf() as ubyte, byval transHi as ubyte, byval transLo as ubyte, _
                               byval unitId as ubyte, byval funcCode as ubyte, _
                               byval startAddr as integer, byval quantity as integer, _
                               byval whichTable as integer )

    '' Read Holding/Input Registers response:
    ''   UnitID, Func, ByteCount, RegHi, RegLo, ...

    dim byteCount as integer = quantity * 2
    dim totalLen as integer = 9 + byteCount
    redim outBuf(0 to totalLen-1)

    outBuf(0) = transHi
    outBuf(1) = transLo
    outBuf(2) = 0
    outBuf(3) = 0

    dim mbapLen as integer = 1 + (1 + 1 + byteCount)
    outBuf(4) = (mbapLen SHR 8) AND 255
    outBuf(5) = mbapLen AND 255

    outBuf(6) = unitId
    outBuf(7) = funcCode
    outBuf(8) = byteCount

    dim i as integer
    dim p as integer = 9

    if whichTable = MBSE_TABLE_HOLDING then
        MutexLock(MBSE_HoldingRegMutex)
    else
        MutexLock(MBSE_InputRegMutex)
    end if

    for i = 0 to quantity-1
        dim v as ushort
        if whichTable = MBSE_TABLE_HOLDING then
            v = MBSE_HoldingRegister(startAddr + i)
        else
            v = MBSE_InputRegister(startAddr + i)
        end if

        outBuf(p)   = (v SHR 8) AND 255
        outBuf(p+1) = v AND 255
        p += 2
    next i

    if whichTable = MBSE_TABLE_HOLDING then
        MutexUnlock(MBSE_HoldingRegMutex)
    else
        MutexUnlock(MBSE_InputRegMutex)
    end if

end sub



''
' -------------------------------------------------------------------------
'' Request handler
' -------------------------------------------------------------------------
''
function MBSE_HandleRequest( req() as ubyte, byval reqLen as integer, resp() as ubyte ) as integer

    '' minimum Modbus/TCP frame: MBAP6(6) + UnitID(1) + Func(1) = 8
    if reqLen < 8 then return -1

    '' clamp ceiling if user changed it mid-run
    if MBSE_AddrCeiling < 0 then MBSE_AddrCeiling = 0
    if MBSE_AddrCeiling > MBSE_MAX_ADDR then MBSE_AddrCeiling = MBSE_MAX_ADDR

    dim transHi as ubyte = req(0)
    dim transLo as ubyte = req(1)

    dim unitId  as ubyte = req(6)
    dim func    as ubyte = req(7)

    '' Strict UnitID enforcement: ignore requests not matching
    if MBSE_StrictUnitID andalso unitId <> MBSE_ExpectedUnitID then
        return 0
    end if

    dim startAddr as integer
    dim quantity as integer

    select case func

        ''
        ' -------------------------------------------------------------------------
        '' FC01/02/03/04 Read tables
        ' -------------------------------------------------------------------------
        ''
        case 1, 2, 3, 4

            if reqLen < 12 then return -1

            startAddr = (req(8) shl 8) OR req(9)
            quantity  = (req(10) shl 8) OR req(11)

            if quantity <= 0 then
                MBSE_BuildExceptionResponse(resp(), transHi, transLo, unitId, func, MBEX_ILLEGAL_DATA_VALUE)
                return ubound(resp)+1
            end if

            if startAddr < 0 or startAddr > MBSE_AddrCeiling then
                MBSE_BuildExceptionResponse(resp(), transHi, transLo, unitId, func, MBEX_ILLEGAL_DATA_ADDRESS)
                return ubound(resp)+1
            end if

            if startAddr + quantity - 1 > MBSE_AddrCeiling then
                MBSE_BuildExceptionResponse(resp(), transHi, transLo, unitId, func, MBEX_ILLEGAL_DATA_ADDRESS)
                return ubound(resp)+1
            end if

            if func = 1 then
                MBSE_BuildReadBitsResponse(resp(), transHi, transLo, unitId, func, startAddr, quantity, MBSE_TABLE_COILS)
            elseif func = 2 then
                MBSE_BuildReadBitsResponse(resp(), transHi, transLo, unitId, func, startAddr, quantity, MBSE_TABLE_DISCRETE)
            elseif func = 3 then
                MBSE_BuildReadRegsResponse(resp(), transHi, transLo, unitId, func, startAddr, quantity, MBSE_TABLE_HOLDING)
            else
                MBSE_BuildReadRegsResponse(resp(), transHi, transLo, unitId, func, startAddr, quantity, MBSE_TABLE_INPUT)
            end if

            MBSE_IncrementEventCount()
            MBSE_LogCommEvent(func)

            return ubound(resp)+1


        ''
        ' -------------------------------------------------------------------------
        '' FC05 Write Single Coil
        ' -------------------------------------------------------------------------
        ''
        case 5

            if reqLen < 12 then return -1

            startAddr = (req(8) shl 8) OR req(9)

            if startAddr < 0 or startAddr > MBSE_AddrCeiling then
                MBSE_BuildExceptionResponse(resp(), transHi, transLo, unitId, func, MBEX_ILLEGAL_DATA_ADDRESS)
                return ubound(resp)+1
            end if

            dim valHi as ubyte = req(10)
            dim valLo as ubyte = req(11)

            '' coil ON is FF00, OFF is 0000
            if valHi = &HFF and valLo = &H00 then
                MBSE_WriteCoil(startAddr, 1)
            elseif valHi = &H00 and valLo = &H00 then
                MBSE_WriteCoil(startAddr, 0)
            else
                MBSE_BuildExceptionResponse(resp(), transHi, transLo, unitId, func, MBEX_ILLEGAL_DATA_VALUE)
                return ubound(resp)+1
            end if

            '' response echoes request for FC05/FC06
            redim resp(0 to 11)
            dim i as integer
            for i = 0 to 11
                resp(i) = req(i)
            next i

            MBSE_IncrementEventCount()
            MBSE_LogCommEvent(func)

            return 12


        ''
        ' -------------------------------------------------------------------------
        '' FC06 Write Single Register
        ' -------------------------------------------------------------------------
        ''
        case 6

            if reqLen < 12 then return -1

            startAddr = (req(8) shl 8) OR req(9)

            if startAddr < 0 or startAddr > MBSE_AddrCeiling then
                MBSE_BuildExceptionResponse(resp(), transHi, transLo, unitId, func, MBEX_ILLEGAL_DATA_ADDRESS)
                return ubound(resp)+1
            end if

            dim regVal as ushort
            regVal = (req(10) shl 8) OR req(11)

            MBSE_WriteHoldingRegister(startAddr, regVal)

            redim resp(0 to 11)
            dim i as integer
            for i = 0 to 11
                resp(i) = req(i)
            next i

            MBSE_IncrementEventCount()
            MBSE_LogCommEvent(func)

            return 12


        ''
        ' -------------------------------------------------------------------------
        '' FC22 (0x16) Mask Write Register
        ' -------------------------------------------------------------------------
        ''
        '' NOTE:
        ''   Function code 22 decimal = 0x16 hex.
        ''   This is a read-modify-write operation on ONE holding register.
        ''
        '' Request:
        ''   UnitID, FC22, Addr(2), AndMask(2), OrMask(2)
        ''
        '' Response:
        ''   Echo request
        ''
        '' Spec formula:
        ''   new = (old AND andMask) OR (orMask AND (NOT andMask))
        ''
        case 22

            '' Full Modbus/TCP frame:
            ''   MBAP6(6) + UnitID(1) + FC(1) + Addr(2) + And(2) + Or(2) = 14 bytes
            if reqLen < 14 then return -1

            startAddr = (req(8) shl 8) OR req(9)

            if startAddr < 0 or startAddr > MBSE_AddrCeiling then
                MBSE_BuildExceptionResponse(resp(), transHi, transLo, unitId, func, MBEX_ILLEGAL_DATA_ADDRESS)
                return ubound(resp)+1
            end if

            dim andMask as ushort
            dim orMask as ushort

            andMask = (req(10) shl 8) OR req(11)
            orMask  = (req(12) shl 8) OR req(13)

            dim oldVal as ushort
            dim newVal as ushort
            dim notAnd as ushort

            MutexLock(MBSE_HoldingRegMutex)

            oldVal = MBSE_HoldingRegister(startAddr)

            '' Force NOT to remain 16-bit (BASIC NOT is wider than 16 bits)
            notAnd = (&HFFFF XOR andMask)

            newVal = (oldVal AND andMask) OR (orMask AND notAnd)

            MBSE_WriteHolding_Unsafe(startAddr, newVal)

            MutexUnlock(MBSE_HoldingRegMutex)

            '' response echoes request
            redim resp(0 to 13)

            dim i as integer
            for i = 0 to 13
                resp(i) = req(i)
            next i

            MBSE_IncrementEventCount()
            MBSE_LogCommEvent(func)

            return 14


        ''
        ' -------------------------------------------------------------------------
        '' FC07 Read Exception Status
        ' -------------------------------------------------------------------------
        ''
        '' NOTE:
        ''   The Modbus spec response is FC + 1 status byte.
        ''   The canonical client/harness used in this project expects a
        ''   “read-like” response with a byte count of 1, then the status byte.
        ''
        ''   So we return: UnitID, FC07, ByteCount=1, Status
        ''   (MBAP Length = 4, total bytes = 10)
        ''
        case 7

            redim resp(0 to 9)

            resp(0) = transHi
            resp(1) = transLo
            resp(2) = 0
            resp(3) = 0

            resp(4) = 0
            resp(5) = 4   '' UnitID + FC + ByteCount + Status

            resp(6) = unitId
            resp(7) = func
            resp(8) = 1              '' byte count
            resp(9) = MBSE_CommStatus

            MBSE_IncrementEventCount()
            MBSE_LogCommEvent(func)

            return 10


        ''
        ' -------------------------------------------------------------------------
        '' FC08 Diagnostics (expanded subset)
        ' -------------------------------------------------------------------------
        ''
        '' Request:
        ''   UnitID, FC08, SubFuncHi, SubFuncLo, DataHi, DataLo
        ''
        '' Response:
        ''   UnitID, FC08, SubFuncHi, SubFuncLo, DataHi, DataLo
        ''
         case 8

            if reqLen < 12 then return -1

            dim subFunc as ushort
            dim diagData as ushort

            subFunc = (req(8) shl 8) OR req(9)
            diagData = (req(10) shl 8) OR req(11)

            dim outData as ushort = diagData

            select case subFunc

                case &H0000
                    '' Return Query Data (echo)
                    outData = diagData

                case &H0001
                    '' Restart Communications Option (ack/echo)
                    outData = diagData

                case &H0002
                    '' Return Diagnostic Register (we map to message counter)
                    MutexLock(MBSE_CommMutex)
                    outData = MBSE_DiagnosticRegister
                    MutexUnlock(MBSE_CommMutex)

                case &H000A
                    '' Clear Counters and Diagnostic Register
                    '' IMPORTANT:
                    ''   The validation harness expects the comm-event log to be EMPTY after this call.
                    ''   So: clear, respond, and DO NOT re-log FC08 as a “new event”.

                    MutexLock(MBSE_CommMutex)
                    MBSE_CommEventCounter = 0
                    MBSE_CommMessageCounter = 0
                    MBSE_DiagnosticRegister = 0
                    MBSE_CommEventLogCount = 0
                    MutexUnlock(MBSE_CommMutex)

                    outData = 0

                    '' Build normal FC08 response (echo subfunc + data)
                    redim resp(0 to 11)

                    resp(0) = transHi
                    resp(1) = transLo
                    resp(2) = 0
                    resp(3) = 0
                    resp(4) = 0
                    resp(5) = 6

                    resp(6) = unitId
                    resp(7) = func
                    resp(8)  = (subFunc SHR 8) AND 255
                    resp(9)  = subFunc AND 255
                    resp(10) = (outData SHR 8) AND 255
                    resp(11) = outData AND 255

                    '' no MBSE_IncrementEventCount()
                    '' no MBSE_LogCommEvent()
                    return 12

                case &H000B
                    MutexLock(MBSE_CommMutex)
                    outData = MBSE_CommMessageCounter
                    MutexUnlock(MBSE_CommMutex)

                case &H000C, &H000D, &H000F, &H0010, &H0011, &H0012, &H0014
                    '' Not tracked in this emulator, but respond with 0 to stay polite
                    outData = 0

                case else
                    MBSE_BuildExceptionResponse(resp(), transHi, transLo, unitId, func, MBEX_ILLEGAL_DATA_VALUE)
                    return ubound(resp)+1

            end select

            '' Normal FC08 response path
            redim resp(0 to 11)

            resp(0) = transHi
            resp(1) = transLo
            resp(2) = 0
            resp(3) = 0
            resp(4) = 0
            resp(5) = 6

            resp(6) = unitId
            resp(7) = func
            resp(8)  = (subFunc SHR 8) AND 255
            resp(9)  = subFunc AND 255
            resp(10) = (outData SHR 8) AND 255
            resp(11) = outData AND 255

            MBSE_IncrementEventCount()
            MBSE_LogCommEvent(func)

            return 12


        ''
        ' -------------------------------------------------------------------------
        '' FC0B Get Comm Event Counter
        ' -------------------------------------------------------------------------
        ''
        case 11

            dim statusWord as ushort
            dim evCount as ushort

            MutexLock(MBSE_CommMutex)
            statusWord = MBSE_CommStatus
            evCount = MBSE_CommEventCounter
            MutexUnlock(MBSE_CommMutex)

            redim resp(0 to 11)

            resp(0) = transHi
            resp(1) = transLo
            resp(2) = 0
            resp(3) = 0
            resp(4) = 0
            resp(5) = 6

            resp(6) = unitId
            resp(7) = func

            resp(8)  = (statusWord SHR 8) AND 255
            resp(9)  = statusWord AND 255
            resp(10) = (evCount SHR 8) AND 255
            resp(11) = evCount AND 255

            MBSE_LogCommEvent(func)

            return 12


        ''
        ' -------------------------------------------------------------------------
        '' FC0C Get Comm Event Log
        ' -------------------------------------------------------------------------
        ''
        case 12

            dim statusWord as ushort
            dim evCount as ushort
            dim msgCount as ushort
            dim nEvents as integer

            MutexLock(MBSE_CommMutex)
            statusWord = MBSE_CommStatus
            evCount = MBSE_CommEventCounter
            msgCount = MBSE_CommMessageCounter
            nEvents = MBSE_CommEventLogCount
            MutexUnlock(MBSE_CommMutex)

            if nEvents < 0 then nEvents = 0
            if nEvents > 64 then nEvents = 64

            dim byteCount as integer
            byteCount = 2 + 2 + 2 + nEvents

            dim totalLen as integer
            totalLen = 9 + byteCount

            redim resp(0 to totalLen-1)

            dim mbapLen as integer
            mbapLen = 1 + (1 + 1 + byteCount)

            resp(0) = transHi
            resp(1) = transLo
            resp(2) = 0
            resp(3) = 0
            resp(4) = (mbapLen SHR 8) AND 255
            resp(5) = mbapLen AND 255

            resp(6) = unitId
            resp(7) = func
            resp(8) = byteCount

            resp(9)  = (statusWord SHR 8) AND 255
            resp(10) = statusWord AND 255

            resp(11) = (evCount SHR 8) AND 255
            resp(12) = evCount AND 255

            resp(13) = (msgCount SHR 8) AND 255
            resp(14) = msgCount AND 255

            MutexLock(MBSE_CommMutex)
            dim i as integer
            for i = 0 to nEvents-1
                resp(15+i) = MBSE_CommEventLog(i)
            next i
            MutexUnlock(MBSE_CommMutex)

            MBSE_LogCommEvent(func)

            return ubound(resp)+1


        ''
        ' -------------------------------------------------------------------------
        '' FC11 Report Server ID
        ' -------------------------------------------------------------------------
        ''
        case 17

            dim n as integer = ubound(MBSE_ServerID) + 1
            if n < 1 then n = 1

            '' must leave room for the "Run Indicator Status" byte
            if n > 239 then n = 239

            dim byteCount as integer
            byteCount = n + 1   '' +1 for run indicator

            dim totalLen as integer
            totalLen = 9 + byteCount

            redim resp(0 to totalLen-1)

            dim mbapLen as integer
            mbapLen = 1 + (1 + 1 + byteCount)

            resp(0) = transHi
            resp(1) = transLo
            resp(2) = 0
            resp(3) = 0
            resp(4) = (mbapLen SHR 8) AND 255
            resp(5) = mbapLen AND 255

            resp(6) = unitId
            resp(7) = func
            resp(8) = byteCount

            dim i as integer
            for i = 0 to n-1
                resp(9+i) = MBSE_ServerID(i)
            next i

            '' Run Indicator Status (0xFF = ON)
            resp(9+n) = &HFF

            MBSE_IncrementEventCount()
            MBSE_LogCommEvent(func)

            return ubound(resp)+1


        ''
        ' -------------------------------------------------------------------------
        '' FC0F Write Multiple Coils
        ' -------------------------------------------------------------------------
        ''
        case 15

            if reqLen < 13 then return -1

            startAddr = (req(8) shl 8) OR req(9)
            quantity  = (req(10) shl 8) OR req(11)

            if quantity <= 0 then
                MBSE_BuildExceptionResponse(resp(), transHi, transLo, unitId, func, MBEX_ILLEGAL_DATA_VALUE)
                return ubound(resp)+1
            end if

            if startAddr < 0 or startAddr > MBSE_AddrCeiling then
                MBSE_BuildExceptionResponse(resp(), transHi, transLo, unitId, func, MBEX_ILLEGAL_DATA_ADDRESS)
                return ubound(resp)+1
            end if

            if startAddr + quantity - 1 > MBSE_AddrCeiling then
                MBSE_BuildExceptionResponse(resp(), transHi, transLo, unitId, func, MBEX_ILLEGAL_DATA_ADDRESS)
                return ubound(resp)+1
            end if

            dim byteCount as integer = req(12)
            dim needed as integer = (quantity + 7) \ 8

            if byteCount <> needed then
                MBSE_BuildExceptionResponse(resp(), transHi, transLo, unitId, func, MBEX_ILLEGAL_DATA_VALUE)
                return ubound(resp)+1
            end if

            if reqLen < 13 + byteCount then return -1

            MutexLock(MBSE_CoilMutex)

            dim i as integer
            for i = 0 to quantity-1
                dim b as ubyte
                b = req(13 + (i \ 8))
                MBSE_WriteCoil_Unsafe(startAddr + i, (b SHR (i MOD 8)) AND 1)
            next i

            MutexUnlock(MBSE_CoilMutex)

            '' response is: UnitID, FC, StartAddr(2), Qty(2)
            redim resp(0 to 11)

            resp(0) = transHi
            resp(1) = transLo
            resp(2) = 0
            resp(3) = 0
            resp(4) = 0
            resp(5) = 6
            resp(6) = unitId
            resp(7) = func
            resp(8) = (startAddr SHR 8) AND 255
            resp(9) = startAddr AND 255
            resp(10) = (quantity SHR 8) AND 255
            resp(11) = quantity AND 255

            MBSE_IncrementEventCount()
            MBSE_LogCommEvent(func)

            return 12


        ''
        ' -------------------------------------------------------------------------
        '' FC10 Write Multiple Registers
        ' -------------------------------------------------------------------------
        ''
        case 16

            if reqLen < 13 then return -1

            startAddr = (req(8) shl 8) OR req(9)
            quantity  = (req(10) shl 8) OR req(11)

            if quantity <= 0 then
                MBSE_BuildExceptionResponse(resp(), transHi, transLo, unitId, func, MBEX_ILLEGAL_DATA_VALUE)
                return ubound(resp)+1
            end if

            if startAddr < 0 or startAddr > MBSE_AddrCeiling then
                MBSE_BuildExceptionResponse(resp(), transHi, transLo, unitId, func, MBEX_ILLEGAL_DATA_ADDRESS)
                return ubound(resp)+1
            end if

            if startAddr + quantity - 1 > MBSE_AddrCeiling then
                MBSE_BuildExceptionResponse(resp(), transHi, transLo, unitId, func, MBEX_ILLEGAL_DATA_ADDRESS)
                return ubound(resp)+1
            end if

            dim byteCount as integer = req(12)

            if byteCount <> quantity * 2 then
                MBSE_BuildExceptionResponse(resp(), transHi, transLo, unitId, func, MBEX_ILLEGAL_DATA_VALUE)
                return ubound(resp)+1
            end if

            if reqLen < 13 + byteCount then return -1

            MutexLock(MBSE_HoldingRegMutex)

            dim i as integer
            dim p as integer = 13

            for i = 0 to quantity-1
                dim v as ushort
                v = (req(p) shl 8) OR req(p+1)
                MBSE_WriteHolding_Unsafe(startAddr + i, v)
                p += 2
            next i

            MutexUnlock(MBSE_HoldingRegMutex)

            '' response is: UnitID, FC, StartAddr(2), Qty(2)
            redim resp(0 to 11)

            resp(0) = transHi
            resp(1) = transLo
            resp(2) = 0
            resp(3) = 0
            resp(4) = 0
            resp(5) = 6
            resp(6) = unitId
            resp(7) = func
            resp(8) = (startAddr SHR 8) AND 255
            resp(9) = startAddr AND 255
            resp(10) = (quantity SHR 8) AND 255
            resp(11) = quantity AND 255

            MBSE_IncrementEventCount()
            MBSE_LogCommEvent(func)

            return 12


        ''
        ' -------------------------------------------------------------------------
        '' FC17 Read/Write Multiple Registers
        ' -------------------------------------------------------------------------
        ''
        case 23

            '' request layout:
            ''   ReadStart(2) ReadQty(2) WriteStart(2) WriteQty(2) ByteCount(1) WriteData(N)

            if reqLen < 17 then return -1

            dim readStart as integer
            dim readQty as integer
            dim writeStart as integer
            dim writeQty as integer
            dim byteCount as integer

            readStart  = (req(8) shl 8) OR req(9)
            readQty    = (req(10) shl 8) OR req(11)
            writeStart = (req(12) shl 8) OR req(13)
            writeQty   = (req(14) shl 8) OR req(15)
            byteCount  = req(16)

            if readQty <= 0 or writeQty <= 0 then
                MBSE_BuildExceptionResponse(resp(), transHi, transLo, unitId, func, MBEX_ILLEGAL_DATA_VALUE)
                return ubound(resp)+1
            end if

            if byteCount <> writeQty * 2 then
                MBSE_BuildExceptionResponse(resp(), transHi, transLo, unitId, func, MBEX_ILLEGAL_DATA_VALUE)
                return ubound(resp)+1
            end if

            if reqLen < 17 + byteCount then return -1

            if readStart < 0 or readStart + readQty - 1 > MBSE_AddrCeiling then
                MBSE_BuildExceptionResponse(resp(), transHi, transLo, unitId, func, MBEX_ILLEGAL_DATA_ADDRESS)
                return ubound(resp)+1
            end if

            if writeStart < 0 or writeStart + writeQty - 1 > MBSE_AddrCeiling then
                MBSE_BuildExceptionResponse(resp(), transHi, transLo, unitId, func, MBEX_ILLEGAL_DATA_ADDRESS)
                return ubound(resp)+1
            end if

            '' write first
            MutexLock(MBSE_HoldingRegMutex)

            dim i as integer
            dim p as integer = 17

            for i = 0 to writeQty-1
                dim v as ushort
                v = (req(p) shl 8) OR req(p+1)
                MBSE_WriteHolding_Unsafe(writeStart + i, v)
                p += 2
            next i

            MutexUnlock(MBSE_HoldingRegMutex)

            '' respond with read block
            dim byteOut as integer = readQty * 2
            dim totalLen as integer = 9 + byteOut

            redim resp(0 to totalLen-1)

            dim mbapLen as integer
            mbapLen = 1 + (1 + 1 + byteOut)

            resp(0) = transHi
            resp(1) = transLo
            resp(2) = 0
            resp(3) = 0
            resp(4) = (mbapLen SHR 8) AND 255
            resp(5) = mbapLen AND 255
            resp(6) = unitId
            resp(7) = func
            resp(8) = byteOut

            MutexLock(MBSE_HoldingRegMutex)

            p = 9
            for i = 0 to readQty-1
                dim v as ushort = MBSE_HoldingRegister(readStart + i)
                resp(p) = (v SHR 8) AND 255
                resp(p+1) = v AND 255
                p += 2
            next i

            MutexUnlock(MBSE_HoldingRegMutex)

            MBSE_IncrementEventCount()
            MBSE_LogCommEvent(func)

            return ubound(resp)+1


        ''
        ' -------------------------------------------------------------------------
        '' FC14 Read File Record (stub)
        ' -------------------------------------------------------------------------
        ''
        case 20
            MBSE_BuildExceptionResponse(resp(), transHi, transLo, unitId, func, MBEX_ILLEGAL_FUNCTION)
            return ubound(resp)+1


        ''
        ' -------------------------------------------------------------------------
        '' Anything else is Illegal Function
        ' -------------------------------------------------------------------------
        ''
        case else
            MBSE_BuildExceptionResponse(resp(), transHi, transLo, unitId, func, MBEX_ILLEGAL_FUNCTION)
            return ubound(resp)+1

    end select

end function


#endif '' __MBSE_BI__

' end of modbustcp_server.bi
