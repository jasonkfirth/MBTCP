' -------------------------------------------------------------------------
' Project: FreeBASIC Modbus TCP library
' -------------------------------------------------------------------------
'
' File: pulldata.bas
'
' Purpose:
'
'     Modbus TCP data extraction utility.
'     Pulls a range of holding registers from a PLC and displays them.
'
' Responsibilities:
'
'      - Iterating through a range of holding register addresses.
'      - Retrieving and displaying both integer and floating-point interpretations.
'      - Handling reconnections (if required by PLC behavior).
'
' This file intentionally does NOT contain:
'
'      - Automated validation logic.
'      - Server-side emulator logic.
' -------------------------------------------------------------------------

#include "modbustcp.bi"

' -------------------------------------------------------------------------
' Main Extraction Loop
' -------------------------------------------------------------------------

print "Initializing MBTCP"
MBTCP_Init ()

' PLC Configuration
const PLC_IP = "192.168.4.126"
MBP_ZeroOffset = 1
MBP_UnitID = 1

print "Pulling Register States from "; PLC_IP
print "Range: 4000 to 32000"

for a as integer = 4000 to 32000
    MBTCP_Connect (PLC_IP)
    if MBP_Connection_Failure = 0 then
        dim regVal as integer = MBTCP_RetrieveRegister(a)
        dim floatVal as single = MBTCP_RetrieveFloatRegister(a)
        print  "Addr: "; a; " | Hex: &H"; hex(regVal, 4); " | Float: "; floatVal
        MBTCP_Disconnect()
    else
        print "Connect failed for addr: "; a
    end if

    '
    ' Delay to prevent overwhelming the PLC or network.
    ' Industrial PLCs may have limited connection pools.
    '
    sleep 250
next a

' -------------------------------------------------------------------------
' Cleanup
' -------------------------------------------------------------------------

print "Complete. Press enter to exit."
sleep

MBTCP_doShutdown()

' end of pulldata.bas
