' -------------------------------------------------------------------------
' Project: FreeBASIC Modbus TCP library
' -------------------------------------------------------------------------
'
' File: modbustcp.bi
'
' Purpose:
'
'     Modbus TCP Client Library for FreeBASIC.
'
' Responsibilities:
'
'      - Establishing and managing TCP connections to Modbus devices.
'      - Encoding Modbus PDUs into MBAP frames.
'      - Decoding responses and handling Modbus exceptions.
'      - Providing high-level functions for reading/writing coils and registers.
'
' This file intentionally does NOT contain:
'
'      - Server-side emulator logic.
'      - Complex multi-device connection management (one connection at a time).
'      - GUI or high-level application logic.
' -------------------------------------------------------------------------

#ifndef __MBTCP_BI__
#define __MBTCP_BI__

' -------------------------------------------------------------------------
' External Headers & Platform Compatibility
' -------------------------------------------------------------------------

#include once "crt/stdio.bi"


' -------------------------------------------------------------------------
' Declarations: Initialization & Connection
' -------------------------------------------------------------------------

declare sub MBTCP_doInit( )
declare sub MBTCP_doShutdown( )

declare sub MBTCP_getHostAndPath _
    ( _
        byref src as string, _
        byref hostname as string, _
        byref path as string _
    )

declare function MBTCP_resolveHost( byref hostname as string ) as integer
declare sub MBTCP_reportError( byref msg as string )

declare sub MBTCP_Init()
declare sub MBTCP_Connect (IPAddress as string)
declare sub MBTCP_Disconnect()
declare sub MBTCP_CloseSocket()

' -------------------------------------------------------------------------
' Declarations: Data Reception & Validation
' -------------------------------------------------------------------------

declare function MBTCP_RecvExact( byval sock as integer, _
                                 byval buf as ubyte ptr, _
                                 byval expected as integer ) as integer
declare function MBTCP_RecvModbusFrame( byval sock as integer, _
                                       buf() as ubyte ) as integer
declare function MBTCP_SendAll( byval sock as integer, _
                               byval buf as ubyte ptr, _
                               byval length as integer ) as integer

declare function MBTCP_CheckFrameCommon( _
        frame() as ubyte, _
        byval expectedFunc as ubyte, _
        byval expectedTransLo as ubyte, _
        outException as integer ) as integer

declare sub MBTCP_SetLastError( byref msg as string )

declare function MBTCP_ValidateAddr16( byval addr as integer, byref what as string ) as integer


' -------------------------------------------------------------------------
' Declarations: Core user-facing Modbus calls
' -------------------------------------------------------------------------

declare function MBTCP_RetrieveCoil (CoilNumber as integer) as integer
declare function MBTCP_RetrieveDiscreteInput (CoilNumber as integer) as integer

declare function MBTCP_RetrieveRegister (RegisterNumber as integer) as integer
declare function MBTCP_RetrieveInputRegister (RegisterNumber as integer) as integer

declare function MBTCP_RetrieveLongRegister (RegisterNumber as integer) as long
declare function MBTCP_RetrieveFloatRegister (RegisterNumber as integer) as single

declare function MBTCP_WriteCoil (Value as integer, CoilNumber as integer) as integer
declare function MBTCP_WriteRegister (Value as short, RegisterNumber as integer) as integer

declare function MBTCP_WriteLongRegister (Value as long, RegisterNumber as integer) as integer
declare function MBTCP_WriteFloatRegister (Value as single, RegisterNumber as integer) as integer

declare function MBTCP_WriteMultipleRegisters (Values() as ushort, StartRegister as integer) as integer
declare function MBTCP_WriteMultipleCoils (Values() as ubyte, StartCoil as integer) as integer


' -------------------------------------------------------------------------
' Declarations: New emulator endpoints
' -------------------------------------------------------------------------

type MBTCP_CommEventCounterResult
    status     as ushort
    eventCount as ushort
end type

type MBTCP_CommEventLogResult
    status       as ushort
    eventCount   as ushort
    messageCount as ushort
    nEvents      as integer
    events(0 to 63) as ubyte
end type

declare function MBTCP_ReadExceptionStatus() as integer

declare function MBTCP_Diagnostics( _
    byval subFunc as ushort, _
    byval inData  as ushort, _
    outData       as ushort ) as integer

declare function MBTCP_GetCommEventCounter( outRes as MBTCP_CommEventCounterResult ) as integer
declare function MBTCP_GetCommEventLog( outRes as MBTCP_CommEventLogResult ) as integer

declare function MBTCP_ReportServerID( byref outId as string ) as integer

declare function MBTCP_ReadWriteMultipleRegisters( _
    readStart as integer, _
    readQty as integer, _
    writeStart as integer, _
    writeValues() as ushort, _
    outReadValues() as ushort ) as integer

declare function MBTCP_MaskWriteRegister( _
    byval registerNumber as integer, _
    byval andMask as ushort, _
    byval orMask as ushort ) as integer


' -------------------------------------------------------------------------
' Error Constants
' -------------------------------------------------------------------------

const MBTCP_COMM_ERROR = -32768


' -------------------------------------------------------------------------
' Debug Support
' -------------------------------------------------------------------------

#ifdef MBTCP_Debug
    declare sub MBTCP_DumpBytes( byref label as string, byval p as ubyte ptr, byval n as integer )
    #define MBTCP_DBG(msg) print "[MBTCP] "; msg
#else
    sub MBTCP_DumpBytes( label as string, p as ubyte ptr, n as integer )
    end sub
    #define MBTCP_DBG(msg)
#endif


' -------------------------------------------------------------------------
' Global State
' -------------------------------------------------------------------------

const MBTCP_INVALID_SOCKET as integer = -1
dim shared MBTCP_Socket as integer = MBTCP_INVALID_SOCKET

dim shared MBTCP_CurrentTransaction as integer
dim shared MBTCP_Connection_Failure as integer
dim shared MBTCP_Socket_Error as integer
dim shared MBTCP_ZeroOffset as integer = 0
dim shared MBTCP_UnitID as integer = 255
dim shared MBTCP_Port as integer = 502
declare sub MBTCP_SetPort(byval port as integer)
sub MBTCP_SetPort(byval port as integer)
MBTCP_Port = port
end sub

dim shared MBTCP_RecvTimeoutMS as integer = 1000   ' default 1 second
dim shared MBTCP_Common_LastError as string



#ifdef MBTCP_Debug

sub MBTCP_DumpBytes( byref label as string, byval p as ubyte ptr, byval n as integer )

    dim i as integer

    print "[MBTCP] "; label; " ("; n; " bytes): ";
    for i = 0 to n-1
        print hex(p[i], 2); " ";
    next i
    print

end sub

#endif



sub MBTCP_SetLastError( byref msg as string )
    MBTCP_Common_LastError = msg
    MBTCP_DBG("LastError = " & msg)
end sub



function MBTCP_ValidateAddr16( byval addr as integer, byref what as string ) as integer

    if addr < 0 or addr > 65535 then
        MBTCP_SetLastError( what & ": address out of range (0..65535): " & addr )
        return 0
    end if

    return 1

end function



sub MBTCP_Init ()
    MBTCP_SetLastError("")
    MBTCP_doInit( )
end sub



