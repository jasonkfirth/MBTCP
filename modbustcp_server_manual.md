# MBTCP Server FreeBASIC Library Manual

## 1.0 Summary
This document explains how to use the MBTCP Server FreeBASIC library.

## 1.1 Intended Audience
This document is intended as a guide for individuals working outside of their normal expertise.

---

## 2.0 Updating Instructions
Updates to this project must be made to the GitHub repository.

---

## 3.0 Introduction

The MBTCP Server Emulator (MBSE) library is a lightweight Modbus TCP server implementation written in FreeBASIC.

It is intended to emulate a minimal PLC (Programmable Logic Controller) so that Modbus TCP clients can connect and read/write registers and coils.

The library supports:
- Multi-client operation (thread-per-connection model)
- A large pre-allocated memory model:
  - 99999 addresses per Modbus memory region

This library is designed for:
- Testing
- Simulation
- Validation
- Learning

### Supported Function Codes

- FC01 Read Coils
- FC02 Read Discrete Inputs
- FC03 Read Holding Registers
- FC04 Read Input Registers
- FC05 Write Single Coil
- FC06 Write Single Register
- FC07 Read Exception Status
- FC08 Diagnostics (subset)
- FC0B Get Comm Event Counter
- FC0C Get Comm Event Log
- FC11 Report Server ID
- FC15 Write Multiple Coils
- FC16 Write Multiple Registers
- FC17 Read/Write Multiple Registers
- FC22 Mask Write Register

### Stubbed Function Codes

- FC14 Read File Record (returns Illegal Function)

---

## 4.0 Getting Started

### 4.1 Setting up FreeBASIC & FBIDE

1. Download FreeBASIC: http://www.freebasic.net  
2. Download fbIDE: http://fbide.sourceforge.net  
3. Install fbIDE  
4. Install FreeBASIC into the fbIDE directory  

---

### 4.2 Loading the Library

Copy `modbustcp_server.bi` into your project directory and include:

    #include "modbustcp_server.bi"

    ### 4.3 Debugging Support

The server emulator supports debug output.

To enable debug messages, place the following at the top of your program before including the library:

    #define MBSE_Debug

This enables verbose output showing:
- Incoming Modbus requests
- Outgoing responses
- Connection events
- Internal processing steps

This is useful when:
- Diagnosing connection issues
- Verifying client behavior
- Learning Modbus packet flow

---

### 4.4 Initialisation and Shutdown

To use the MBTCP Server Emulator, the library must be initialized before use and properly shut down when finished.

    MBSE_Init()
    MBSE_Shutdown()

- MBSE_Init() prepares the library (Winsock, mutexes, internal structures)
- MBSE_Shutdown() cleans up all resources

---

### 4.5 Starting and Stopping the Server

To begin accepting Modbus TCP connections:

    MBSE_StartServer(port)

- port is typically 502

To stop the server and disconnect all clients:

    MBSE_StopServer()

---

#### Example (Basic Server Lifecycle)

    #define MBSE_Debug
    #include "modbustcp_server.bi"

    MBSE_Init()

    if MBSE_StartServer(502) = 0 then
        print "Failed to start Modbus server"
        MBSE_Shutdown()
        end
    end if

    print "Server running on port 502."
    print "Press any key to stop."
    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

    print "Server stopped."
    sleep

---

### 4.6 Threading Model

The MBTCP Server Emulator supports multiple clients simultaneously.

The internal design:

- MBSE_StartServer() creates a listening socket
- An accept thread waits for incoming connections
- Each client connection is handled by its own thread
- Each client thread:
  - Receives Modbus requests
  - Processes them
  - Sends responses

All clients share the same Modbus memory.

Thread safety is handled internally using mutex locks, ensuring:

- No memory corruption
- Safe concurrent access
- Predictable behavior under load

---

### 4.7 Modbus Memory Model

The emulator pre-allocates memory for all Modbus data regions:

- Coils (0XXXXX)
- Discrete Inputs (1XXXXX)
- Input Registers (3XXXXX)
- Holding Registers (4XXXXX)

Internal arrays:

    MBSE_Coil(0 to 99999)             as ubyte
    MBSE_DiscreteInput(0 to 99999)    as ubyte
    MBSE_InputRegister(0 to 99999)    as ushort
    MBSE_HoldingRegister(0 to 99999)  as ushort

Key rules:

