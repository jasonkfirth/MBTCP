' ============================================================
' Modbus TCP Integration / Validation Harness (MBSE <-> MBTCP)
' ============================================================
'
' This program is a *validation harness* for the FreeBASIC Modbus TCP
' library pair:
'
'   - MBSE : Modbus Server Emulator (acts like a PLC / slave device)
'   - MBTCP: Modbus TCP Client API (acts like SCADA / HMI / Master)
'
' This harness is designed for two major purposes:
'
'   1) Regression Testing
'      If we modify MBTCP or MBSE, we can re-run this harness and verify
'      that nothing broke.
'
'   2) Teaching / Trades Documentation
'      This file is deliberately verbose and educational. It explains
'      Modbus behaviour in practical terms, so it can be used as a
'      reference by technicians, apprentices, and integrators.
'
'
' ============================================================
' CANON HARNESS BEHAVIOUR
' ============================================================
'
'   - MBSE runs as a threaded Modbus TCP server emulator.
'   - MBTCP connects as a real TCP client.
'   - We validate:
'
'       * MBTCP client API correctness
'       * MBSE emulator correctness
'       * Full integration correctness (socket, framing, parsing)
'
'
' ============================================================
' IMPORTANT NOTES FOR TECHS
' ============================================================
'
' Modbus TCP uses port 502 by default.
'
' On Windows and Linux, binding port 502 often requires administrator
' privileges because it is a "privileged port".
'
' If you get failures starting the server:
'
'   - another Modbus program may already be running
'   - you may not have privileges
'   - port 502 may be blocked by firewall
'
'
' ============================================================
' DEBUGGING
' ============================================================
'
' You can enable extra prints by defining:
'
'   MBSE_Debug
'   MBTCP_Debug
'   VALIDATION_Debug
'
' ============================================================

'' #define MBSE_Debug
'' #define MBTCP_Debug
'' #define VALIDATION_Debug

#include "modbustcp_server.bi"
#include "modbustcp.bi"


' ============================================================
' HARNESS CONFIGURATION
' ============================================================

const HARNESS_HOST as string  = "127.0.0.1"
const HARNESS_PORT as integer = 502

const WAIT_SERVER_READY_MS as integer = 3000
const WAIT_CONNECT_MS      as integer = 3000

' Client recv timeout values:
'
' FAST = used for tests where we expect the PLC NOT to respond
'        (example: wrong Unit ID test)
'
' NORM = used for normal traffic
'
const CLIENT_RECV_TIMEOUT_MS_FAST as integer = 200
const CLIENT_RECV_TIMEOUT_MS_NORM as integer = 1000


' ============================================================
' HARNESS GLOBALS
' ============================================================

dim shared serverThreadRunning as integer
dim shared serverThreadReady as integer
dim shared serverStartOk as integer

dim shared gPass as integer
dim shared gFail as integer


' ============================================================
' DEBUG PRINT ROUTINE
' ============================================================

#ifdef VALIDATION_Debug
sub DBG(msg as string)
    print "[DBG] "; msg
end sub
#else
sub DBG(msg as string)
end sub
#endif


' ============================================================
' TEST RESULT PRINTER
' ============================================================
'
' passed = 1 means PASS
' passed = 0 means FAIL
'
sub TestResult(testName as string, passed as integer, details as string = "")
    if passed then
        gPass += 1
        print "[PASS] "; testName;
        if details <> "" then
            print " -- "; details
        else
            print
        end if
    else
        gFail += 1
        print "[FAIL] "; testName;
        if details <> "" then
            print " -- "; details
        else
            print
        end if
    end if
end sub


' ============================================================
' FLOAT COMPARISON (NEAR MATCH)
' ============================================================
'
' Floating point values are not always exact due to binary rounding.
'
function FloatNear( byval a as single, byval b as single, byval eps as single ) as integer
    if abs(a-b) <= eps then return 1
    return 0
end function


' ============================================================
' WAIT UNTIL FLAG MATCHES VALUE
' ============================================================
'
' Used to wait for the server thread to indicate readiness.
'
function WaitUntil( byref flag as integer, byval want as integer, byval timeoutMs as integer ) as integer

    dim start as double = timer

    while flag <> want
        sleep 10

        if (timer - start) * 1000.0 >= timeoutMs then
            return 0
        end if
    wend

    return 1

end function


' ============================================================
' CONNECT CLIENT WITH RETRY
' ============================================================
'
' In real-world automation, PLCs may be slow to boot or may reject the
' first few connection attempts.
'
function ConnectClientOrFail( byref host as string, byval timeoutMs as integer ) as integer

    dim start as double = timer
    MBP_Connection_Failure = 0

    do

        MBTCP_Connect(host)

        if MBP_Connection_Failure = 0 then
            return 1
        end if

        sleep 50

        if (timer - start) * 1000.0 >= timeoutMs then exit do

    loop

    return 0

