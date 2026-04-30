' ============================================================
' Modbus TCP Server Emulator Example (MBSE)
' ============================================================
'
' This is a complete standalone example program showing how to use
' the MBSE (Modbus Server Emulator) library.
'
' MBSE is designed to behave like a PLC or industrial instrument
' that speaks Modbus/TCP.
'
' In real terms:
'   - MBSE acts like a "slave" / "server"
'   - a SCADA system or Modbus master will connect to it
'   - MBSE responds to Modbus function codes (FC01, FC03, FC06, etc.)
'
' This is extremely useful for:
'   - testing MBTCP client code without real PLC hardware
'   - training techs on Modbus/TCP without risk
'   - simulating a PLC when a PLC is not available
'
'
' ============================================================
' IMPORTANT TECH NOTE ABOUT PORT 502
' ============================================================
'
' Modbus/TCP uses port 502 by default.
'
' On Windows and Linux, port numbers below 1024 are often "privileged".
' That means you may need administrator rights to bind to port 502.
'
' If this program fails to start the server, try:
'   - running as admin
'   - using a different port (ex: 1502)
'   - checking if another Modbus program is already using 502
'
'
' ============================================================
' HOW THIS SERVER WORKS INTERNALLY
' ============================================================
'
' Older versions of MBSE were "single-client":
'   - you started the server
'   - you waited for one client
'   - you manually pumped MBSE_ServerLoopOnce()
'
' The modern MBSE emulator is multi-client and threaded:
'
'   - MBSE_StartServer() starts a listening socket
'   - MBSE creates an internal accept thread
'   - each client that connects gets its own client thread
'   - each client thread loops reading requests and sending responses
'
' So your program does NOT need to run MBSE_ServerLoopOnce() manually.
'
' Your program's job is mainly:
'   1) initialize MBSE
'   2) preload memory values (like a PLC would contain)
'   3) start the server
'   4) keep running until you want to stop
'   5) shut down cleanly
'
'
' ============================================================
' WHAT MEMORY DOES MBSE SIMULATE?
' ============================================================
'
' MBSE simulates the standard Modbus memory model:
'
'   Coils              (0xxxxx)  - single-bit outputs (read/write)
'   Discrete Inputs    (1xxxxx)  - single-bit inputs (read only)
'   Input Registers    (3xxxxx)  - 16-bit analog inputs (read only)
'   Holding Registers  (4xxxxx)  - 16-bit memory registers (read/write)
'
' Internally, MBSE uses arrays indexed from 0:
'
'   Coil(0) is Modbus coil address 0
'   HoldingRegister(0) is Modbus holding register address 0
'
' IMPORTANT:
'   Modbus addresses are always "0-based" on the wire.
'   Some PLC manuals label registers starting at 1, but Modbus itself
'   transmits 0-based addresses.
'
'
' ============================================================
' THREAD SAFETY WARNING (IMPORTANT)
' ============================================================
'
' MBSE is multi-client and threaded.
'
' That means multiple client threads may read/write the Modbus memory
' at the same time.
'
' Because of that, you should NOT directly write to MBSE_Coil(),
' MBSE_HoldingRegister(), etc.
'
' Instead, MBSE provides safe accessor routines like:
'
'   MBSE_WriteCoil()
'   MBSE_WriteHoldingRegister()
'   MBSE_ReadHoldingRegister()
'
' These functions lock a mutex internally so the emulator behaves
' consistently.
'
' This example uses ONLY the safe routines.
'
'
' ============================================================
' INCLUDE THE MBSE LIBRARY
' ============================================================
'
' This file contains the server emulator code and API.
'
#include "modbustcp_server.bi"


' ============================================================
' PROGRAM START
' ============================================================

print "========================================"
print " MBSE Modbus/TCP Server Emulator Example"
print "========================================"
print