- Addressing starts at 0
- Address 0 maps directly to index 0
- Address 10 maps to index 10

Do not access these arrays directly.

Always use the provided API functions to ensure thread safety.

---

### 4.8 Runtime Interaction Model

The server operates independently once started.

However, the purpose of the library is to allow your program to modify the Modbus memory **while the server is running**.

This enables:

- Simulation of PLC behavior
- Dynamic data updates
- Testing client responses to changing values

Typical workflow:

1. Start server
2. Modify registers/coils using MBSE_* functions
3. Modbus clients read/write data over TCP
4. Your program reacts or updates values continuously

---

#### Example (Runtime Interaction)

    #include "modbustcp_server.bi"

    MBSE_Init()

    if MBSE_StartServer(502) = 0 then
        print "Failed to start server"
        MBSE_Shutdown()
        end
    end if

    dim i as integer = 0

    print "Server running. Updating register 0..."

    do
        MBSE_WriteHoldingRegister(0, i)
        print "Register 0 = "; i
        i += 1
        sleep 1000
    loop until inkey <> ""

    MBSE_StopServer()
    MBSE_Shutdown()

---

#### Example (Integration Concept)

In real usage, a Modbus client (SCADA/HMI) connects and reads values:

- Your program writes:

    MBSE_WriteHoldingRegister(0, 1234)

- Client reads via FC03:

    → receives 1234

This mirrors real PLC behavior.

For full validation, see the integration harness which demonstrates:
- Server write → client read
- Client write → server memory update
- End-to-end Modbus correctness :contentReference[oaicite:0]{index=0}

## 5.0 Commands

---

### 5.1 MBSE_Init

#### Introduction
Initializes the Modbus TCP server emulator library.

On Windows, this initializes Winsock. It also creates internal mutex objects used for thread-safe access to memory tables.

This must be called before starting the server.

---

#### Parameters

    sub MBSE_Init()

None.

---

#### Usage
Call once at program start before any other MBSE functions.

---

#### Example

    #define MBSE_Debug
    #include "modbustcp_server.bi"

    MBSE_Init()

    if MBSE_StartServer(502) = 0 then
        print "Failed to start Modbus server"
        MBSE_Shutdown()
        end
    end if

    print "Server initialized and running."
    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

---

### 5.2 MBSE_Shutdown

#### Introduction
Shuts down the Modbus server emulator library.

Stops the server (if running), destroys mutex objects, and performs cleanup.

---

#### Parameters

    sub MBSE_Shutdown()

None.

---

#### Usage
Call once at program exit.

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()

    if MBSE_StartServer(502) = 0 then
        print "Failed to start server"
        MBSE_Shutdown()
        end
    end if

    print "Server running."
    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

    print "Shutdown complete."

---

### 5.3 MBSE_StartServer

#### Introduction
Starts the Modbus TCP server.

- Binds to a TCP port
- Begins listening for connections
- Starts accept thread
- Creates client threads per connection

---

#### Parameters

    function MBSE_StartServer(byval port as integer) as integer

- port: TCP port (typically 502)

---

#### Return Values

- 1 = success  
- 0 = failure  

---

#### Usage
Call after MBSE_Init().

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()

    if MBSE_StartServer(502) = 0 then
        print "Failed to bind port 502"
        MBSE_Shutdown()
        end
    end if

    print "Server started on port 502."
    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

---

### 5.4 MBSE_StopServer

#### Introduction
Stops the Modbus TCP server.

- Closes listening socket
- Stops accept thread
- Disconnects all clients

---

#### Parameters

    sub MBSE_StopServer()

None.

---

#### Usage
Call before MBSE_Shutdown().

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()

    if MBSE_StartServer(502) = 0 then
        print "Failed to start server"
        MBSE_Shutdown()
        end
    end if

    print "Server running."
    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

    print "Server stopped."

---

### 5.5 MBSE_WriteHoldingRegister

#### Introduction
Writes a 16-bit value into a holding register (4XXXXX).

---

#### Parameters

    sub MBSE_WriteHoldingRegister(byval addr as integer, byval value as ushort)

---

#### Usage
Updates emulator memory. Connected clients will read this value via FC03.

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()
    MBSE_StartServer(502)

    MBSE_WriteHoldingRegister(10, 12345)

    print "Register 10 = "; MBSE_ReadHoldingRegister(10)

    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

---

### 5.6 MBSE_ReadHoldingRegister

