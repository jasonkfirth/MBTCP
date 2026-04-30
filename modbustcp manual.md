# MBTCP FreeBASIC Library Manual

## 1.0 Summary
This document explains how to use the MBTCP FreeBASIC library.

## 1.1 Intended Audience
This document is intended as a guide for users of the library, particularly those who are operating outside their normal areas of competence.

---

## 2.0 Updating Instructions
Upon making changes to Instructions

---

## 3.0 Introduction
This library makes assumptions to reduce the complexity on the user interface:

- Assumes only one PLC connection at a time.
- Handles connections internally (no manual socket handling required).
- Uses blocking sockets:
  - Requests are sent and the program waits for a response.
  - No polling required.
  - The program will pause during delays or communication issues.
  - On major failure, communication aborts and an error variable is set.

---

## 4.0 Getting Started

### 4.1 Setting up FreeBASIC & FBIDE

1. Download FreeBASIC: http://www.freebasic.net  
2. Download fbIDE: http://fbide.sourceforge.net  
3. Install fbIDE  
4. Install FreeBASIC into the fbIDE directory  

---

### 4.2 Loading the Library

Copy MBTCP.bi into your project directory and include:

    #include "MBTCP.bi"

---

### 4.3 Initialisation and Shutdown

    MBTCP_Init()
    MBTCP_doShutdown()

- Call MBTCP_Init() after including the library.
- Call MBTCP_doShutdown() before program exit.

---

### 4.4 Connecting and Disconnecting

    MBTCP_Connect("HOSTNAME")
    MBTCP_Disconnect()

- HOSTNAME = IP or resolvable name
- Only one active connection is supported

---

## 5.0 Commands

### 5.1 MBTCP_Init

#### Introduction
Initialises the library (e.g. Winsock on Win32).

#### Parameters
None

#### Usage
Must be called before any MBTCP operations.

#### Example

    #include "ModbusTCP.bi"
    MBTCP_Init()

---

### 5.2 MBTCP_doShutdown

#### Introduction
Shuts down the library.

#### Parameters
None

#### Usage
Call before program exit.

#### Example

    #include "ModbusTCP.bi"
    MBTCP_Init()
    REM All your MBTCP code goes here
    MBTCP_doShutdown()

---

### 5.3 MBTCP_Connect

#### Parameters

    sub MBTCP_Connect(hostname as string)

#### Behaviour
- Resolves hostname
- Opens socket
- Connects to PLC

#### Errors
- Resolve failure → MBTCP_resolveHost(): invalid address
- Socket failure → MBTCP: socket()
- Connect failure → MBTCP: connect()
- Sets MBP_Connection_Failure = 1

#### Example

    #include "ModbusTCP.bi"
    MBTCP_Init()
    MBTCP_Connect("90.0.0.1")
    MBTCP_doShutdown()

### 5.7 MBTCP_RetrieveRegister

#### Introduction
Returns 16-bit value from holding register (4XXXXX).

#### Parameters

    function MBTCP_RetrieveRegister (RegisterNumber as short) as integer

#### Usage
Reads a single holding register. Addressing starts at 0. Use MBP_ZeroOffset if required.

#### Example

    #include "ModbusTCP.bi"
    MBTCP_Init()
    MBTCP_Connect("90.0.0.1")

    PRINT "Register 1 = "; MBTCP_RetrieveRegister(1)

    MBTCP_Disconnect()
    MBTCP_doShutdown()

---

### 5.8 MBTCP_RetrieveFloatRegister

#### Introduction
Returns 32-bit floating point value from two registers.

#### Parameters

    function MBTCP_RetrieveFloatRegister (RegisterNumber as short) as single

#### Usage
Reads RegisterNumber and RegisterNumber+1.

#### Example

    #include "ModbusTCP.bi"
    MBTCP_Init()
    MBTCP_Connect("90.0.0.1")

    PRINT "Float @1 = "; MBTCP_RetrieveFloatRegister(1)

    MBTCP_Disconnect()
    MBTCP_doShutdown()

---

### 5.9 MBTCP_RetrieveLongRegister

