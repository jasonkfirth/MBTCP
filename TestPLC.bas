' ============================================================
' ModbusTCP PLC Probe / Test Program
'
' This program tests and demonstrates the MBTCP Modbus TCP library.
'
' It is designed to connect to a PLC that we assume may not have
' anything mapped or configured for Modbus yet.
'
' It attempts common Modbus function codes and reports:
'
'   - what worked
'   - what failed
'   - whether the PLC returned a Modbus exception
'   - whether the PLC ignored the request (timeout)
'
' This is useful for:
'   - field testing
'   - commissioning
'   - verifying network / firewall / Unit ID behaviour
'
' ============================================================

' #define MBTCP_Debug

#include "modbustcp.bi"


' ============================================================
' Helper: Print PASS/FAIL in a consistent way
' ============================================================

sub PrintResult(testName as string, passed as integer, details as string = "")
    if passed then
        print "[PASS] "; testName;
        if details <> "" then print " -- "; details else print
    else
        print "[FAIL] "; testName;
        if details <> "" then print " -- "; details else print
    end if
end sub


' ============================================================
' Helper: Print Modbus return values in a readable way
' ============================================================
'
' Some functions return:
'   - normal value (0 or 1 or register value)
'   - MBTCP_COMM_ERROR (-32768)
'
' MBP_Common_LastError tells us why.
'
sub PrintReadValue(testName as string, value as integer)
    if value = MBTCP_COMM_ERROR then
        PrintResult(testName, 0, MBP_Common_LastError)
    else
        PrintResult(testName, 1, "Value=" & value)
    end if
end sub


' ============================================================
' Helper: attempt a "safe read" that doesn't assume the register exists
' ============================================================

function TryReadRegister(addr as integer) as integer
    dim v as integer
    v = MBTCP_RetrieveRegister(addr)
    return v
end function


function TryReadInputRegister(addr as integer) as integer
    dim v as integer
    v = MBTCP_RetrieveInputRegister(addr)
    return v
end function


function TryReadCoil(addr as integer) as integer
    dim v as integer
    v = MBTCP_RetrieveCoil(addr)
    return v
end function


function TryReadDiscreteInput(addr as integer) as integer
    dim v as integer
    v = MBTCP_RetrieveDiscreteInput(addr)
    return v
end function



' ============================================================
' MAIN PROGRAM
' ============================================================

print "========================================"
print " ModbusTCP PLC Probe / Test Program"
print "========================================"
print

dim plcIP as string
plcIP = "23-PLC-0002

' Allow override from command line
if command$ <> "" then
    plcIP = command$
end if

print "Initializing MBTCP..."
MBTCP_Init()

' Recommended defaults:
MBP_ZeroOffset = 0

' If PLC ignores requests, this prevents hanging forever.
MBP_RecvTimeoutMS = 800

print "PLC Address: "; plcIP
print "Port: 502"
print


' ============================================================
' CONNECT TEST
' ============================================================

print "----------------------------------------"
print "Connecting..."
print "----------------------------------------"

MBTCP_Connect(plcIP)

if MBP_Connection_Failure <> 0 then
    PrintResult("TCP Connect", 0, MBP_Common_LastError)
    print
    print "Could not connect to PLC."
    print "Check IP address, network, firewall, and whether port 502 is open."
    print
    sleep
    end
else
    PrintResult("TCP Connect", 1, "Connected successfully")
end if


print
print "----------------------------------------"
print "Unit ID Scan"
print "----------------------------------------"
print
print "Many PLCs ignore UnitID, but some require a specific one."
print "We will try: 255, 1, 0"
print

dim unitCandidates(0 to 2) as integer
unitCandidates(0) = 255
unitCandidates(1) = 1
unitCandidates(2) = 0

dim unitOK as integer = 0
dim chosenUnit as integer = 255