#### Introduction
Reads a 16-bit value from a holding register (4XXXXX).

---

#### Parameters

    function MBSE_ReadHoldingRegister(byval addr as integer) as ushort

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()
    MBSE_StartServer(502)

    MBSE_WriteHoldingRegister(10, 54321)

    print "Register 10 = "; MBSE_ReadHoldingRegister(10)

    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

---

### 5.7 MBSE_WriteInputRegister

#### Introduction
Writes a value into an input register (3XXXXX).

Note: Real PLCs treat input registers as read-only, but this emulator allows writes for simulation.

---

#### Parameters

    sub MBSE_WriteInputRegister(byval addr as integer, byval value as ushort)

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()
    MBSE_StartServer(502)

    MBSE_WriteInputRegister(5, 777)

    print "Input register 5 set to 777"

    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

---

### 5.8 MBSE_ReadInputRegister

#### Introduction
Reads a value from an input register (3XXXXX).

---

#### Parameters

    function MBSE_ReadInputRegister(byval addr as integer) as ushort

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()
    MBSE_StartServer(502)

    MBSE_WriteInputRegister(5, 777)

    print "Input register 5 = "; MBSE_ReadInputRegister(5)

    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

---

### 5.9 MBSE_WriteCoil

#### Introduction
Writes a value to a coil (0XXXXX).

---

#### Parameters

    sub MBSE_WriteCoil(byval addr as integer, byval value as ubyte)

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()
    MBSE_StartServer(502)

    MBSE_WriteCoil(0, 1)

    print "Coil 0 = "; MBSE_ReadCoil(0)

    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

---

### 5.10 MBSE_ReadCoil

#### Introduction
Reads a value from a coil (0XXXXX).

---

#### Parameters

    function MBSE_ReadCoil(byval addr as integer) as ubyte

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()
    MBSE_StartServer(502)

    MBSE_WriteCoil(100, 1)

    print "Coil 100 = "; MBSE_ReadCoil(100)

    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

    ### 5.11 MBSE_WriteDiscreteInput

#### Introduction
Writes a value to a discrete input (1XXXXX).

Discrete inputs represent single-bit input values.

---

#### Parameters

    sub MBSE_WriteDiscreteInput(byval addr as integer, byval value as ubyte)

- addr: 0 to 99999  
- value: 0 or 1  

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()
    MBSE_StartServer(502)

    MBSE_WriteDiscreteInput(0, 1)

    print "Discrete input 0 = "; MBSE_ReadDiscreteInput(0)

    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

---

### 5.12 MBSE_ReadDiscreteInput

#### Introduction
Reads a value from a discrete input (1XXXXX).

---

#### Parameters

    function MBSE_ReadDiscreteInput(byval addr as integer) as ubyte

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()
    MBSE_StartServer(502)

    MBSE_WriteDiscreteInput(0, 1)

    print "Discrete input 0 = "; MBSE_ReadDiscreteInput(0)

    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

---

### 5.13 MBSE_WriteLong

#### Introduction
Writes a 32-bit integer into two holding registers.

- addr     = low word  
- addr + 1 = high word  

---

#### Parameters

    sub MBSE_WriteLong(byval addr as integer, byval value as long)

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()
    MBSE_StartServer(502)

    MBSE_WriteLong(100, &H12345678)

    print "Low word  = &H"; hex(MBSE_ReadHoldingRegister(100))
    print "High word = &H"; hex(MBSE_ReadHoldingRegister(101))

    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

---

### 5.14 MBSE_ReadLong

#### Introduction
Reads a 32-bit integer from two holding registers.

---

#### Parameters

    function MBSE_ReadLong(byval addr as integer) as long

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()
    MBSE_StartServer(502)

    MBSE_WriteLong(200, &HCAFEBEEF)

    print "ReadLong(200) = &H"; hex(MBSE_ReadLong(200))

    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

---

### 5.15 MBSE_WriteFloat

#### Introduction
Writes a 32-bit floating point value into two holding registers.

- addr     = low word  
- addr + 1 = high word  

---

#### Parameters

    sub MBSE_WriteFloat(byval addr as integer, byval value as single)

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()
    MBSE_StartServer(502)

    MBSE_WriteFloat(300, 123.456)

    print "ReadFloat(300) = "; MBSE_ReadFloat(300)

    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

---

### 5.16 MBSE_ReadFloat

#### Introduction
Reads a 32-bit floating point value from two holding registers.