#### Introduction
Returns 32-bit integer from two registers.

#### Parameters

    function MBTCP_RetrieveLongRegister (RegisterNumber as short) as long

#### Example

    #include "ModbusTCP.bi"
    MBTCP_Init()
    MBTCP_Connect("90.0.0.1")

    PRINT "Long @1 = "; MBTCP_RetrieveLongRegister(1)

    MBTCP_Disconnect()
    MBTCP_doShutdown()

---

### 5.10 MBTCP_RetrieveInputRegister

#### Introduction
Returns 16-bit value from input register (3XXXXX).

#### Parameters

    function MBTCP_RetrieveInputRegister (RegisterNumber as short) as integer

#### Example

    #include "ModbusTCP.bi"
    MBTCP_Init()
    MBTCP_Connect("90.0.0.1")

    PRINT "Input Register 1 = "; MBTCP_RetrieveInputRegister(1)

    MBTCP_Disconnect()
    MBTCP_doShutdown()

---

### 5.11 MBTCP_WriteCoil

#### Introduction
Writes ON/OFF to a coil (FC05).

#### Parameters

    function MBTCP_WriteCoil (Value as integer, CoilNumber as integer) as integer

#### Example

    #include "ModbusTCP.bi"
    MBTCP_Init()
    MBTCP_Connect("90.0.0.1")

    MBTCP_WriteCoil(1, 10)
    PRINT "Coil 10 ON"

    MBTCP_WriteCoil(0, 10)
    PRINT "Coil 10 OFF"

    MBTCP_Disconnect()
    MBTCP_doShutdown()

---

### 5.12 MBTCP_WriteRegister

#### Introduction
Writes 16-bit value to holding register (FC06).

#### Parameters

    function MBTCP_WriteRegister (Value as short, RegisterNumber as integer) as integer

#### Example

    #include "ModbusTCP.bi"
    MBTCP_Init()
    MBTCP_Connect("90.0.0.1")

    MBTCP_WriteRegister(1234, 10)
    PRINT "Register 10 = 1234"

    MBTCP_Disconnect()
    MBTCP_doShutdown()

---

### 5.13 MBTCP_WriteFloatRegister

#### Introduction
Writes 32-bit float across two registers.

#### Parameters

    function MBTCP_WriteFloatRegister (Value as single, RegisterNumber as integer) as integer

#### Example

    #include "ModbusTCP.bi"
    MBTCP_Init()
    MBTCP_Connect("90.0.0.1")

    MBTCP_WriteFloatRegister(123.456, 100)
    PRINT "Float written to 100/101"

    MBTCP_Disconnect()
    MBTCP_doShutdown()

---

### 5.14 MBTCP_WriteLongRegister

#### Introduction
Writes 32-bit integer across two registers.

#### Parameters

    function MBTCP_WriteLongRegister (Value as long, RegisterNumber as integer) as integer

#### Example

    #include "ModbusTCP.bi"
    MBTCP_Init()
    MBTCP_Connect("90.0.0.1")

    MBTCP_WriteLongRegister(&H12345678, 200)
    PRINT "Long written to 200/201"

    MBTCP_Disconnect()
    MBTCP_doShutdown()

---

### 5.15 MBTCP_WriteMultipleRegisters

#### Introduction
Writes multiple registers (FC16).

#### Parameters

    function MBTCP_WriteMultipleRegisters (Values() as ushort, StartRegister as integer) as integer

#### Example

    #include "ModbusTCP.bi"
    MBTCP_Init()
    MBTCP_Connect("90.0.0.1")

    DIM vals(0 to 2) as ushort
    vals(0) = 111
    vals(1) = 222
    vals(2) = 333

    MBTCP_WriteMultipleRegisters(vals(), 50)

    MBTCP_Disconnect()
    MBTCP_doShutdown()

---

### 5.16 MBTCP_WriteMultipleCoils

#### Introduction
Writes multiple coils (FC15).

#### Parameters

    function MBTCP_WriteMultipleCoils (Values() as ubyte, StartCoil as integer) as integer

