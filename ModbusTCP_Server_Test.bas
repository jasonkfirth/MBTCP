' -------------------------------------------------------------------------
' Project: FreeBASIC Modbus TCP library
' -------------------------------------------------------------------------
'
' File: ModbusTCP_Server_Test.bas
'
' Purpose:
'
'     Modbus TCP Server Emulator Example (MBSE).
'     Demonstrates how to use the MBSE library to emulate a PLC.
'
' Responsibilities:
'
'      - Initializing the server emulator.
'      - Preloading simulated PLC memory (coils, registers).
'      - Starting the server on a specified port (default 502).
'      - Handling the server lifecycle (start, run, stop, shutdown).
'
' This file intentionally does NOT contain:
'
'      - Client-side library logic.
'      - Complex automation logic (only provides static preloaded data).
' -------------------------------------------------------------------------

#include "modbustcp_server.bi"

' -------------------------------------------------------------------------
' Program Entry Point
' -------------------------------------------------------------------------

print "========================================"
print " MBSE Modbus/TCP Server Emulator Example"
print "========================================"
print

'
' Initialize the emulator.
' This must be called before any other MBSE functions.
'
MBSE_Init()

' -------------------------------------------------------------------------
' Preload Simulated Memory
' -------------------------------------------------------------------------

'
' We use the thread-safe MBSE_Write* functions to populate the memory
' regions before the server starts accepting connections.
'

' Coils (0XXXXX)
MBSE_WriteCoil(0, 1)
MBSE_WriteCoil(1, 0)

' Holding registers (4XXXXX)
MBSE_WriteHoldingRegister(0, 1234)
MBSE_WriteHoldingRegister(1, 5678)

' Input registers (3XXXXX)
MBSE_WriteInputRegister(0, 111)

' -------------------------------------------------------------------------
' Start the Server
' -------------------------------------------------------------------------

'
' Default Modbus TCP port is 502.
' Note: Admin privileges may be required to bind to ports < 1024.
'
dim port as integer = 502

if MBSE_StartServer(port) = 0 then
    print "ERROR: Failed to start Modbus server on port "; port
    print
    print "Possible causes:"
    print "  - Port already in use (check for other Modbus instances)"
    print "  - No admin/root rights (required for port 502 on some systems)"
    print "  - Firewall blocking socket bind"
    print
    print "Try using a different port (e.g., 1502) if issues persist."
    MBSE_Shutdown()
    end
end if

print "Modbus TCP emulator listening on port "; port
print
print "Try connecting with a Modbus client to read:"
print "  - Coil 0"
print "  - Holding Register 0"
print "  - Input Register 0"
print
print "Press 'Q' to quit cleanly."
print

' -------------------------------------------------------------------------
' Main Loop
' -------------------------------------------------------------------------

dim k as string

do
    k = ucase(inkey$)
    if k = "Q" then exit do
    sleep 50
loop

' -------------------------------------------------------------------------
' Cleanup and Shutdown
' -------------------------------------------------------------------------

print
print "Stopping server..."

MBSE_StopServer()
MBSE_Shutdown()

print "Shutdown complete."
print
print "Program ended normally."

' end of ModbusTCP_Server_Test.bas