---

#### Parameters

    function MBSE_ReadFloat(byval addr as integer) as single

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()
    MBSE_StartServer(502)

    MBSE_WriteFloat(400, 987.654)

    print "ReadFloat(400) = "; MBSE_ReadFloat(400)

    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

---

### 5.17 MBSE_WriteInputLong

#### Introduction
Writes a 32-bit integer into two input registers.

---

#### Parameters

    sub MBSE_WriteInputLong(byval addr as integer, byval value as long)

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()
    MBSE_StartServer(502)

    MBSE_WriteInputLong(10, &H12345678)

    print "ReadInputLong(10) = &H"; hex(MBSE_ReadInputLong(10))

    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

---

### 5.18 MBSE_ReadInputLong

#### Introduction
Reads a 32-bit integer from two input registers.

---

#### Parameters

    function MBSE_ReadInputLong(byval addr as integer) as long

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()
    MBSE_StartServer(502)

    MBSE_WriteInputLong(20, &HCAFEBEEF)

    print "ReadInputLong(20) = &H"; hex(MBSE_ReadInputLong(20))

    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

---

### 5.19 MBSE_WriteInputFloat

#### Introduction
Writes a 32-bit floating point value into two input registers.

---

#### Parameters

    sub MBSE_WriteInputFloat(byval addr as integer, byval value as single)

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()
    MBSE_StartServer(502)

    MBSE_WriteInputFloat(50, 123.456)

    print "ReadInputFloat(50) = "; MBSE_ReadInputFloat(50)

    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

---

### 5.20 MBSE_ReadInputFloat

#### Introduction
Reads a 32-bit floating point value from two input registers.

---

#### Parameters

    function MBSE_ReadInputFloat(byval addr as integer) as single

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()
    MBSE_StartServer(502)

    MBSE_WriteInputFloat(100, 987.654)

    print "ReadInputFloat(100) = "; MBSE_ReadInputFloat(100)

    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

    ### 5.21 MBSE_StrictUnitID (Global Variable)

#### Introduction
Controls whether the server enforces a specific Modbus Unit ID.

In real systems, some PLCs ignore Unit ID, while others require a match.

---

#### Definition

    dim shared MBSE_StrictUnitID as integer

---

#### Values

- 0 = ignore Unit ID (default)  
- 1 = enforce Unit ID  

---

#### Usage
When enabled, the server will ignore requests with the wrong Unit ID.

From the client perspective, this appears as:
- No response
- Timeout

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()

    MBSE_StrictUnitID = 1
    MBSE_ExpectedUnitID = 255

    MBSE_StartServer(502)

    print "Strict UnitID enabled (255)."
    print "Clients using other UnitIDs will not receive responses."

    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

---

### 5.22 MBSE_ExpectedUnitID (Global Variable)

#### Introduction
Defines the Unit ID value required when strict mode is enabled.

---

#### Definition

    dim shared MBSE_ExpectedUnitID as ubyte

---

#### Range

- 0 to 255  

---

#### Usage
Used only when MBSE_StrictUnitID = 1.

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()

    MBSE_StrictUnitID = 1
    MBSE_ExpectedUnitID = 10

    MBSE_StartServer(502)

    print "Only UnitID 10 will be accepted."

    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

---

### 5.23 MBSE_AddrCeiling (Global Variable)

#### Introduction
Limits the maximum address that can be accessed.

Requests above this value return Modbus exception code 2 (Illegal Data Address).

---

#### Definition

    dim shared MBSE_AddrCeiling as integer

---

#### Usage
Used to simulate PLCs with limited memory or to test client error handling.

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()

    MBSE_AddrCeiling = 50

    MBSE_StartServer(502)

    MBSE_WriteHoldingRegister(50, 1234)

    print "Address ceiling set to 50."
    print "Address 51 should trigger exception."

    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

---

### 5.24 MBSE_ClientRecvTimeoutMS (Global Variable)

#### Introduction
Controls how long the server waits to receive data from a client.

---

#### Definition

    dim shared MBSE_ClientRecvTimeoutMS as integer

---

#### Units

Milliseconds

---

#### Usage
- Shorter values improve responsiveness
- Longer values allow slower clients

Applied per client connection.

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()

    MBSE_ClientRecvTimeoutMS = 500

    MBSE_StartServer(502)

    print "Client receive timeout = 500 ms"

    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