' ============================================================
' INITIALIZE THE EMULATOR
' ============================================================
'
' MBSE_Init() must be called before using the emulator.
'
' On Windows, this initializes Winsock.
' On Linux, it initializes mutexes and internal data structures.
'
MBSE_Init()


' ============================================================
' PRELOAD "PLC MEMORY"
' ============================================================
'
' In a real PLC, the memory tables already contain values.
'
' For example:
'   - coils represent outputs like relays, contactors, alarms
'   - holding registers represent analog values, setpoints, parameters
'   - input registers represent sensor readings
'
' Here we preload some sample values so a Modbus client can connect
' and immediately read something meaningful.
'
' ------------------------------------------------------------

' Coils (FC01 / FC05 / FC0F)
'
' Coil 0 = ON
' Coil 1 = OFF
'
MBSE_WriteCoil(0, 1)
MBSE_WriteCoil(1, 0)

' Holding registers (FC03 / FC06 / FC10 / FC17 / FC22)
'
' Holding register 0 = 1234
' Holding register 1 = 5678
'
MBSE_WriteHoldingRegister(0, 1234)
MBSE_WriteHoldingRegister(1, 5678)

' Input registers (FC04)
'
' Input register 0 = 111
'
MBSE_WriteInputRegister(0, 111)


' ============================================================
' START THE MODBUS/TCP SERVER
' ============================================================
'
' MBSE_StartServer(port) opens a listening TCP socket.
'
' When a Modbus client connects:
'   - MBSE accepts the connection
'   - MBSE creates a new client thread
'   - the client thread listens for Modbus requests
'   - MBSE sends responses back automatically
'
' If MBSE_StartServer() returns 0, the server failed to start.
'
' Common reasons:
'   - port 502 already in use
'   - firewall blocked
'   - missing admin privileges (privileged port)
'
dim port as integer = 502

if MBSE_StartServer(port) = 0 then
    print "ERROR: Failed to start Modbus server on port "; port
    print
    print "Possible causes:"
    print "  - Port already in use"
    print "  - No admin rights (port < 1024)"
    print "  - Firewall blocking socket bind"
    print
    print "Try port 1502 if needed."
    MBSE_Shutdown()
    end
end if


' ============================================================
' SERVER IS NOW RUNNING
' ============================================================
'
' At this point, the emulator is active.
'
' A Modbus client can connect using:
'
'   IP Address: the PC running this program
'   Port:       502 (or whatever port you chose)
'
' For example:
'   - MBTCP client library
'   - ModScan
'   - QModMaster
'   - SCADA packages
'
print "Modbus TCP emulator listening on port "; port
print
print "Try reading:"
print "  Coil 0"
print "  Holding Register 0"
print "  Input Register 0"
print
print "Press Q to quit cleanly."
print


' ============================================================
' MAIN LOOP (IDLE LOOP)
' ============================================================
'
' Since MBSE runs in background threads, we do NOT need to manually
' service requests.
'
' We just keep the main program alive until the user quits.
'
' This loop checks the keyboard for the letter Q.
'
' Inkey$ returns a string containing the key pressed, or "" if no key.
'
dim k as string

do
    k = ucase(inkey$)

    if k = "Q" then
        exit do
    end if

    sleep 50
loop


' ============================================================
' STOPPING THE SERVER CLEANLY
' ============================================================
'
' MBSE_StopServer() closes:
'   - the listening socket
'   - all active client sockets
'
' It also stops the internal accept thread.
'
' If you do NOT call MBSE_StopServer(), the port may remain stuck
' until the operating system releases it.
'
print
print "Stopping server..."

MBSE_StopServer()


' ============================================================
' SHUTDOWN / CLEANUP
' ============================================================
'
' MBSE_Shutdown() releases all emulator resources:
'
'   - mutexes
'   - internal buffers
'   - Winsock cleanup (Windows)
'
' This should always be called when your program ends.
'
MBSE_Shutdown()


print "Shutdown complete."
print
print "Program ended normally."