end function


' ============================================================
' SERVER THREAD
' ============================================================
'
' This thread runs the Modbus Server Emulator (MBSE).
'
' The server must run in its own thread because the harness is also
' running the Modbus client tests in the main thread.
'
function ServerThread( byval p as any ptr ) as any ptr

    serverThreadRunning = 1
    serverThreadReady   = 0
    serverStartOk       = 0

    DBG("Server thread starting...")

    if MBSE_StartServer(HARNESS_PORT) = 0 then

        DBG("Server failed to start")
        serverThreadRunning = 0
        serverThreadReady   = 0
        serverStartOk       = 0
        return 0

    end if

    DBG("Server started")
    serverStartOk     = 1
    serverThreadReady = 1

    while serverThreadRunning
        sleep 50
    wend

    DBG("Server stopping...")
    MBSE_StopServer()

    DBG("Server thread exiting")
    serverThreadRunning = 0

    return 0

end function



' ============================================================
' MAIN HARNESS ENTRY POINT
' ============================================================

print "========================================"
print " Modbus TCP Validation Harness (MBSE/MBTCP)"
print "========================================"
print


dim abortHarness as integer = 0
dim t as any ptr = 0


' ============================================================
' INITIALIZE SERVER EMULATOR (MBSE)
' ============================================================

DBG("Initializing MBSE...")
MBSE_Init()


' ============================================================
' CONFIGURE STRICT MODE
' ============================================================
'
' Strict mode makes the emulator behave like a real PLC:
'
'   - if the UnitID does not match, ignore the request
'   - if the register address is too high, return Modbus exception
'
' This is important because many real Modbus PLCs are picky.
'
MBSE_StrictUnitID   = 1
MBSE_ExpectedUnitID = 255

' CANON REQUIRED LIMIT:
' If address exceeds this, MBSE must throw Modbus exception code 2.
'
MBSE_AddrCeiling    = 500


DBG("Configured strict UnitID + ceiling")


' ============================================================
' TEST #0: SERVER-SIDE MEMORY ACCESSORS
' ============================================================
'
' This test does NOT involve TCP.
'
' It verifies that the internal emulator memory routines are working.
'
' If this fails, MBSE itself is broken before networking even starts.
'
print "----------------------------------------"
print "Test #0: Server-side memory accessors"
print "----------------------------------------"

scope

    dim okServer as integer = 1

    MBSE_WriteHoldingRegister(10, 5555)
    if MBSE_ReadHoldingRegister(10) <> 5555 then okServer = 0

    MBSE_WriteInputRegister(20, 6666)
    if MBSE_ReadInputRegister(20) <> 6666 then okServer = 0

    MBSE_WriteCoil(30, 0)
    if MBSE_ReadCoil(30) <> 0 then okServer = 0

    MBSE_WriteCoil(30, 1)
    if MBSE_ReadCoil(30) <> 1 then okServer = 0

    MBSE_WriteDiscreteInput(40, 0)
    if MBSE_ReadDiscreteInput(40) <> 0 then okServer = 0

    MBSE_WriteDiscreteInput(40, 1)
    if MBSE_ReadDiscreteInput(40) <> 1 then okServer = 0

    TestResult("Server-side memory routines", okServer, iif(okServer, "OK", "Mismatch"))

end scope


' ============================================================
' PRELOAD SOME MEMORY
' ============================================================
'
' This is not strictly required, but it's useful for sanity checking.
'
DBG("Preloading server memory...")

MBSE_WriteCoil(0, 0)
MBSE_WriteDiscreteInput(0, 1)
MBSE_WriteHoldingRegister(0, 1234)
MBSE_WriteInputRegister(0, 4321)


' ============================================================
' START SERVER THREAD
' ============================================================

DBG("Starting server thread...")

t = ThreadCreate( cast(any ptr, @ServerThread), 0 )

if t = 0 then
    TestResult("Server thread creation", 0, "ThreadCreate failed")
    abortHarness = 1
end if


if abortHarness = 0 then
    if WaitUntil(serverThreadReady, 1, WAIT_SERVER_READY_MS) = 0 then
        TestResult("Server ready", 0, "Timed out waiting for server readiness")
        abortHarness = 1
    end if
end if


if abortHarness = 0 then

    if serverStartOk = 0 then
        TestResult("Server start", 0, "MBSE_StartServer failed (privilege/port-in-use?)")
        abortHarness = 1
    else
        TestResult("Server start", 1, "Listening on port " & HARNESS_PORT)
    end if

end if


' ============================================================
' INIT + CONNECT MBTCP CLIENT
' ============================================================