dim i as integer
for i = 0 to 2

    MBP_UnitID = unitCandidates(i)

    print "Trying UnitID="; MBP_UnitID; "..."

    ' FC11 is a great probe because it doesn't depend on mapped memory.
    dim idStr as string
    dim rc as integer

    rc = MBTCP_ReportServerID(idStr)

    if rc = 0 then
        PrintResult("FC11 ReportServerID", 1, "UnitID=" & MBP_UnitID & " ID='" & idStr & "'")
        unitOK = 1
        chosenUnit = MBP_UnitID
        exit for
    else
        PrintResult("FC11 ReportServerID", 0, "UnitID=" & MBP_UnitID & " (" & MBP_Common_LastError & ")")
    end if

next i


if unitOK = 0 then
    print
    print "No UnitID responded to FC11."
    print "This does NOT mean Modbus is dead."
    print "Some PLCs do not support FC11."
    print
    print "We will continue tests using UnitID=255."
    MBP_UnitID = 255
else
    print
    print "Using UnitID="; chosenUnit; " for the remaining tests."
    MBP_UnitID = chosenUnit
end if



' ============================================================
' BASIC READ TESTS (FC01/02/03/04)
' ============================================================

print
print "----------------------------------------"
print "Basic Read Tests"
print "----------------------------------------"
print
print "If these fail with exception 2, the PLC likely has no Modbus mapping configured."
print


' Test addresses (these are guesses)
dim coilAddr as integer = 0
dim diAddr   as integer = 0
dim regAddr  as integer = 0
dim inAddr   as integer = 0

dim v as integer


v = TryReadCoil(coilAddr)
PrintReadValue("FC01 Read Coil @ " & coilAddr, v)

v = TryReadDiscreteInput(diAddr)
PrintReadValue("FC02 Read Discrete Input @ " & diAddr, v)

v = TryReadRegister(regAddr)
PrintReadValue("FC03 Read Holding Register @ " & regAddr, v)

v = TryReadInputRegister(inAddr)
PrintReadValue("FC04 Read Input Register @ " & inAddr, v)



' ============================================================
' EXTENDED READ TESTS (FC07, FC0B, FC0C)
' ============================================================

print
print "----------------------------------------"
print "Extended Read Tests"
print "----------------------------------------"
print
print "These are optional features. Many PLCs do not support them."
print


dim exStatus as integer
exStatus = MBTCP_ReadExceptionStatus()

if exStatus = MBTCP_COMM_ERROR then
    PrintResult("FC07 Read Exception Status", 0, MBP_Common_LastError)
else
    PrintResult("FC07 Read Exception Status", 1, "Status=" & exStatus)
end if


dim ctr as MBTCP_CommEventCounterResult
dim rc as integer

rc = MBTCP_GetCommEventCounter(ctr)

if rc = 0 then
    PrintResult("FC0B Get Comm Event Counter", 1, "Status=" & ctr.status & " EventCount=" & ctr.eventCount)
else
    PrintResult("FC0B Get Comm Event Counter", 0, MBP_Common_LastError)
end if


dim logRes as MBTCP_CommEventLogResult
rc = MBTCP_GetCommEventLog(logRes)

if rc = 0 then
    PrintResult("FC0C Get Comm Event Log", 1, _
        "Status=" & logRes.status & " Events=" & logRes.nEvents & " MsgCount=" & logRes.messageCount)
else
    PrintResult("FC0C Get Comm Event Log", 0, MBP_Common_LastError)
end if



' ============================================================
' WRITE TESTS (DANGEROUS!)
' ============================================================
'
' Writes can alter real PLC memory.
'
' We will attempt writes to address 0.
' If the PLC is unmapped, it should reject them.
'
' If the PLC is mapped, you may actually be changing something.
'
' ============================================================

print
print "----------------------------------------"
print "Write Tests (WARNING)"
print "----------------------------------------"
print
print "This will attempt to write to address 0."
print "If the PLC is mapped, this may change a real value."
print "If you are not sure, do not run this on production hardware."
print

print "Proceeding with safe test writes..."
print


' FC06 Write Single Register
rc = MBTCP_WriteRegister(1234, 0)

if rc = 0 then
    PrintResult("FC06 Write Single Register @ 0", 1, "Wrote 1234")
else
    PrintResult("FC06 Write Single Register @ 0", 0, MBP_Common_LastError)