sub MBTCP_Connect (hostname as string)

    MBTCP_SetLastError("")
    MBTCP_Connection_Failure = 0
    MBTCP_Socket_Error = 0

    if MBTCP_Socket <> MBTCP_INVALID_SOCKET then
    MBTCP_CloseSocket()
    end if

    MBTCP_Socket = freefile()
    if( OPEN TCP( "host=" & hostname & ",port=" & MBTCP_Port AS #MBTCP_Socket ) <> 0 ) then
        MBTCP_SetLastError("MBTCP_Connect: OPEN TCP failed for '" & hostname & ":" & MBTCP_Port & "'")
        MBTCP_reportError( "MBTCP: OPEN TCP()" )
        MBTCP_Socket = MBTCP_INVALID_SOCKET
        MBTCP_Connection_Failure = 1
        exit sub
    end if

    MBTCP_DBG("Connected successfully")
    MBTCP_DBG("Receive timeout is " & MBTCP_RecvTimeoutMS & " ms (applied in OpenTCP poll loop)")

end sub



sub MBTCP_Disconnect( )
    MBTCP_DBG("Disconnecting socket")

    if MBTCP_Socket <> MBTCP_INVALID_SOCKET then
    MBTCP_CloseSocket()
    end if
end sub



sub MBTCP_CloseSocket()
    if MBTCP_Socket <> MBTCP_INVALID_SOCKET then
        close #MBTCP_Socket
        MBTCP_Socket = MBTCP_INVALID_SOCKET
    end if
end sub


' -------------------------------------------------------------------------
' MBTCP_RecvExact
' -------------------------------------------------------------------------

function MBTCP_RecvExact( byval sock as integer, _
                          byval buf as ubyte ptr, _
                          byval expected as integer ) as integer

    dim as integer total = 0
    dim as integer got
    dim as double startTime
    dim as integer chunkLen
    dim as string chunk
    dim as integer i

    MBTCP_DBG("RecvExact expecting " & expected & " bytes")

    if expected <= 0 then
        return 0
    end if

    if sock = MBTCP_INVALID_SOCKET then
        return 0
    end if

    startTime = timer
    while total < expected

        if eof( sock  ) = 0 then
            chunkLen = expected - total
            if chunkLen > 256 then chunkLen = 256

            chunk = input( chunkLen, #sock )
            got = len( chunk )

            if got > 0 then
                for i = 1 to got
                    buf[ total + i - 1 ] = asc( mid( chunk, i, 1 ) )
                next i

                total += got
            elseif eoc( sock ) <> 0 then
                MBTCP_DBG("RecvExact: connection closed")
                MBTCP_SetLastError("MBTCP_RecvExact: connection closed")
                return 0
            end if

        elseif eoc( sock ) <> 0 then
            MBTCP_DBG("RecvExact: connection closed")
            MBTCP_SetLastError("MBTCP_RecvExact: connection closed")
            return 0
        end if

        if total < expected then
            if ( MBTCP_RecvTimeoutMS > 0 ) then
                if ( (timer - startTime) * 1000.0 >= MBTCP_RecvTimeoutMS ) then
                    MBTCP_DBG("RecvExact: recv timed out")
                    MBTCP_SetLastError("MBTCP_RecvExact: recv() failed or timed out")
                    return 0
                end if
            end if
            sleep 1, 1
        end if

    wend

    return total

end function


function MBTCP_SendAll( byval sock as integer, _
                        byval buf as ubyte ptr, _
                        byval length as integer ) as integer

    dim as integer sent = 0
    dim as ubyte b

    if sock = MBTCP_INVALID_SOCKET then
        return 0
    end if

    while sent < length
        if eoc( sock ) <> 0 then
            return 0
        end if

        b = buf[ sent ]
        put #sock, , b
        sent += 1
    wend

    return 1

end function



' -------------------------------------------------------------------------
' MBTCP_RecvModbusFrame
' -------------------------------------------------------------------------

function MBTCP_RecvModbusFrame( byval sock as integer, _
                               buf() as ubyte ) as integer

    dim as integer got
    dim as ubyte header6(0 to 5)

    got = MBTCP_RecvExact(sock, @header6(0), 6)
    if got <> 6 then
        if MBTCP_Common_LastError = "" then
            MBTCP_SetLastError("MBTCP_RecvModbusFrame: failed reading MBAP header")
        end if
        return MBTCP_COMM_ERROR
    end if

    if header6(2) <> 0 or header6(3) <> 0 then
        MBTCP_SetLastError("MBTCP_RecvModbusFrame: invalid protocol ID")
        return MBTCP_COMM_ERROR
    end if

    dim as ushort lengthField
    lengthField = (cushort(header6(4)) shl 8) or cushort(header6(5))

    if lengthField < 2 then
        MBTCP_SetLastError("MBTCP_RecvModbusFrame: invalid MBAP length field")
        return MBTCP_COMM_ERROR
    end if

    if lengthField > 260 then
        MBTCP_SetLastError("MBTCP_RecvModbusFrame: MBAP length too large")
        return MBTCP_COMM_ERROR
    end if

    redim buf(0 to 6 + lengthField - 1)

    dim i as integer
    for i = 0 to 5
        buf(i) = header6(i)
    next i

    got = MBTCP_RecvExact(sock, @buf(6), lengthField)
    if got <> lengthField then
        if MBTCP_Common_LastError = "" then
            MBTCP_SetLastError("MBTCP_RecvModbusFrame: failed reading full response")
        end if
        return MBTCP_COMM_ERROR
    end if

    return 6 + lengthField

end function



' -------------------------------------------------------------------------
' MBTCP_CheckFrameCommon
' -------------------------------------------------------------------------

function MBTCP_CheckFrameCommon( _
        frame() as ubyte, _
        byval expectedFunc as ubyte, _
        byval expectedTransLo as ubyte, _
        outException as integer ) as integer

    outException = 0

    if (ubound(frame) + 1) < 9 then
        MBTCP_SetLastError("MBTCP_CheckFrameCommon: frame too short")
        return MBTCP_COMM_ERROR
    end if

    if frame(2) <> 0 or frame(3) <> 0 then
        MBTCP_SetLastError("MBTCP_CheckFrameCommon: invalid protocol ID")
        return MBTCP_COMM_ERROR
    end if

    if frame(0) <> 0 or frame(1) <> expectedTransLo then
        MBTCP_SetLastError("MBTCP_CheckFrameCommon: packet dropped -- out of sequence")
        print "MBTCP:Packet dropped -- out of sequence"
        return MBTCP_COMM_ERROR
    end if

    if frame(6) <> (MBTCP_UnitID and 255) then
        MBTCP_SetLastError("MBTCP_CheckFrameCommon: UnitID mismatch")
        return MBTCP_COMM_ERROR
    end if

    if frame(7) = (expectedFunc or &H80) then
        outException = frame(8)
        MBTCP_SetLastError("MBTCP_CheckFrameCommon: PLC exception code " & outException & _
                           " (function " & expectedFunc & ")")
        return MBTCP_COMM_ERROR
    end if

    if frame(7) <> expectedFunc then
        MBTCP_SetLastError("MBTCP_CheckFrameCommon: unexpected function code in response")
        return MBTCP_COMM_ERROR
    end if

    return 0

end function



' -------------------------------------------------------------------------
' Implementation: Core user-facing Modbus calls
' -------------------------------------------------------------------------

function MBTCP_RetrieveDiscreteInput (CoilNumber as integer) as integer

    MBTCP_SetLastError("")

    dim addr as integer
    addr = (CoilNumber - MBTCP_ZeroOffset)

    if MBTCP_ValidateAddr16(addr, "MBTCP_RetrieveDiscreteInput" ) = 0 then
        return MBTCP_COMM_ERROR
    end if

    dim Request as zstring * 13

    MBTCP_CurrentTransaction += 1
    if MBTCP_CurrentTransaction > 255 then MBTCP_CurrentTransaction = 0

    Request = chr (0, MBTCP_CurrentTransaction, _
                   0, 0, _
                   0, 6, _
                   MBTCP_UnitID, _
                   2, _
                   (addr SHR 8) AND 255, addr AND 255, _
                   0, 1)

    if MBTCP_SendAll( MBTCP_Socket, @Request, 12 ) = 0 then
        MBTCP_SetLastError("MBTCP_RetrieveDiscreteInput: send() failed")
        MBTCP_reportError( " MBTCP_DiscreteInput send()" )
    MBTCP_CloseSocket()
        MBTCP_Socket_Error = 1
        return MBTCP_COMM_ERROR
    end if

    dim frame() as ubyte
    dim bytes as integer
    bytes = MBTCP_RecvModbusFrame(MBTCP_Socket, frame())

    if bytes <= 0 then
        if MBTCP_Common_LastError = "" then
            MBTCP_SetLastError("MBTCP_RetrieveDiscreteInput: no response / recv failed")
        end if
        return MBTCP_COMM_ERROR
    end if

    dim ex as integer
    dim rc as integer
    rc = MBTCP_CheckFrameCommon(frame(), 2, MBTCP_CurrentTransaction, ex)
    if rc <> 0 then return rc

    if bytes < 10 then
        MBTCP_SetLastError("MBTCP_RetrieveDiscreteInput: response too short")
        return MBTCP_COMM_ERROR
    end if

    if frame(8) < 1 then
        MBTCP_SetLastError("MBTCP_RetrieveDiscreteInput: invalid bytecount in response")
        return MBTCP_COMM_ERROR
    end if

    return (frame(9) and 1)

end function



function MBTCP_RetrieveCoil (CoilNumber as integer) as integer

    MBTCP_SetLastError("")

    dim addr as integer
    addr = (CoilNumber - MBTCP_ZeroOffset)

    if MBTCP_ValidateAddr16(addr, "MBTCP_RetrieveCoil" ) = 0 then
        return MBTCP_COMM_ERROR
    end if

    dim Request as zstring * 13

    MBTCP_CurrentTransaction += 1
    if MBTCP_CurrentTransaction > 255 then MBTCP_CurrentTransaction = 0

    Request = chr (0, MBTCP_CurrentTransaction, _
                   0, 0, _
                   0, 6, _
                   MBTCP_UnitID, _
                   1, _
                   (addr SHR 8) AND 255, addr AND 255, _
                   0, 1)

    if MBTCP_SendAll( MBTCP_Socket, @Request, 12 ) = 0 then
        MBTCP_SetLastError("MBTCP_RetrieveCoil: send() failed")
        MBTCP_reportError( " MBTCP_RetrieveCoil send()" )
    MBTCP_CloseSocket()
        MBTCP_Socket_Error = 1
        return MBTCP_COMM_ERROR
    end if

    dim frame() as ubyte
    dim bytes as integer
    bytes = MBTCP_RecvModbusFrame(MBTCP_Socket, frame())

    if bytes <= 0 then
        if MBTCP_Common_LastError = "" then
            MBTCP_SetLastError("MBTCP_RetrieveCoil: no response / recv failed")
        end if
        return MBTCP_COMM_ERROR
    end if

    dim ex as integer
    dim rc as integer
    rc = MBTCP_CheckFrameCommon(frame(), 1, MBTCP_CurrentTransaction, ex)
    if rc <> 0 then return rc

    if bytes < 10 then
        MBTCP_SetLastError("MBTCP_RetrieveCoil: response too short")
        return MBTCP_COMM_ERROR
    end if

    if frame(8) < 1 then
        MBTCP_SetLastError("MBTCP_RetrieveCoil: invalid bytecount in response")
        return MBTCP_COMM_ERROR
    end if

    return (frame(9) and 1)

end function



function MBTCP_RetrieveRegister (RegisterNumber as integer) as integer

    MBTCP_SetLastError("")

    dim addr as integer
    addr = (RegisterNumber - MBTCP_ZeroOffset)

    if MBTCP_ValidateAddr16(addr, "MBTCP_RetrieveRegister" ) = 0 then
        return MBTCP_COMM_ERROR
    end if

    dim Request as zstring * 13

    MBTCP_CurrentTransaction += 1
    if MBTCP_CurrentTransaction > 255 then MBTCP_CurrentTransaction = 0

    Request = chr (0, MBTCP_CurrentTransaction, _
                   0, 0, _
                   0, 6, _
                   MBTCP_UnitID, _
                   3, _
                   (addr SHR 8) AND 255, addr AND 255, _
                   0, 1)

    if MBTCP_SendAll( MBTCP_Socket, @Request, 12 ) = 0 then
        MBTCP_SetLastError("MBTCP_RetrieveRegister: send() failed")
        MBTCP_reportError( " MBTCP_RetrieveRegister send()" )
    MBTCP_CloseSocket()
        MBTCP_Socket_Error = 1
        return MBTCP_COMM_ERROR
    end if

    dim frame() as ubyte
    dim bytes as integer
    bytes = MBTCP_RecvModbusFrame(MBTCP_Socket, frame())

    if bytes <= 0 then
        if MBTCP_Common_LastError = "" then
            MBTCP_SetLastError("MBTCP_RetrieveRegister: no response / recv failed")
        end if
        return MBTCP_COMM_ERROR
    end if

    dim ex as integer
    dim rc as integer
    rc = MBTCP_CheckFrameCommon(frame(), 3, MBTCP_CurrentTransaction, ex)
    if rc <> 0 then return rc

    if frame(8) <> 2 then
        MBTCP_SetLastError("MBTCP_RetrieveRegister: invalid bytecount (expected 2)")
        return MBTCP_COMM_ERROR
    end if

    if bytes < 11 then
        MBTCP_SetLastError("MBTCP_RetrieveRegister: response too short")
        return MBTCP_COMM_ERROR
    end if

    return (frame(9) shl 8) or frame(10)

end function



function MBTCP_RetrieveInputRegister (RegisterNumber as integer) as integer

    MBTCP_SetLastError("")

    dim addr as integer
    addr = (RegisterNumber - MBTCP_ZeroOffset)

    if MBTCP_ValidateAddr16(addr, "MBTCP_RetrieveInputRegister" ) = 0 then
        return MBTCP_COMM_ERROR
    end if

    dim Request as zstring * 13

    MBTCP_CurrentTransaction += 1
    if MBTCP_CurrentTransaction > 255 then MBTCP_CurrentTransaction = 0

    Request = chr (0, MBTCP_CurrentTransaction, _
                   0, 0, _
                   0, 6, _
                   MBTCP_UnitID, _
                   4, _
                   (addr SHR 8) AND 255, addr AND 255, _
                   0, 1)

    if MBTCP_SendAll( MBTCP_Socket, @Request, 12 ) = 0 then
        MBTCP_SetLastError("MBTCP_RetrieveInputRegister: send() failed")
        MBTCP_reportError( " MBTCP_RetrieveInputRegister send()" )
    MBTCP_CloseSocket()
        MBTCP_Socket_Error = 1
        return MBTCP_COMM_ERROR
    end if

    dim frame() as ubyte
    dim bytes as integer
    bytes = MBTCP_RecvModbusFrame(MBTCP_Socket, frame())

    if bytes <= 0 then
        if MBTCP_Common_LastError = "" then
            MBTCP_SetLastError("MBTCP_RetrieveInputRegister: no response / recv failed")
        end if
        return MBTCP_COMM_ERROR
    end if

    dim ex as integer
    dim rc as integer
    rc = MBTCP_CheckFrameCommon(frame(), 4, MBTCP_CurrentTransaction, ex)
    if rc <> 0 then return rc

    if frame(8) <> 2 then
        MBTCP_SetLastError("MBTCP_RetrieveInputRegister: invalid bytecount (expected 2)")
        return MBTCP_COMM_ERROR
    end if

    if bytes < 11 then
        MBTCP_SetLastError("MBTCP_RetrieveInputRegister: response too short")
        return MBTCP_COMM_ERROR
    end if

    return (frame(9) shl 8) or frame(10)

end function



function MBTCP_RetrieveLongRegister (RegisterNumber as integer) as long

    MBTCP_SetLastError("")

    dim addr as integer
    addr = (RegisterNumber - MBTCP_ZeroOffset)

    if MBTCP_ValidateAddr16(addr, "MBTCP_RetrieveLongRegister" ) = 0 then
        return MBTCP_COMM_ERROR
    end if

    if MBTCP_ValidateAddr16(addr + 1, "MBTCP_RetrieveLongRegister" ) = 0 then
        return MBTCP_COMM_ERROR
    end if

    dim Request as zstring * 13

    MBTCP_CurrentTransaction += 1
    if MBTCP_CurrentTransaction > 255 then MBTCP_CurrentTransaction = 0

    Request = chr (0, MBTCP_CurrentTransaction, _
                   0, 0, _
                   0, 6, _
                   MBTCP_UnitID, _
                   3, _
                   (addr SHR 8) AND 255, addr AND 255, _
                   0, 2)

    if MBTCP_SendAll( MBTCP_Socket, @Request, 12 ) = 0 then
        MBTCP_SetLastError("MBTCP_RetrieveLongRegister: send() failed")
        MBTCP_reportError( " MBTCP_RetrieveLongRegister send()" )
    MBTCP_CloseSocket()
        MBTCP_Socket_Error = 1
        return MBTCP_COMM_ERROR
    end if

    dim frame() as ubyte
    dim bytes as integer
    bytes = MBTCP_RecvModbusFrame(MBTCP_Socket, frame())

    if bytes <= 0 then
        if MBTCP_Common_LastError = "" then
            MBTCP_SetLastError("MBTCP_RetrieveLongRegister: no response / recv failed")
        end if
        return MBTCP_COMM_ERROR
    end if

    dim ex as integer
    dim rc as integer
    rc = MBTCP_CheckFrameCommon(frame(), 3, MBTCP_CurrentTransaction, ex)
    if rc <> 0 then return rc

    if frame(8) <> 4 then
        MBTCP_SetLastError("MBTCP_RetrieveLongRegister: invalid bytecount (expected 4)")
        return MBTCP_COMM_ERROR
    end if

    if bytes < 13 then
        MBTCP_SetLastError("MBTCP_RetrieveLongRegister: response too short")
        return MBTCP_COMM_ERROR
    end if

    dim as ulong reg0, reg1
    reg0 = (culng(frame(9))  shl 8) or culng(frame(10))
    reg1 = (culng(frame(11)) shl 8) or culng(frame(12))

    dim as ulong raw
    raw = (reg1 shl 16) or reg0

    return cast(long, raw)

end function



function MBTCP_RetrieveFloatRegister (RegisterNumber as integer) as single

    dim v as long
    v = MBTCP_RetrieveLongRegister(RegisterNumber)

    if v = MBTCP_COMM_ERROR then
        return MBTCP_COMM_ERROR
    end if

    return *cptr(single ptr, @v)

end function



' -------------------------------------------------------------------------
' Core Write Functions
' -------------------------------------------------------------------------

function MBTCP_WriteRegister (Value as short, RegisterNumber as integer) as integer

    MBTCP_SetLastError("")

    dim addr as integer
    addr = (RegisterNumber - MBTCP_ZeroOffset)

    if MBTCP_ValidateAddr16(addr, "MBTCP_WriteRegister" ) = 0 then
        return MBTCP_COMM_ERROR
    end if

    dim Request as zstring * 13

    MBTCP_CurrentTransaction += 1
    if MBTCP_CurrentTransaction > 255 then MBTCP_CurrentTransaction = 0

    Request = chr (0, MBTCP_CurrentTransaction, _
                   0, 0, _
                   0, 6, _
                   MBTCP_UnitID, _
                   06, _
                   (addr SHR 8) AND 255, addr AND 255, _
                   (Value SHR 8) AND 255, Value AND 255)

    if MBTCP_SendAll( MBTCP_Socket, @Request, 12 ) = 0 then
        MBTCP_SetLastError("MBTCP_WriteRegister: send() failed")
        MBTCP_reportError( " MBTCP_WriteRegister send()" )
    MBTCP_CloseSocket()
        MBTCP_Socket_Error = 1
        return MBTCP_COMM_ERROR
    end if

    dim frame() as ubyte
    dim bytes as integer
    bytes = MBTCP_RecvModbusFrame(MBTCP_Socket, frame())

    if bytes <= 0 then
        if MBTCP_Common_LastError = "" then
            MBTCP_SetLastError("MBTCP_WriteRegister: no response / recv failed")
        end if
        return MBTCP_COMM_ERROR
    end if

    dim ex as integer
    dim rc as integer
    rc = MBTCP_CheckFrameCommon(frame(), 6, MBTCP_CurrentTransaction, ex)
    if rc <> 0 then return rc

    if bytes <> 12 then
        MBTCP_SetLastError("MBTCP_WriteRegister: expected 12 bytes but got " & bytes)
        return MBTCP_COMM_ERROR
    end if

    dim as integer echoedAddr = (frame(8) shl 8) OR frame(9)
    dim as integer echoedVal  = (frame(10) shl 8) OR frame(11)

    if echoedAddr <> addr then
        MBTCP_SetLastError("MBTCP_WriteRegister: echoed address mismatch")
        return MBTCP_COMM_ERROR
    end if

    if echoedVal <> (cint(Value) AND &HFFFF) then
        MBTCP_SetLastError("MBTCP_WriteRegister: echoed value mismatch")
        return MBTCP_COMM_ERROR
    end if

    return 0

end function



function MBTCP_WriteLongRegister (Value as long, RegisterNumber as integer) as integer

    dim addr as integer
    addr = (RegisterNumber - MBTCP_ZeroOffset)

    if MBTCP_ValidateAddr16(addr, "MBTCP_WriteLongRegister" ) = 0 then
        return MBTCP_COMM_ERROR
    end if

    if MBTCP_ValidateAddr16(addr + 1, "MBTCP_WriteLongRegister" ) = 0 then
        return MBTCP_COMM_ERROR
    end if

    dim rc as integer

    rc = MBTCP_WriteRegister( Value AND &HFFFF, RegisterNumber )
    if rc <> 0 then return rc

    rc = MBTCP_WriteRegister( (Value shr 16) AND &HFFFF, RegisterNumber + 1 )
    if rc <> 0 then return rc

    return 0

end function



function MBTCP_WriteFloatRegister (Value as single, RegisterNumber as integer) as integer
    return MBTCP_WriteLongRegister(*cptr(long ptr, @Value), RegisterNumber)
end function



function MBTCP_WriteCoil (Value as integer, CoilNumber as integer) as integer

    MBTCP_SetLastError("")

    dim addr as integer
    addr = (CoilNumber - MBTCP_ZeroOffset)

    if MBTCP_ValidateAddr16(addr, "MBTCP_WriteCoil" ) = 0 then
        return MBTCP_COMM_ERROR
    end if

    dim Request as zstring * 13

    dim coilValueHi as ubyte
    dim coilValueLo as ubyte

    if Value <> 0 then
        coilValueHi = &HFF
        coilValueLo = &H00
    else
        coilValueHi = &H00
        coilValueLo = &H00
    end if

    MBTCP_CurrentTransaction += 1
    if MBTCP_CurrentTransaction > 255 then MBTCP_CurrentTransaction = 0

    Request = chr (0, MBTCP_CurrentTransaction, _
                   0, 0, _
                   0, 6, _
                   MBTCP_UnitID, _
                   05, _
                   (addr SHR 8) AND 255, addr AND 255, _
                   coilValueHi, coilValueLo)

    if MBTCP_SendAll( MBTCP_Socket, @Request, 12 ) = 0 then
        MBTCP_SetLastError("MBTCP_WriteCoil: send() failed")
        MBTCP_reportError( " MBTCP_WriteCoil send()" )
    MBTCP_CloseSocket()
        MBTCP_Socket_Error = 1
        return MBTCP_COMM_ERROR
    end if

    dim frame() as ubyte
    dim bytes as integer
    bytes = MBTCP_RecvModbusFrame(MBTCP_Socket, frame())

    if bytes <= 0 then
        if MBTCP_Common_LastError = "" then
            MBTCP_SetLastError("MBTCP_WriteCoil: no response / recv failed")
        end if
        return MBTCP_COMM_ERROR
    end if

    dim ex as integer
    dim rc as integer
    rc = MBTCP_CheckFrameCommon(frame(), 5, MBTCP_CurrentTransaction, ex)
    if rc <> 0 then return rc

    if bytes <> 12 then
        MBTCP_SetLastError("MBTCP_WriteCoil: expected 12 bytes but got " & bytes)
        return MBTCP_COMM_ERROR
    end if

    dim as integer echoedAddr = (frame(8) shl 8) OR frame(9)
    if echoedAddr <> addr then
        MBTCP_SetLastError("MBTCP_WriteCoil: echoed address mismatch")
        return MBTCP_COMM_ERROR
    end if

    return 0

end function



function MBTCP_WriteMultipleRegisters (Values() as ushort, StartRegister as integer) as integer

    MBTCP_SetLastError("")

    dim count as integer
    count = ubound(Values) - lbound(Values) + 1

    if count <= 0 then
        MBTCP_SetLastError("MBTCP_WriteMultipleRegisters: invalid value count")
        return MBTCP_COMM_ERROR
    end if

    if count > 123 then
        MBTCP_SetLastError("MBTCP_WriteMultipleRegisters: count too large (max 123)")
        return MBTCP_COMM_ERROR
    end if

    dim addr as integer
    addr = (StartRegister - MBTCP_ZeroOffset)

    if MBTCP_ValidateAddr16(addr, "MBTCP_WriteMultipleRegisters" ) = 0 then
        return MBTCP_COMM_ERROR
    end if

    if MBTCP_ValidateAddr16(addr + count - 1, "MBTCP_WriteMultipleRegisters" ) = 0 then
        return MBTCP_COMM_ERROR
    end if

    dim byteCount as integer
    byteCount = count * 2

    dim mbapLength as integer
    mbapLength = 1 + (1 + 2 + 2 + 1 + byteCount)

    dim packetLen as integer
    packetLen = 7 + (mbapLength - 1)

    dim Request(0 to 511) as ubyte

    MBTCP_CurrentTransaction += 1
    if MBTCP_CurrentTransaction > 255 then MBTCP_CurrentTransaction = 0

    Request(0) = 0
    Request(1) = MBTCP_CurrentTransaction
    Request(2) = 0
    Request(3) = 0
    Request(4) = (mbapLength SHR 8) AND 255
    Request(5) = mbapLength AND 255
    Request(6) = MBTCP_UnitID
    Request(7) = 16

    Request(8) = (addr SHR 8) AND 255
    Request(9) = addr AND 255

    Request(10) = (count SHR 8) AND 255
    Request(11) = count AND 255

    Request(12) = byteCount AND 255

    dim i as integer
    dim p as integer
    p = 13

    for i = lbound(Values) to ubound(Values)
        Request(p)   = (Values(i) SHR 8) AND 255
        Request(p+1) = Values(i) AND 255
        p += 2
    next i

    if MBTCP_SendAll( MBTCP_Socket, @Request(0), packetLen ) = 0 then
        MBTCP_SetLastError("MBTCP_WriteMultipleRegisters: send() failed")
        MBTCP_reportError( " MBTCP_WriteMultipleRegisters send()" )
    MBTCP_CloseSocket()
        MBTCP_Socket_Error = 1
        return MBTCP_COMM_ERROR
    end if

    dim frame() as ubyte
    dim bytes as integer
    bytes = MBTCP_RecvModbusFrame(MBTCP_Socket, frame())

    if bytes <= 0 then
        if MBTCP_Common_LastError = "" then
            MBTCP_SetLastError("MBTCP_WriteMultipleRegisters: no response / recv failed")
        end if
        return MBTCP_COMM_ERROR
    end if

    dim ex as integer
    dim rc as integer
    rc = MBTCP_CheckFrameCommon(frame(), 16, MBTCP_CurrentTransaction, ex)
    if rc <> 0 then return rc

    if bytes <> 12 then
        MBTCP_SetLastError("MBTCP_WriteMultipleRegisters: expected 12 bytes but got " & bytes)
        return MBTCP_COMM_ERROR
    end if

    return 0

end function



function MBTCP_WriteMultipleCoils (Values() as ubyte, StartCoil as integer) as integer

    MBTCP_SetLastError("")

    dim count as integer
    count = ubound(Values) - lbound(Values) + 1

    if count <= 0 then
        MBTCP_SetLastError("MBTCP_WriteMultipleCoils: invalid value count")
        return MBTCP_COMM_ERROR
    end if

    if count > 1968 then
        MBTCP_SetLastError("MBTCP_WriteMultipleCoils: count too large (max 1968)")
        return MBTCP_COMM_ERROR
    end if

    dim addr as integer
    addr = (StartCoil - MBTCP_ZeroOffset)

    if MBTCP_ValidateAddr16(addr, "MBTCP_WriteMultipleCoils" ) = 0 then
        return MBTCP_COMM_ERROR
    end if

    if MBTCP_ValidateAddr16(addr + count - 1, "MBTCP_WriteMultipleCoils" ) = 0 then
        return MBTCP_COMM_ERROR
    end if

    dim byteCount as integer
    byteCount = (count + 7) \ 8

    dim mbapLength as integer
    mbapLength = 1 + (1 + 2 + 2 + 1 + byteCount)

    dim packetLen as integer
    packetLen = 7 + (mbapLength - 1)

    dim Request(0 to 2047) as ubyte

    MBTCP_CurrentTransaction += 1
    if MBTCP_CurrentTransaction > 255 then MBTCP_CurrentTransaction = 0

    Request(0) = 0
    Request(1) = MBTCP_CurrentTransaction
    Request(2) = 0
    Request(3) = 0
    Request(4) = (mbapLength SHR 8) AND 255
    Request(5) = mbapLength AND 255
    Request(6) = MBTCP_UnitID
    Request(7) = 15

    Request(8) = (addr SHR 8) AND 255
    Request(9) = addr AND 255

    Request(10) = (count SHR 8) AND 255
    Request(11) = count AND 255

    Request(12) = byteCount AND 255

    dim i as integer
    dim p as integer
    p = 13

    for i = 0 to byteCount-1
        Request(p+i) = 0
    next i

    dim bitIndex as integer
    bitIndex = 0

    for i = lbound(Values) to ubound(Values)
        if Values(i) <> 0 then
            Request(p + (bitIndex \ 8)) OR= (1 SHL (bitIndex MOD 8))
        end if
        bitIndex += 1
    next i

    if MBTCP_SendAll( MBTCP_Socket, @Request(0), packetLen ) = 0 then
        MBTCP_SetLastError("MBTCP_WriteMultipleCoils: send() failed")
        MBTCP_reportError( " MBTCP_WriteMultipleCoils send()" )
    MBTCP_CloseSocket()
        MBTCP_Socket_Error = 1
        return MBTCP_COMM_ERROR
    end if

    dim frame() as ubyte
    dim bytes as integer
    bytes = MBTCP_RecvModbusFrame(MBTCP_Socket, frame())

    if bytes <= 0 then
        if MBTCP_Common_LastError = "" then
            MBTCP_SetLastError("MBTCP_WriteMultipleCoils: no response / recv failed")
        end if
        return MBTCP_COMM_ERROR
    end if

    dim ex as integer
    dim rc as integer
    rc = MBTCP_CheckFrameCommon(frame(), 15, MBTCP_CurrentTransaction, ex)
    if rc <> 0 then return rc

    if bytes <> 12 then
        MBTCP_SetLastError("MBTCP_WriteMultipleCoils: expected 12 bytes but got " & bytes)
        return MBTCP_COMM_ERROR
    end if

    return 0

end function




function MBTCP_MaskWriteRegister( _
    byval registerNumber as integer, _
    byval andMask as ushort, _
    byval orMask as ushort ) as integer

    MBTCP_SetLastError("")

    dim addr as integer
    addr = (registerNumber - MBTCP_ZeroOffset)

    if MBTCP_ValidateAddr16(addr, "MBTCP_MaskWriteRegister" ) = 0 then
        return MBTCP_COMM_ERROR
    end if

    dim Request(0 to 13) as ubyte

    MBTCP_CurrentTransaction += 1
    if MBTCP_CurrentTransaction > 255 then MBTCP_CurrentTransaction = 0

    Request(0) = 0
    Request(1) = MBTCP_CurrentTransaction
    Request(2) = 0
    Request(3) = 0
    Request(4) = 0
    Request(5) = 8

    Request(6) = MBTCP_UnitID
    Request(7) = 22

    Request(8)  = (addr SHR 8) AND 255
    Request(9)  = addr AND 255

    Request(10) = (andMask SHR 8) AND 255
    Request(11) = andMask AND 255

    Request(12) = (orMask SHR 8) AND 255
    Request(13) = orMask AND 255

    if MBTCP_SendAll( MBTCP_Socket, @Request(0), 14 ) = 0 then
        MBTCP_SetLastError("MBTCP_MaskWriteRegister: send() failed")
        MBTCP_Socket_Error = 1
        return MBTCP_COMM_ERROR
    end if

    dim frame() as ubyte
    dim bytes as integer
    bytes = MBTCP_RecvModbusFrame(MBTCP_Socket, frame())

    if bytes <= 0 then
        if MBTCP_Common_LastError = "" then
            MBTCP_SetLastError("MBTCP_MaskWriteRegister: no response / recv failed")
        end if
        return MBTCP_COMM_ERROR
    end if

    dim ex as integer
    dim rc as integer
    rc = MBTCP_CheckFrameCommon(frame(), 22, MBTCP_CurrentTransaction, ex)
    if rc <> 0 then return rc

    if bytes <> 14 then
        MBTCP_SetLastError("MBTCP_MaskWriteRegister: expected 14 bytes but got " & bytes)
        return MBTCP_COMM_ERROR
    end if

    dim echoedAddr as integer
    echoedAddr = (frame(8) shl 8) OR frame(9)

    if echoedAddr <> addr then
        MBTCP_SetLastError("MBTCP_MaskWriteRegister: echoed address mismatch")
        return MBTCP_COMM_ERROR
    end if

    dim echoedAndMask as ushort
    dim echoedOrMask as ushort

    echoedAndMask = (frame(10) shl 8) OR frame(11)
    echoedOrMask  = (frame(12) shl 8) OR frame(13)

    if echoedAndMask <> andMask then
        MBTCP_SetLastError("MBTCP_MaskWriteRegister: echoed AND mask mismatch")
        return MBTCP_COMM_ERROR
    end if

    if echoedOrMask <> orMask then
        MBTCP_SetLastError("MBTCP_MaskWriteRegister: echoed OR mask mismatch")
        return MBTCP_COMM_ERROR
    end if

    return 0

end function



' -------------------------------------------------------------------------
' Emulator extensions (FC07 / FC08 / FC0B / FC0C / FC11 / FC17)
' -------------------------------------------------------------------------

function MBTCP_ReadExceptionStatus() as integer

    MBTCP_SetLastError("")

    dim Request as zstring * 13

    MBTCP_CurrentTransaction += 1
    if MBTCP_CurrentTransaction > 255 then MBTCP_CurrentTransaction = 0

    Request = chr(0, MBTCP_CurrentTransaction, _
                  0, 0, _
                  0, 2, _
                  MBTCP_UnitID, _
                  7)

    if MBTCP_SendAll( MBTCP_Socket, @Request, 8 ) = 0 then
        MBTCP_SetLastError("MBTCP_ReadExceptionStatus: send() failed")
        MBTCP_Socket_Error = 1
        return MBTCP_COMM_ERROR
    end if

    dim frame() as ubyte
    dim bytes as integer
    bytes = MBTCP_RecvModbusFrame(MBTCP_Socket, frame())

    if bytes <= 0 then
        MBTCP_SetLastError("MBTCP_ReadExceptionStatus: no response")
        return MBTCP_COMM_ERROR
    end if

    dim ex as integer
    dim rc as integer
    rc = MBTCP_CheckFrameCommon(frame(), 7, MBTCP_CurrentTransaction, ex)
    if rc <> 0 then return rc

    if bytes < 10 then
        MBTCP_SetLastError("MBTCP_ReadExceptionStatus: response too short")
        return MBTCP_COMM_ERROR
    end if

    if frame(8) <> 1 then
        MBTCP_SetLastError("MBTCP_ReadExceptionStatus: invalid bytecount (expected 1)")
        return MBTCP_COMM_ERROR
    end if

    return frame(9)

end function



function MBTCP_Diagnostics( _
    byval subFunc as ushort, _
    byval inData  as ushort, _
    outData       as ushort ) as integer

    MBTCP_SetLastError("")
    outData = 0

    dim Request(0 to 11) as ubyte

    MBTCP_CurrentTransaction += 1
    if MBTCP_CurrentTransaction > 255 then MBTCP_CurrentTransaction = 0

    Request(0) = 0
    Request(1) = MBTCP_CurrentTransaction
    Request(2) = 0
    Request(3) = 0
    Request(4) = 0
    Request(5) = 6
    Request(6) = MBTCP_UnitID
    Request(7) = 8
    Request(8) = (subFunc SHR 8) AND 255
    Request(9) = subFunc AND 255
    Request(10) = (inData SHR 8) AND 255
    Request(11) = inData AND 255

    if MBTCP_SendAll( MBTCP_Socket, @Request(0), 12 ) = 0 then
        MBTCP_SetLastError("MBTCP_Diagnostics: send() failed")
        MBTCP_Socket_Error = 1
        return MBTCP_COMM_ERROR
    end if

    dim frame() as ubyte
    dim bytes as integer
    bytes = MBTCP_RecvModbusFrame(MBTCP_Socket, frame())

    if bytes <= 0 then
        MBTCP_SetLastError("MBTCP_Diagnostics: no response")
        return MBTCP_COMM_ERROR
    end if

    dim ex as integer
    dim rc as integer
    rc = MBTCP_CheckFrameCommon(frame(), 8, MBTCP_CurrentTransaction, ex)
    if rc <> 0 then return rc

    if bytes < 12 then
        MBTCP_SetLastError("MBTCP_Diagnostics: response too short")
        return MBTCP_COMM_ERROR
    end if

    outData = (frame(10) shl 8) OR frame(11)
    return 0

end function



function MBTCP_GetCommEventCounter( outRes as MBTCP_CommEventCounterResult ) as integer

    MBTCP_SetLastError("")
    outRes.status = 0
    outRes.eventCount = 0

    dim Request as zstring * 13

    MBTCP_CurrentTransaction += 1
    if MBTCP_CurrentTransaction > 255 then MBTCP_CurrentTransaction = 0

    Request = chr(0, MBTCP_CurrentTransaction, _
                  0, 0, _
                  0, 2, _
                  MBTCP_UnitID, _
                  11)

    if MBTCP_SendAll( MBTCP_Socket, @Request, 8 ) = 0 then
        MBTCP_SetLastError("MBTCP_GetCommEventCounter: send() failed")
        MBTCP_Socket_Error = 1
        return MBTCP_COMM_ERROR
    end if

    dim frame() as ubyte
    dim bytes as integer
    bytes = MBTCP_RecvModbusFrame(MBTCP_Socket, frame())

    if bytes <= 0 then
        MBTCP_SetLastError("MBTCP_GetCommEventCounter: no response")
        return MBTCP_COMM_ERROR
    end if

    dim ex as integer
    dim rc as integer
    rc = MBTCP_CheckFrameCommon(frame(), 11, MBTCP_CurrentTransaction, ex)
    if rc <> 0 then return rc

    if bytes < 12 then
        MBTCP_SetLastError("MBTCP_GetCommEventCounter: response too short")
        return MBTCP_COMM_ERROR
    end if

    outRes.status = (frame(8) shl 8) OR frame(9)
    outRes.eventCount = (frame(10) shl 8) OR frame(11)

    return 0

end function



function MBTCP_GetCommEventLog( outRes as MBTCP_CommEventLogResult ) as integer

    MBTCP_SetLastError("")

    outRes.status = 0
    outRes.eventCount = 0
    outRes.messageCount = 0
    outRes.nEvents = 0

    dim i as integer
    for i = 0 to 63
        outRes.events(i) = 0
    next i

    dim Request as zstring * 13

    MBTCP_CurrentTransaction += 1
    if MBTCP_CurrentTransaction > 255 then MBTCP_CurrentTransaction = 0

    Request = chr(0, MBTCP_CurrentTransaction, _
                  0, 0, _
                  0, 2, _
                  MBTCP_UnitID, _
                  12)

    if MBTCP_SendAll( MBTCP_Socket, @Request, 8 ) = 0 then
        MBTCP_SetLastError("MBTCP_GetCommEventLog: send() failed")
        MBTCP_Socket_Error = 1
        return MBTCP_COMM_ERROR
    end if

    dim frame() as ubyte
    dim bytes as integer
    bytes = MBTCP_RecvModbusFrame(MBTCP_Socket, frame())

    if bytes <= 0 then
        MBTCP_SetLastError("MBTCP_GetCommEventLog: no response")
        return MBTCP_COMM_ERROR
    end if

    dim ex as integer
    dim rc as integer
    rc = MBTCP_CheckFrameCommon(frame(), 12, MBTCP_CurrentTransaction, ex)
    if rc <> 0 then return rc

    if bytes < 15 then
        MBTCP_SetLastError("MBTCP_GetCommEventLog: response too short")
        return MBTCP_COMM_ERROR
    end if

    dim byteCount as integer
    byteCount = frame(8)

    if bytes < (9 + byteCount) then
        MBTCP_SetLastError("MBTCP_GetCommEventLog: truncated response")
        return MBTCP_COMM_ERROR
    end if

    outRes.status = (frame(9) shl 8) OR frame(10)
    outRes.eventCount = (frame(11) shl 8) OR frame(12)
    outRes.messageCount = (frame(13) shl 8) OR frame(14)

    dim nEvents as integer
    nEvents = byteCount - 6

    if nEvents < 0 then nEvents = 0
    if nEvents > 64 then nEvents = 64

    outRes.nEvents = nEvents

    for i = 0 to nEvents-1
        outRes.events(i) = frame(15 + i)
    next i

    return 0

end function



function MBTCP_ReportServerID( byref outId as string ) as integer

    MBTCP_SetLastError("")
    outId = ""

    dim Request as zstring * 13

    MBTCP_CurrentTransaction += 1
    if MBTCP_CurrentTransaction > 255 then MBTCP_CurrentTransaction = 0

    Request = chr(0, MBTCP_CurrentTransaction, _
                  0, 0, _
                  0, 2, _
                  MBTCP_UnitID, _
                  17)

    if MBTCP_SendAll( MBTCP_Socket, @Request, 8 ) = 0 then
        MBTCP_SetLastError("MBTCP_ReportServerID: send() failed")
        MBTCP_Socket_Error = 1
        return MBTCP_COMM_ERROR
    end if

    dim frame() as ubyte
    dim bytes as integer
    bytes = MBTCP_RecvModbusFrame(MBTCP_Socket, frame())

    if bytes <= 0 then
        MBTCP_SetLastError("MBTCP_ReportServerID: no response")
        return MBTCP_COMM_ERROR
    end if

    dim ex as integer
    dim rc as integer
    rc = MBTCP_CheckFrameCommon(frame(), 17, MBTCP_CurrentTransaction, ex)
    if rc <> 0 then return rc

    if bytes < 10 then
        MBTCP_SetLastError("MBTCP_ReportServerID: response too short")
        return MBTCP_COMM_ERROR
    end if

    dim byteCount as integer
    byteCount = frame(8)

    if byteCount < 1 then
        MBTCP_SetLastError("MBTCP_ReportServerID: invalid bytecount")
        return MBTCP_COMM_ERROR
    end if

    if bytes < (9 + byteCount) then
        MBTCP_SetLastError("MBTCP_ReportServerID: truncated response")
        return MBTCP_COMM_ERROR
    end if

    dim idLen as integer
    idLen = byteCount - 1
    if idLen < 0 then idLen = 0

    dim s as string = ""
    dim i as integer

    for i = 0 to idLen-1
        s &= chr(frame(9+i))
    next i

    outId = s
    return 0

end function



function MBTCP_ReadWriteMultipleRegisters( _
    readStart as integer, _
    readQty as integer, _
    writeStart as integer, _
    writeValues() as ushort, _
    outReadValues() as ushort ) as integer

    MBTCP_SetLastError("")

    dim writeQty as integer
    writeQty = ubound(writeValues) - lbound(writeValues) + 1

    if readQty <= 0 then
        MBTCP_SetLastError("MBTCP_ReadWriteMultipleRegisters: invalid readQty")
        return MBTCP_COMM_ERROR
    end if

    if writeQty <= 0 then
        MBTCP_SetLastError("MBTCP_ReadWriteMultipleRegisters: invalid writeQty")
        return MBTCP_COMM_ERROR
    end if

    if readQty > 125 then
        MBTCP_SetLastError("MBTCP_ReadWriteMultipleRegisters: readQty too large (max 125)")
        return MBTCP_COMM_ERROR
    end if

    if writeQty > 121 then
        MBTCP_SetLastError("MBTCP_ReadWriteMultipleRegisters: writeQty too large (max 121)")
        return MBTCP_COMM_ERROR
    end if

    dim readAddr as integer
    dim writeAddr as integer

    readAddr = readStart - MBTCP_ZeroOffset
    writeAddr = writeStart - MBTCP_ZeroOffset

    if MBTCP_ValidateAddr16(readAddr, "MBTCP_ReadWriteMultipleRegisters" ) = 0 then
        return MBTCP_COMM_ERROR
    end if

    if MBTCP_ValidateAddr16(writeAddr, "MBTCP_ReadWriteMultipleRegisters" ) = 0 then
        return MBTCP_COMM_ERROR
    end if

    if MBTCP_ValidateAddr16(readAddr + readQty - 1, "MBTCP_ReadWriteMultipleRegisters" ) = 0 then
        return MBTCP_COMM_ERROR
    end if

    if MBTCP_ValidateAddr16(writeAddr + writeQty - 1, "MBTCP_ReadWriteMultipleRegisters" ) = 0 then
        return MBTCP_COMM_ERROR
    end if

    dim byteCount as integer
    byteCount = writeQty * 2

    dim mbapLength as integer
    mbapLength = 1 + (1 + 2 + 2 + 2 + 2 + 1 + byteCount)

    dim packetLen as integer
    packetLen = 7 + (mbapLength - 1)

    dim Request(0 to 1023) as ubyte

    MBTCP_CurrentTransaction += 1
    if MBTCP_CurrentTransaction > 255 then MBTCP_CurrentTransaction = 0

    Request(0) = 0
    Request(1) = MBTCP_CurrentTransaction
    Request(2) = 0
    Request(3) = 0
    Request(4) = (mbapLength SHR 8) AND 255
    Request(5) = mbapLength AND 255
    Request(6) = MBTCP_UnitID
    Request(7) = 23

    Request(8)  = (readAddr SHR 8) AND 255
    Request(9)  = readAddr AND 255
    Request(10) = (readQty SHR 8) AND 255
    Request(11) = readQty AND 255

    Request(12) = (writeAddr SHR 8) AND 255
    Request(13) = writeAddr AND 255
    Request(14) = (writeQty SHR 8) AND 255
    Request(15) = writeQty AND 255

    Request(16) = byteCount AND 255

    dim p as integer = 17
    dim i as integer

    for i = lbound(writeValues) to ubound(writeValues)
        Request(p) = (writeValues(i) SHR 8) AND 255
        Request(p+1) = writeValues(i) AND 255
        p += 2
    next i

    if MBTCP_SendAll( MBTCP_Socket, @Request(0), packetLen ) = 0 then
        MBTCP_SetLastError("MBTCP_ReadWriteMultipleRegisters: send() failed")
        MBTCP_Socket_Error = 1
        return MBTCP_COMM_ERROR
    end if

    dim frame() as ubyte
    dim bytes as integer
    bytes = MBTCP_RecvModbusFrame(MBTCP_Socket, frame())

    if bytes <= 0 then
        MBTCP_SetLastError("MBTCP_ReadWriteMultipleRegisters: no response")
        return MBTCP_COMM_ERROR
    end if

    dim ex as integer
    dim rc as integer
    rc = MBTCP_CheckFrameCommon(frame(), 23, MBTCP_CurrentTransaction, ex)
    if rc <> 0 then return rc

    if bytes < 10 then
        MBTCP_SetLastError("MBTCP_ReadWriteMultipleRegisters: response too short")
        return MBTCP_COMM_ERROR
    end if

    dim respByteCount as integer
    respByteCount = frame(8)

    if respByteCount <> (readQty * 2) then
        MBTCP_SetLastError("MBTCP_ReadWriteMultipleRegisters: invalid bytecount")
        return MBTCP_COMM_ERROR
    end if

    if bytes < (9 + respByteCount) then
        MBTCP_SetLastError("MBTCP_ReadWriteMultipleRegisters: truncated response")
        return MBTCP_COMM_ERROR
    end if

    redim outReadValues(0 to readQty-1)

    p = 9
    for i = 0 to readQty-1
        outReadValues(i) = (frame(p) shl 8) OR frame(p+1)
        p += 2
    next i

    return 0

end function



' -------------------------------------------------------------------------
' Implementation: Resolution & Error Reporting
' -------------------------------------------------------------------------

sub MBTCP_getHostAndPath _
    ( _
        byref src as string, _
        byref hostname as string, _
        byref path as string _
    )

    dim p as integer = instr( src, " " )
    if( p = 0 or p = len( src ) ) then
        hostname = trim( src )
        path = ""
    else
        hostname = trim( left( src, p-1 ) )
        path = trim( mid( src, p+1 ) )
    end if

end sub



function MBTCP_resolveHost( byref hostname as string ) as integer

    hostname = trim( hostname )

    if len( hostname ) = 0 then
        return 0
    end if

    return 1

end function



sub MBTCP_reportError( byref msg as string )
    print msg
end sub



sub MBTCP_doInit( )
end sub



sub MBTCP_doShutdown( )
end sub



#endif '' __MBTCP_BI__

' end of modbustcp.bi