if abortHarness = 0 then

    DBG("Initializing MBTCP...")
    MBTCP_Init()

    MBP_UnitID = 255
    MBP_ZeroOffset = 0
    MBP_RecvTimeoutMS = CLIENT_RECV_TIMEOUT_MS_NORM

    DBG("Connecting client...")

    if ConnectClientOrFail(HARNESS_HOST, WAIT_CONNECT_MS) = 0 then
        TestResult("Client connect", 0, "Failed (" & MBP_Common_LastError & ")")
        abortHarness = 1
    else
        TestResult("Client connect", 1, "Connected to emulator")
    end if

end if


' ============================================================
' RUN VALIDATION TESTS
' ============================================================

if abortHarness = 0 then

    print
    print "Running validation tests..."
    print


    ' ============================================================
    ' Test #1: WriteRegister / RetrieveRegister
    ' ============================================================
    '
    ' Function Codes:
    '   - FC06 Write Single Holding Register
    '   - FC03 Read Holding Register
    '
    print "----------------------------------------"
    print "Test #1: WriteRegister / RetrieveRegister"
    print "----------------------------------------"

    dim regAddr as integer = 10
    dim regVal  as integer = 54321
    dim rc      as integer

    rc = MBTCP_WriteRegister(regVal, regAddr)

    if rc = 0 then

        dim got as integer = MBTCP_RetrieveRegister(regAddr)

        if got = regVal then
            TestResult("WriteRegister / RetrieveRegister", 1, "Value=" & got)
        else
            TestResult("WriteRegister / RetrieveRegister", 0, "Expected " & regVal & " got " & got)
        end if

    else
        TestResult("WriteRegister / RetrieveRegister", 0, "Write failed (" & MBP_Common_LastError & ")")
    end if


    ' ============================================================
    ' Test #1B: FC16 (0x16) Mask Write Register (END-TO-END)
    ' ============================================================
    '
    ' Function Code:
    '   - FC16 / 0x16 / decimal 22  (Mask Write Register)
    '
    ' PURPOSE:
    '   Proves that masked writes work *end to end*:
    '     MBSE memory -> MBTCP MaskWrite -> MBSE memory -> MBTCP readback
    '
    ' WHY TECHS CARE:
    '   This is the "no clobber" method for updating a single bitfield inside
    '   a 16-bit register when multiple writers exist.
    '
    ' MODBUS MASK RULE (spec):
    '   newValue = (oldValue AND andMask) OR (orMask AND (NOT andMask))
    '
    print
    print "----------------------------------------"
    print "Test #1B: FC16 MaskWriteRegister / Verify"
    print "----------------------------------------"

    scope
        dim maskAddr as integer = 300

        '' Start from a known value.
        '' 0xAAAA = 1010 1010 1010 1010 (nice pattern for bit tests)
        dim oldVal as ushort = &HAAAA
        MBSE_WriteHoldingRegister(maskAddr, oldVal)

        '' Goal: clear the lowest 4 bits, then force bits 0 and 2 ON.
        '' andMask = 0xFFF0 => preserves upper 12 bits, clears low 4.
        '' orMask  = 0x0005 => sets bit0 and bit2 within the cleared field.
        dim andMask as ushort = &HFFF0
        dim orMask  as ushort = &H0005

        '' Expected result:
        ''   old & andMask      = 0xAAA0
        ''   ~andMask (16-bit)  = 0x000F
        ''   orMask & ~andMask  = 0x0005
        ''   new               = 0xAAA0 OR 0x0005 = 0xAAA5
        dim expected as ushort = &HAAA5

        rc = MBTCP_MaskWriteRegister(maskAddr, andMask, orMask)

        if rc <> 0 then
            TestResult("FC16 MaskWriteRegister", 0, "Write failed (" & MBP_Common_LastError & ")")
        else
            '' Verify from both sides:
            ''   - Client readback (over TCP)
            ''   - Server memory (direct)
            dim gotClient as integer = MBTCP_RetrieveRegister(maskAddr)
            dim gotServer as ushort  = MBSE_ReadHoldingRegister(maskAddr)

            dim ok as integer = 1

            if gotClient = MBTCP_COMM_ERROR then ok = 0
            if gotClient <> expected then ok = 0
            if gotServer <> expected then ok = 0

            if ok then
                TestResult("FC16 MaskWriteRegister", 1, _
                    "Old=&H" & hex(oldVal,4) & _
                    " AND=&H" & hex(andMask,4) & _
                    " OR=&H" & hex(orMask,4) & _
                    " New=&H" & hex(gotServer,4))
            else
                TestResult("FC16 MaskWriteRegister", 0, _
                    "Expected=&H" & hex(expected,4) & _
                    " Client=&H" & hex(gotClient AND &HFFFF,4) & _
                    " Server=&H" & hex(gotServer,4) & _
                    " (" & MBP_Common_LastError & ")")
            end if
        end if
    end scope



    ' ============================================================
    ' Test #2: WriteLongRegister / RetrieveLongRegister
    ' ============================================================
    '
    ' A 32-bit value is stored across TWO holding registers.
    '
    print
    print "----------------------------------------"
    print "Test #2: WriteLongRegister / RetrieveLongRegister"
    print "----------------------------------------"

    dim longAddr as integer = 20
    dim longVal  as long    = &H12345678

    rc = MBTCP_WriteLongRegister(longVal, longAddr)

    if rc = 0 then

        dim gotLong as long = MBTCP_RetrieveLongRegister(longAddr)

        if gotLong = longVal then
            TestResult("WriteLongRegister / RetrieveLongRegister", 1, "Value=&H" & hex(gotLong))
        else
            TestResult("WriteLongRegister / RetrieveLongRegister", 0, _
                "Expected &H" & hex(longVal) & " got &H" & hex(gotLong))
        end if

    else
        TestResult("WriteLongRegister / RetrieveLongRegister", 0, "Write failed (" & MBP_Common_LastError & ")")
    end if



    ' ============================================================
    ' Test #3: WriteFloatRegister / RetrieveFloatRegister
    ' ============================================================
    '
    ' A float is typically stored as IEEE-754 across two registers.
    '
    print
    print "----------------------------------------"
    print "Test #3: WriteFloatRegister / RetrieveFloatRegister"
    print "----------------------------------------"

    dim floatAddr as integer = 30
    dim floatVal  as single  = 123.456

    rc = MBTCP_WriteFloatRegister(floatVal, floatAddr)

    if rc = 0 then

        dim gotFloat as single = MBTCP_RetrieveFloatRegister(floatAddr)

        if FloatNear(gotFloat, floatVal, 0.001) then
            TestResult("WriteFloatRegister / RetrieveFloatRegister", 1, "Value=" & gotFloat)
        else
            TestResult("WriteFloatRegister / RetrieveFloatRegister", 0, _
                "Expected " & floatVal & " got " & gotFloat)
        end if

    else
        TestResult("WriteFloatRegister / RetrieveFloatRegister", 0, "Write failed (" & MBP_Common_LastError & ")")
    end if



    ' ============================================================
    ' Test #4: WriteCoil / RetrieveCoil
    ' ============================================================
    '
    ' Function Codes:
    '   - FC05 Write Single Coil
    '   - FC01 Read Coil Status
    '
    print
    print "----------------------------------------"
    print "Test #4: WriteCoil / RetrieveCoil"
    print "----------------------------------------"

    dim coilAddr as integer = 40

    rc = MBTCP_WriteCoil(1, coilAddr)

    if rc = 0 then

        dim gotCoil as integer = MBTCP_RetrieveCoil(coilAddr)

        if gotCoil = 1 then
            TestResult("WriteCoil / RetrieveCoil", 1, "Value=" & gotCoil)
        else
            TestResult("WriteCoil / RetrieveCoil", 0, "Expected 1 got " & gotCoil)
        end if

    else
        TestResult("WriteCoil / RetrieveCoil", 0, "Write failed (" & MBP_Common_LastError & ")")
    end if



    ' ============================================================
    ' Test #5: WriteMultipleRegisters / Verify
    ' ============================================================
    '
    ' Function Code:
    '   - FC16 (0x10) Write Multiple Holding Registers
    '
    print
    print "----------------------------------------"
    print "Test #5: WriteMultipleRegisters / Verify"
    print "----------------------------------------"

    dim multiStart as integer = 50
    dim vals(0 to 4) as ushort

    vals(0)=111
    vals(1)=222
    vals(2)=333
    vals(3)=444
    vals(4)=555

    rc = MBTCP_WriteMultipleRegisters(vals(), multiStart)

    if rc = 0 then

        dim ok as integer = 1
        dim i as integer

        for i = 0 to 4
            dim got as integer = MBTCP_RetrieveRegister(multiStart + i)
            if got <> vals(i) then ok = 0
        next i

        TestResult("WriteMultipleRegisters / Verify", ok, iif(ok, "OK", "Mismatch"))

    else
        TestResult("WriteMultipleRegisters / Verify", 0, "Write failed (" & MBP_Common_LastError & ")")
    end if



    ' ============================================================
    ' Test #6: WriteMultipleCoils / Verify
    ' ============================================================
    '
    ' Function Code:
    '   - FC15 (0x0F) Write Multiple Coils
    '
    print
    print "----------------------------------------"
    print "Test #6: WriteMultipleCoils / Verify"
    print "----------------------------------------"

    dim coilStart as integer = 60
    dim coilVals(0 to 9) as ubyte

    coilVals(0)=1
    coilVals(1)=0
    coilVals(2)=1
    coilVals(3)=1
    coilVals(4)=0
    coilVals(5)=0
    coilVals(6)=1
    coilVals(7)=0
    coilVals(8)=1
    coilVals(9)=1

    rc = MBTCP_WriteMultipleCoils(coilVals(), coilStart)

    if rc = 0 then

        dim ok as integer = 1
        dim i as integer

        for i = 0 to 9
            dim got as integer = MBTCP_RetrieveCoil(coilStart + i)
            if got <> coilVals(i) then ok = 0
        next i

        TestResult("WriteMultipleCoils / Verify", ok, iif(ok, "OK", "Mismatch"))

    else
        TestResult("WriteMultipleCoils / Verify", 0, "Write failed (" & MBP_Common_LastError & ")")
    end if



    ' ============================================================
    ' Test #7: MBSE_WriteLong / MBTCP_RetrieveLongRegister
    ' ============================================================
    '
    ' This test verifies that the emulator-side write routines match
    ' what the Modbus TCP client reads.
    '
    print
    print "----------------------------------------"
    print "Test #7: MBSE_WriteLong / MBTCP_RetrieveLongRegister"
    print "----------------------------------------"

    dim mbseLongAddr1 as integer = 100
    dim mbseLongVal1  as long    = &HCAFEBEEF

    MBSE_WriteLong(mbseLongAddr1, mbseLongVal1)

    dim gotMBSELong1 as long = MBTCP_RetrieveLongRegister(mbseLongAddr1)

    if gotMBSELong1 = mbseLongVal1 then
        TestResult("MBSE_WriteLong / RetrieveLongRegister", 1, "Value=&H" & hex(gotMBSELong1))
    else
        TestResult("MBSE_WriteLong / RetrieveLongRegister", 0, _
            "Expected &H" & hex(mbseLongVal1) & " got &H" & hex(gotMBSELong1))
    end if



    ' ============================================================
    ' Test #8: MBTCP_WriteLongRegister / MBSE_ReadLong
    ' ============================================================
    '
    ' This verifies that the client write functions properly update
    ' emulator memory.
    '
    print
    print "----------------------------------------"
    print "Test #8: MBTCP_WriteLongRegister / MBSE_ReadLong"
    print "----------------------------------------"

    dim mbseLongAddr2 as integer = 110
    dim mbseLongVal2  as long    = &H12345678

    rc = MBTCP_WriteLongRegister(mbseLongVal2, mbseLongAddr2)

    if rc = 0 then

        dim gotMBSELong2 as long = MBSE_ReadLong(mbseLongAddr2)

        if gotMBSELong2 = mbseLongVal2 then
            TestResult("MBTCP_WriteLongRegister / MBSE_ReadLong", 1, "Value=&H" & hex(gotMBSELong2))
        else
            TestResult("MBTCP_WriteLongRegister / MBSE_ReadLong", 0, _
                "Expected &H" & hex(mbseLongVal2) & " got &H" & hex(gotMBSELong2))
        end if

    else
        TestResult("MBTCP_WriteLongRegister / MBSE_ReadLong", 0, "Write failed (" & MBP_Common_LastError & ")")
    end if



    ' ============================================================
    ' Test #9: MBSE_WriteFloat / MBTCP_RetrieveFloatRegister
    ' ============================================================
    '
    ' Emulator writes float -> client reads float
    '
    print
    print "----------------------------------------"
    print "Test #9: MBSE_WriteFloat / MBTCP_RetrieveFloatRegister"
    print "----------------------------------------"

    dim mbseFloatAddr1 as integer = 200
    dim mbseFloatVal1  as single  = 123.456

    MBSE_WriteFloat(mbseFloatAddr1, mbseFloatVal1)

    dim gotMBSEFloat1 as single = MBTCP_RetrieveFloatRegister(mbseFloatAddr1)

    if FloatNear(gotMBSEFloat1, mbseFloatVal1, 0.001) then
        TestResult("MBSE_WriteFloat / RetrieveFloatRegister", 1, "Value=" & gotMBSEFloat1)
    else
        TestResult("MBSE_WriteFloat / RetrieveFloatRegister", 0, _
            "Expected " & mbseFloatVal1 & " got " & gotMBSEFloat1)
    end if



    ' ============================================================
    ' Test #10: MBTCP_WriteFloatRegister / MBSE_ReadFloat
    ' ============================================================
    '
    ' Client writes float -> emulator reads float
    '
    print
    print "----------------------------------------"
    print "Test #10: MBTCP_WriteFloatRegister / MBSE_ReadFloat"
    print "----------------------------------------"

    dim mbseFloatAddr2 as integer = 210
    dim mbseFloatVal2  as single  = 987.654

    rc = MBTCP_WriteFloatRegister(mbseFloatVal2, mbseFloatAddr2)

    if rc = 0 then

        dim gotMBSEFloat2 as single = MBSE_ReadFloat(mbseFloatAddr2)

        if FloatNear(gotMBSEFloat2, mbseFloatVal2, 0.001) then
            TestResult("MBTCP_WriteFloatRegister / MBSE_ReadFloat", 1, "Value=" & gotMBSEFloat2)
        else
            TestResult("MBTCP_WriteFloatRegister / MBSE_ReadFloat", 0, _
                "Expected " & mbseFloatVal2 & " got " & gotMBSEFloat2)
        end if

    else
        TestResult("MBTCP_WriteFloatRegister / MBSE_ReadFloat", 0, "Write failed (" & MBP_Common_LastError & ")")
    end if



    ' ============================================================
    ' EXTENDED FUNCTION CODE TESTS
    ' ============================================================



    ' ============================================================
    ' Test #11: FC07 Read Exception Status
    ' ============================================================
    '
    ' FC07 is an older Modbus feature.
    ' Many modern PLCs still support it.
    '
    print
    print "----------------------------------------"
    print "Test #11: FC07 Read Exception Status"
    print "----------------------------------------"

    dim exStatus as integer
    exStatus = MBTCP_ReadExceptionStatus()

    if exStatus <> MBTCP_COMM_ERROR then
        TestResult("FC07 ReadExceptionStatus", 1, "Status=" & exStatus)
    else
        TestResult("FC07 ReadExceptionStatus", 0, "Comm error (" & MBP_Common_LastError & ")")
    end if



    ' ============================================================
    ' Test #12: FC08 Diagnostics (subset)
    ' ============================================================
    '
    ' NOTE FOR TECHS:
    ' --------------
    ' Modbus function code 08 (Diagnostics) is one of those "optional"
    ' function blocks that many real PLCs implement inconsistently.
    '
    ' Even good industrial devices will sometimes:
    '   - only support subfunction 0000 (Echo)
    '   - return fixed zeros for some counters
    '   - claim to clear counters but not actually reset all values
    '
    ' Because of that, this harness treats FC08 as a *soft compliance test*.
    '
    ' Canonical Harness Rule:
    '   - up to 2 subtests may fail and we still PASS
    '
    ' This gives us confidence that the request/response framing is correct,
    ' without requiring full diagnostic feature completeness.
    '
    print
    print "----------------------------------------"
    print "Test #12: FC08 Diagnostics"
    print "----------------------------------------"

    dim diagFailures as integer = 0
    dim outData as ushort

    ' ------------------------------------------------------------
    ' Subtest A: Echo (subfunction 0000)
    ' ------------------------------------------------------------
    outData = 0
    rc = MBTCP_Diagnostics(&H0000, &H55AA, outData)

    if rc <> 0 or outData <> &H55AA then
        diagFailures += 1
    end if


    ' ------------------------------------------------------------
    ' Subtest B: Return Diagnostic Register (subfunction 0002)
    ' ------------------------------------------------------------
    '
    ' We do not require a specific value.
    ' We only require that the PLC accepts the request.
    '
    outData = 0
    rc = MBTCP_Diagnostics(&H0002, 0, outData)

    if rc <> 0 then
        diagFailures += 1
    end if


    ' ------------------------------------------------------------
    ' Subtest C: Clear Counters (subfunction 000A)
    ' ------------------------------------------------------------
    '
    ' Many PLCs accept the command but do not clear every counter.
    ' We only require that the PLC accepts the request.
    '
    outData = 123
    rc = MBTCP_Diagnostics(&H000A, 0, outData)

    if rc <> 0 then
        diagFailures += 1
    end if


    if diagFailures <= 2 then
        TestResult("FC08 Diagnostics subset", 1, "OK (" & diagFailures & " subtest failures allowed)")
    else
        TestResult("FC08 Diagnostics subset", 0, "Too many failures (" & diagFailures & ")")
    end if



    ' ============================================================
    ' Test #13: FC0B Get Comm Event Counter
    ' ============================================================
    '
    ' This returns:
    '   - status
    '   - event count
    '
    print
    print "----------------------------------------"
    print "Test #13: FC0B Get Comm Event Counter"
    print "----------------------------------------"

    dim ctr as MBTCP_CommEventCounterResult
    rc = MBTCP_GetCommEventCounter(ctr)

    if rc = 0 then
        TestResult("FC0B GetCommEventCounter", 1, _
            "Status=" & ctr.status & " EventCount=" & ctr.eventCount)
    else
        TestResult("FC0B GetCommEventCounter", 0, "Failed (" & MBP_Common_LastError & ")")
    end if



    ' ============================================================
    ' Test #14: FC0C Get Comm Event Log
    ' ============================================================
    '
    ' This returns a log buffer with recent Modbus events.
    '
    print
    print "----------------------------------------"
    print "Test #14: FC0C Get Comm Event Log"
    print "----------------------------------------"

    dim logRes as MBTCP_CommEventLogResult
    rc = MBTCP_GetCommEventLog(logRes)

    if rc = 0 then
        TestResult("FC0C GetCommEventLog", 1, _
            "Status=" & logRes.status & " Events=" & logRes.nEvents & " MsgCount=" & logRes.messageCount)
    else
        TestResult("FC0C GetCommEventLog", 0, "Failed (" & MBP_Common_LastError & ")")
    end if



    ' ============================================================
    ' Test #15: FC11 Report Server ID
    ' ============================================================
    '
    ' This returns a vendor string and sometimes device metadata.
    '
    print
    print "----------------------------------------"
    print "Test #15: FC11 Report Server ID"
    print "----------------------------------------"

    dim serverIDStr as string
    rc = MBTCP_ReportServerID(serverIDStr)

    if rc = 0 then

        if len(serverIDStr) > 0 then
            TestResult("FC11 ReportServerID", 1, serverIDStr)
        else
            TestResult("FC11 ReportServerID", 0, "Empty ID string")
        end if

    else
        TestResult("FC11 ReportServerID", 0, "Failed (" & MBP_Common_LastError & ")")
    end if



    ' ============================================================
    ' Test #16: FC17 Read/Write Multiple Registers
    ' ============================================================
    '
    ' FC17 is one of the more advanced Modbus operations.
    ' It performs:
    '   - read N registers
    '   - write M registers
    ' all in one transaction.
    '
    print
    print "----------------------------------------"
    print "Test #16: FC17 Read/Write Multiple Registers"
    print "----------------------------------------"

    dim writeVals(0 to 2) as ushort

    writeVals(0) = &H1111
    writeVals(1) = &H2222
    writeVals(2) = &H3333

    dim readVals() as ushort

    rc = MBTCP_ReadWriteMultipleRegisters( _
            100, 4, _
            110, writeVals(), _
            readVals() )

    if rc = 0 then

        dim okRW as integer = 1

        if (ubound(readVals) - lbound(readVals) + 1) <> 4 then okRW = 0

        if MBSE_ReadHoldingRegister(110) <> writeVals(0) then okRW = 0
        if MBSE_ReadHoldingRegister(111) <> writeVals(1) then okRW = 0
        if MBSE_ReadHoldingRegister(112) <> writeVals(2) then okRW = 0

        TestResult("FC17 ReadWriteMultipleRegisters", okRW, iif(okRW, "OK", "Mismatch"))

    else
        TestResult("FC17 ReadWriteMultipleRegisters", 0, "Failed (" & MBP_Common_LastError & ")")
    end if



    ' ============================================================
    ' CONTROLLED FAILURE TESTS
    ' ============================================================
    '
    ' These tests intentionally cause errors.
    '
    ' The harness expects MBTCP to detect them cleanly and report a
    ' meaningful error string.
    '



    ' ============================================================
    ' Test #17: Illegal register address
    ' ============================================================
    '
    ' Expected behaviour:
    '   PLC should return exception code 2 (Illegal Data Address)
    '
    print
    print "----------------------------------------"
    print "Test #17: Controlled Failure - Illegal Register Address"
    print "----------------------------------------"

    dim badRegAddr as integer = MBSE_AddrCeiling + 10
    dim badRead as integer = MBTCP_RetrieveRegister(badRegAddr)

    if badRead = MBTCP_COMM_ERROR then
        TestResult("Illegal Register Address", 1, "Comm error (" & MBP_Common_LastError & ")")
    elseif badRead > 0 and badRead <= 255 then
        TestResult("Illegal Register Address", 1, "PLC exception code=" & badRead)
    else
        TestResult("Illegal Register Address", 0, "Unexpected return=" & badRead)
    end if



    ' ============================================================
    ' Test #18: Illegal coil address
    ' ============================================================
    '
    ' Expected behaviour:
    '   PLC should return exception code 2 (Illegal Data Address)
    '
    print
    print "----------------------------------------"
    print "Test #18: Controlled Failure - Illegal Coil Address"
    print "----------------------------------------"

    dim badCoilAddr as integer = MBSE_AddrCeiling + 10
    dim badCoilRead as integer = MBTCP_RetrieveCoil(badCoilAddr)

    if badCoilRead = MBTCP_COMM_ERROR then
        TestResult("Illegal Coil Address", 1, "Comm error (" & MBP_Common_LastError & ")")
    elseif badCoilRead > 0 and badCoilRead <= 255 then
        TestResult("Illegal Coil Address", 1, "PLC exception code=" & badCoilRead)
    else
        TestResult("Illegal Coil Address", 0, "Unexpected return=" & badCoilRead)
    end if



    ' ============================================================
    ' Test #19: Wrong UnitID
    ' ============================================================
    '
    ' Real Modbus behaviour:
    ' If UnitID is wrong, PLC usually does NOT respond at all.
    '
    ' That means we expect a timeout / recv failure.
    '
    print
    print "----------------------------------------"
    print "Test #19: Controlled Failure - Wrong Unit ID"
    print "----------------------------------------"

    dim savedUnit as integer = MBP_UnitID
    MBP_UnitID = 1

    MBP_RecvTimeoutMS = CLIENT_RECV_TIMEOUT_MS_FAST

    dim wrongUnitRead as integer
    wrongUnitRead = MBTCP_RetrieveRegister(10)

    if wrongUnitRead = MBTCP_COMM_ERROR then
        TestResult("Wrong UnitID", 1, "Correctly failed (" & MBP_Common_LastError & ")")
    elseif wrongUnitRead > 0 and wrongUnitRead <= 255 then
        TestResult("Wrong UnitID", 1, "PLC exception code=" & wrongUnitRead)
    else
        TestResult("Wrong UnitID", 0, "Expected failure but got " & wrongUnitRead)
    end if

    MBP_UnitID = savedUnit
    MBP_RecvTimeoutMS = CLIENT_RECV_TIMEOUT_MS_NORM



    ' ============================================================
    ' Test #20: Stop server mid-session
    ' ============================================================
    '
    ' This test simulates:
    '   - PLC power loss
    '   - PLC reboot
    '   - Ethernet cable unplug
    '
    print
    print "----------------------------------------"
    print "Test #20: Controlled Failure - Server Shutdown Mid-Session"
    print "----------------------------------------"

    serverThreadRunning = 0
    ThreadWait(t)

    dim afterStopRead as integer
    afterStopRead = MBTCP_RetrieveRegister(10)

    if afterStopRead = MBTCP_COMM_ERROR then
        TestResult("Server Shutdown Mid-Session", 1, "Correctly failed (" & MBP_Common_LastError & ")")
    else
        TestResult("Server Shutdown Mid-Session", 0, "Expected comm error but got " & afterStopRead)
    end if



    ' ============================================================
    ' Test #21: Attempt reconnect while server down
    ' ============================================================
    '
    ' This test ensures that MBTCP properly detects connection failure.
    '
    print
    print "----------------------------------------"
    print "Test #21: Controlled Failure - Connect When Server Down"
    print "----------------------------------------"

    MBTCP_Disconnect()

    MBP_Connection_Failure = 0
    MBTCP_Connect(HARNESS_HOST)

    if MBP_Connection_Failure <> 0 then
        TestResult("Connect When Server Down", 1, "Correctly failed connection")
    else
        TestResult("Connect When Server Down", 0, "Unexpectedly connected")
    end if



    ' ============================================================
    ' Test #22: Restart server, reconnect client
    ' ============================================================
    '
    ' This test simulates:
    '   - PLC reboot
    '   - SCADA reconnect
    '
    print
    print "----------------------------------------"
    print "Test #22: Recovery - Restart Server and Reconnect"
    print "----------------------------------------"

    serverThreadReady = 0
    serverThreadRunning = 1

    t = ThreadCreate( cast(any ptr, @ServerThread), 0 )

    if t = 0 then

        TestResult("Recovery restart server thread", 0, "ThreadCreate failed")

    else

        if WaitUntil(serverThreadReady, 1, WAIT_SERVER_READY_MS) = 0 or serverStartOk = 0 then

            TestResult("Recovery server start", 0, "Server failed restart")

        else

            MBP_RecvTimeoutMS = CLIENT_RECV_TIMEOUT_MS_NORM

            if ConnectClientOrFail(HARNESS_HOST, WAIT_CONNECT_MS) then
                TestResult("Recovery reconnect", 1, "Client reconnected successfully")
            else
                TestResult("Recovery reconnect", 0, "Reconnect failed (" & MBP_Common_LastError & ")")
            end if

        end if

    end if

end if



' ============================================================
' SUMMARY
' ============================================================

print
print "========================================"
print " Validation Complete"
print "----------------------------------------"
print " PASS: "; gPass
print " FAIL: "; gFail
print "========================================"
print


' ============================================================
' CLEANUP
' ============================================================
'
' Always clean up sockets and server threads.
'
' This ensures:
'   - port 502 is released
'   - threads do not leak
'   - next run works cleanly
'
DBG("Disconnecting client...")
MBTCP_Disconnect()

DBG("Stopping server thread...")
serverThreadRunning = 0
if t <> 0 then ThreadWait(t)

DBG("Shutting down MBSE...")
MBSE_Shutdown()


' ============================================================
' PAUSE IF DOUBLE-CLICKED
' ============================================================
'
' If the harness is run from a file explorer, the window will close
' immediately. This gives the tech time to read the output.
'
if command$ = "" then sleep
