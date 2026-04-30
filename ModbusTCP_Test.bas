' -------------------------------------------------------------------------
' Project: FreeBASIC Modbus TCP library
' -------------------------------------------------------------------------
'
' File: ModbusTCP_Test.bas
'
' Purpose:
'
'     Integration test and demonstration of the MBTCP client library.
'
' Responsibilities:
'
'      - Demonstrating basic read operations for coils, discrete inputs, and registers.
'      - Testing connectivity to a physical or emulated PLC.
'      - Verifying high-level data types (float, long).
'
' This file intentionally does NOT contain:
'
'      - Comprehensive protocol validation (see validation.bas).
'      - Server-side logic.
' -------------------------------------------------------------------------

#include "modbustcp.bi"

' -------------------------------------------------------------------------
' Main Test Program
' -------------------------------------------------------------------------

' Initialise the MBTCP library
print "Initializing MBTCP"
MBTCP_Init ()

'
' NOTE: Ensure the target IP address below is reachable on your network
' or that an emulator is running on the specified host.
'
print "Connecting to 192.168.4.218"
MBTCP_Connect ("192.168.4.218")

dim a as integer

print "Coil Retrieval Test:"
for a = 1 to 5
    print "Coil ";a;" is:";MBTCP_RetrieveCoil(a)
next a

print "Discrete Input Retrieval Test:"
for a = 1 to 5
    print "Discrete Input ";a;" is:";MBTCP_RetrieveDiscreteInput(a)
next a

print "Register Retrieval Test:"
for a = 1 to 5
    print "Register ";a;" is:";MBTCP_RetrieveRegister(a)
next a

print
print "Floating Point Retrieve @310: "; MBTCP_RetrieveFloatRegister(310)
print
print "Long Value Retrieve @310: "; MBTCP_RetrieveLongRegister(310)

' -------------------------------------------------------------------------
' Cleanup
' -------------------------------------------------------------------------

print
print "Test complete. Press any key to exit."
sleep

MBTCP_Disconnect( )
MBTCP_doShutdown( )

' end of ModbusTCP_Test.bas