#### Example

    #include "ModbusTCP.bi"
    MBTCP_Init()
    MBTCP_Connect("90.0.0.1")

    DIM vals(0 to 3) as ubyte
    vals(0)=1 : vals(1)=0 : vals(2)=1 : vals(3)=1

    MBTCP_WriteMultipleCoils(vals(), 100)

    MBTCP_Disconnect()
    MBTCP_doShutdown()

---

### 5.17 MBTCP_ReadExceptionStatus

#### Example

    #include "ModbusTCP.bi"
    DIM status as integer

    MBTCP_Init()
    MBTCP_Connect("90.0.0.1")

    status = MBTCP_ReadExceptionStatus()
    PRINT "Status = "; status

    MBTCP_Disconnect()
    MBTCP_doShutdown()

---

### 5.18 MBTCP_Diagnostics

#### Example

    #include "ModbusTCP.bi"
    DIM rc as integer
    DIM outData as ushort

    MBTCP_Init()
    MBTCP_Connect("90.0.0.1")

    rc = MBTCP_Diagnostics(&H0000, &H55AA, outData)
    PRINT "Returned: "; outData

    MBTCP_Disconnect()
    MBTCP_doShutdown()

---

### 5.19 MBTCP_GetCommEventCounter

#### Example

    #include "ModbusTCP.bi"
    DIM ctr as MBTCP_CommEventCounterResult

    MBTCP_Init()
    MBTCP_Connect("90.0.0.1")

    MBTCP_GetCommEventCounter(ctr)

    PRINT ctr.status
    PRINT ctr.eventCount

    MBTCP_Disconnect()
    MBTCP_doShutdown()

---

### 5.20 MBTCP_GetCommEventLog

#### Example

    #include "ModbusTCP.bi"
    DIM logRes as MBTCP_CommEventLogResult

    MBTCP_Init()
    MBTCP_Connect("90.0.0.1")

    MBTCP_GetCommEventLog(logRes)

    PRINT logRes.eventCount

    MBTCP_Disconnect()
    MBTCP_doShutdown()

---

### 5.21 MBTCP_ReportServerID

#### Example

    #include "ModbusTCP.bi"
    DIM id as string

    MBTCP_Init()
    MBTCP_Connect("90.0.0.1")

    MBTCP_ReportServerID(id)
    PRINT id

    MBTCP_Disconnect()
    MBTCP_doShutdown()

---

### 5.22 MBTCP_ReadWriteMultipleRegisters

#### Example

    #include "ModbusTCP.bi"

    DIM writeVals(0 to 1) as ushort
    DIM readVals() as ushort

    writeVals(0)=&H1111
    writeVals(1)=&H2222

    MBTCP_Init()
    MBTCP_Connect("90.0.0.1")

    MBTCP_ReadWriteMultipleRegisters(100, 2, 110, writeVals(), readVals())

    PRINT readVals(0)
    PRINT readVals(1)

    MBTCP_Disconnect()
    MBTCP_doShutdown()

---

### 5.23 MBTCP_MaskWriteRegister

#### Example

    #include "ModbusTCP.bi"

    DIM beforeVal as integer
    DIM afterVal as integer

    MBTCP_Init()
    MBTCP_Connect("90.0.0.1")

    beforeVal = MBTCP_RetrieveRegister(300)

    MBTCP_MaskWriteRegister(300, &HFFF0, &H0005)

    afterVal = MBTCP_RetrieveRegister(300)

    PRINT beforeVal
    PRINT afterVal

    MBTCP_Disconnect()
    MBTCP_doShutdown()

    ---

## 6.0 Additional Global Variables

### 6.1 MBP_UnitID

Defines Modbus Unit Identifier.

- Default: 255
- Must match PLC expectations

Example:

    MBP_UnitID = 255

---

## 7.0 Debugging

### 7.1 MBTCP_Debug

Enable with:

    #define MBTCP_Debug

Outputs:
- Requests sent
- Responses received
- Byte counts
- Communication failures

Useful for diagnosing:
- Hangs
- Addressing issues
- Unexpected PLC responses