end if


' FC05 Write Single Coil
rc = MBTCP_WriteCoil(1, 0)

if rc = 0 then
    PrintResult("FC05 Write Single Coil @ 0", 1, "Wrote ON")
else
    PrintResult("FC05 Write Single Coil @ 0", 0, MBP_Common_LastError)
end if


' FC16 Write Multiple Registers
dim vals(0 to 2) as ushort
vals(0) = 111
vals(1) = 222
vals(2) = 333

rc = MBTCP_WriteMultipleRegisters(vals(), 0)

if rc = 0 then
    PrintResult("FC16 Write Multiple Registers @ 0", 1, "Wrote 3 registers")
else
    PrintResult("FC16 Write Multiple Registers @ 0", 0, MBP_Common_LastError)
end if


' FC15 Write Multiple Coils
dim coils(0 to 7) as ubyte
coils(0)=1
coils(1)=0
coils(2)=1
coils(3)=1
coils(4)=0
coils(5)=0
coils(6)=1
coils(7)=0

rc = MBTCP_WriteMultipleCoils(coils(), 0)

if rc = 0 then
    PrintResult("FC15 Write Multiple Coils @ 0", 1, "Wrote 8 coils")
else
    PrintResult("FC15 Write Multiple Coils @ 0", 0, MBP_Common_LastError)
end if



' ============================================================
' FC22 Mask Write Register
' ============================================================

print
print "----------------------------------------"
print "FC22 Mask Write Register Test"
print "----------------------------------------"
print
print "This attempts to modify bits in holding register 0."
print

rc = MBTCP_MaskWriteRegister(0, &HFFF0, &H0005)

if rc = 0 then
    PrintResult("FC22 Mask Write Register @ 0", 1, "AND=&HFFF0 OR=&H0005")
else
    PrintResult("FC22 Mask Write Register @ 0", 0, MBP_Common_LastError)
end if



' ============================================================
' FC17 Read/Write Multiple Registers
' ============================================================

print
print "----------------------------------------"
print "FC17 Read/Write Multiple Registers Test"
print "----------------------------------------"
print
print "This attempts to read 2 registers and write 2 registers."
print

dim writeVals(0 to 1) as ushort
writeVals(0) = &H1111
writeVals(1) = &H2222

dim readVals() as ushort

rc = MBTCP_ReadWriteMultipleRegisters( _
        0, 2, _
        10, writeVals(), _
        readVals() )

if rc = 0 then

    dim s as string = ""
    dim j as integer

    for j = lbound(readVals) to ubound(readVals)
        s &= "&H" & hex(readVals(j), 4) & " "
    next j

    PrintResult("FC17 Read/Write Multiple Registers", 1, "ReadBack=" & s)

else
    PrintResult("FC17 Read/Write Multiple Registers", 0, MBP_Common_LastError)
end if



' ============================================================
' FLOAT + LONG TESTS
' ============================================================

print
print "----------------------------------------"
print "32-bit Data Tests (Long / Float)"
print "----------------------------------------"
print
print "These tests assume holding registers 0 and 1 are readable."
print


dim longVal as long
longVal = MBTCP_RetrieveLongRegister(0)

if longVal = MBTCP_COMM_ERROR then
    PrintResult("Read Long @ 0", 0, MBP_Common_LastError)
else
    PrintResult("Read Long @ 0", 1, "Value=&H" & hex(longVal))
end if


dim floatVal as single
floatVal = MBTCP_RetrieveFloatRegister(0)

if floatVal = MBTCP_COMM_ERROR then
    PrintResult("Read Float @ 0", 0, MBP_Common_LastError)
else
    PrintResult("Read Float @ 0", 1, "Value=" & floatVal)
end if



' ============================================================
' DISCONNECT
' ============================================================

print
print "----------------------------------------"
print "Disconnecting..."
print "----------------------------------------"

MBTCP_Disconnect()
PrintResult("Disconnect", 1, "Socket closed")

print
print "========================================"
print " PLC Probe Complete"
print "========================================"
print

sleep