---

### 5.25 MBSE_ClientSendTimeoutMS (Global Variable)

#### Introduction
Controls how long the server attempts to send data before failing.

---

#### Definition

    dim shared MBSE_ClientSendTimeoutMS as integer

---

#### Units

Milliseconds

---

#### Usage
Prevents blocking when a client is unresponsive.

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()

    MBSE_ClientSendTimeoutMS = 1000

    MBSE_StartServer(502)

    print "Client send timeout = 1000 ms"

    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

---

### 5.26 MBSE_SetServerIDString

#### Introduction
Sets the string returned by Modbus function FC11 (Report Server ID).

---

#### Parameters

    sub MBSE_SetServerIDString(byref s as string)

---

#### Usage
Used to identify the emulator to Modbus clients.

If not set, a default string is used.

---

#### Example

    #include "modbustcp_server.bi"

    MBSE_Init()

    MBSE_SetServerIDString("Training PLC Emulator")

    MBSE_StartServer(502)

    print "Custom Server ID set."

    sleep

    MBSE_StopServer()
    MBSE_Shutdown()

    ## 6.0 Full Example Program

This example demonstrates a complete Modbus TCP server lifecycle.

It:
- Starts the server
- Updates a holding register continuously
- Allows external Modbus clients to read changing values

---

### Example

    #include "modbustcp_server.bi"

    MBSE_Init()

    if MBSE_StartServer(502) = 0 then
        print "Failed to start Modbus server"
        MBSE_Shutdown()
        end
    end if

    print "Modbus server running on port 502."
    print "Holding register 0 will increment once per second."
    print "Use a Modbus client (FC03) to read address 0."
    print "Press any key to stop."
    print

    dim value as integer = 0

    do
        MBSE_WriteHoldingRegister(0, value)
        print "Register 0 = "; value
        value += 1
        sleep 1000
    loop until inkey <> ""

    MBSE_StopServer()
    MBSE_Shutdown()

    print "Server stopped."
    sleep

---

## 7.0 Additional Global Variables Summary

The following global variables control server behaviour.

---

### MBSE_StrictUnitID

Controls whether Unit ID must match.

- 0 = ignore Unit ID (default)
- 1 = enforce match

---

### MBSE_ExpectedUnitID

Defines the Unit ID accepted when strict mode is enabled.

- Range: 0–255
- Default: typically 255

---

### MBSE_AddrCeiling

Limits maximum accessible address.

- Requests above this return Modbus exception code 2
- Useful for testing and simulation

---

### MBSE_ClientRecvTimeoutMS

Client receive timeout (milliseconds).

- Controls how long server waits for client data

---

### MBSE_ClientSendTimeoutMS

Client send timeout (milliseconds).

- Prevents blocking when sending to unresponsive clients

---

## 8.0 Debugging

### 8.1 Enabling Debug Output

Enable debug output by placing this before including the library:

    #define MBSE_Debug

---

### 8.2 Debug Output Includes

When enabled, the server will print:

- Client connection and disconnection events
- Incoming Modbus requests
- Outgoing responses
- Socket-level failures

---

### 8.3 When to Use Debugging

Enable debugging when:

- Clients fail to connect
- Requests time out
- Unexpected values are returned
- Diagnosing protocol-level issues

---

## 9.0 Behavioural Notes

### 9.1 Server Independence

Once started, the server runs independently in its own threads.

Your program can:
- Continue executing logic
- Modify registers and coils at runtime
- React to external client activity

---

### 9.2 Thread Safety

All Modbus memory access is internally protected by mutex locks.

- Multiple clients can safely read/write simultaneously
- Direct access to internal arrays is discouraged

---

### 9.3 Addressing

- Modbus addressing starts at 0
- Address N maps directly to internal index N
- No offset is applied internally

---

### 9.4 Port Usage

- Default Modbus TCP port: 502
- May require elevated privileges on some systems
- Ensure no other service is using the port

---

### 9.5 Failure Modes

Common failure cases:

- Port already in use → server fails to start
- Firewall blocking → clients cannot connect
- Wrong Unit ID (strict mode) → client receives no response
- Address out of range → Modbus exception code 2

---

### 9.6 Expected Usage Pattern

Typical usage:

1. Initialize library  
2. Configure global variables (optional)  
3. Start server  
4. Modify memory during runtime  
5. Allow clients to interact  
6. Stop server  
7. Shutdown library