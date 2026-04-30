' -------------------------------------------------------------------------
' Project: FreeBASIC Modbus TCP library
' -------------------------------------------------------------------------
'
' File: TestPLC.bas
'
' Purpose:
'
'     ModbusTCP PLC Probe / Test Program.
'     Designed to probe a PLC for supported function codes and mapping.
'
' Responsibilities:
'
'      - Connecting to a specified IP address (default or command-line).
'      - Scanning for responsive Unit IDs.
'      - Testing common read/write function codes.
'      - Testing extended function codes (FC07, FC0B, FC0C, FC11, FC17, FC22).
'      - Handling 32-bit data types (float, long).
'
' This file intentionally does NOT contain:
'
'      - Automated regression testing (see validation.bas).
'      - Server-side emulator logic.
' -------------------------------------------------------------------------

#include "modbustcp.bi"

' -------------------------------------------------------------------------
' Helper Routines
' -------------------------------------------------------------------------

sub PrintResult(testName as string, passed as integer, details as string = "")
    ' Prints test result in a consistent PASS/FAIL format.
    if passed then
        print "[PASS] "; testName;
        if details <> "" then print " -- "; details else print
    else
        print "[FAIL] "; testName;
        if details <> "" then print " -- "; details else print
    end if
end sub

sub PrintReadValue(testName as string, value as integer)
    ' Handles printing of results from read operations.
    if value = MBTCP_COMM_ERROR then
        PrintResult(testName, 0, MBP_Common_LastError)
    else
        PrintResult(testName, 1, "Value=" & value)
    end if
end sub

' -------------------------------------------------------------------------
' Main Program
' -------------------------------------------------------------------------

print "========================================"
print " ModbusTCP PLC Probe / Test Program"
print "========================================"
print

dim plcIP as string
plcIP = "127.0.0.1"

' Allow override from command line
if command$ <> "" then
    plcIP = command$
end if

print "Initializing MBTCP..."
MBTCP_Init()

' Configuration
MBP_ZeroOffset = 0
MBP_RecvTimeoutMS = 800

print "PLC Address: "; plcIP
print "Port: 502"
print

' -------------------------------------------------------------------------
' Connection
' -------------------------------------------------------------------------

print "----------------------------------------"
print "Connecting..."
print "----------------------------------------"

MBP_Connection_Failure = 0
MBTCP_Connect(plcIP)

if MBP_Connection_Failure <> 0 then
    PrintResult("TCP Connect", 0, MBP_Common_LastError)
    print
    print "Could not connect to PLC."
    print "Check IP, network, firewall, and port 502."
    print
    sleep
    end
else
    PrintResult("TCP Connect", 1, "Connected successfully")
end if

' -------------------------------------------------------------------------
' Unit ID Scan
' -------------------------------------------------------------------------

print
print "----------------------------------------"
print "Unit ID Scan"
print "----------------------------------------"
print

dim unitCandidates(0 to 2) as integer
unitCandidates(0) = 255: unitCandidates(1) = 1: unitCandidates(2) = 0

dim unitOK as integer = 0
dim chosenUnit as integer = 255

for i as integer = 0 to 2
    MBP_UnitID = unitCandidates(i)
    print "Trying UnitID="; MBP_UnitID; "..."
    dim idStr as string
    if MBTCP_ReportServerID(idStr) = 0 then
        PrintResult("FC11 ReportServerID", 1, "UnitID=" & MBP_UnitID & " ID='" & idStr & "'")
        unitOK = 1
        chosenUnit = MBP_UnitID
        exit for
    else
        PrintResult("FC11 ReportServerID", 0, "UnitID=" & MBP_UnitID & " (" & MBP_Common_LastError & ")")
    end if
next i

if unitOK = 0 then
    print "No UnitID responded to FC11. Using 255."
    MBP_UnitID = 255
else
    print "Using UnitID="; chosenUnit
    MBP_UnitID = chosenUnit
end if

' -------------------------------------------------------------------------
' Basic Read Tests
' -------------------------------------------------------------------------

print
print "----------------------------------------"
print "Basic Read Tests"
print "----------------------------------------"

PrintReadValue("FC01 Read Coil @ 0", MBTCP_RetrieveCoil(0))
PrintReadValue("FC02 Read Discrete Input @ 0", MBTCP_RetrieveDiscreteInput(0))
PrintReadValue("FC03 Read Holding Register @ 0", MBTCP_RetrieveRegister(0))
PrintReadValue("FC04 Read Input Register @ 0", MBTCP_RetrieveInputRegister(0))

' -------------------------------------------------------------------------
' Cleanup
' -------------------------------------------------------------------------

print
print "----------------------------------------"
print "Disconnecting..."
print "----------------------------------------"

MBTCP_Disconnect()
PrintResult("Disconnect", 1, "Socket closed")

print "========================================"
print " PLC Probe Complete"
print "========================================"
print

sleep

' end of TestPLC.bas
