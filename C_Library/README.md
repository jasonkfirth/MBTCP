# Modbus TCP C Library

This folder contains a C-compatible version of the FreeBASIC Modbus TCP library. It allows C and C++ projects to utilize the robust Modbus TCP client and server implementation written in FreeBASIC.

## Files

- `mbtcp.h`: Header file for the Modbus TCP client.
- `mbtcp_server.h`: Header file for the Modbus TCP server emulator.
- `libmbtcp.a`: Static library for the client.
- `libmbtcp_server.a`: Static library for the server.
- `validation_c.c`: C implementation of the validation harness.

## Usage

### Inclusion

Include the headers in your C code:

```c
#include "mbtcp.h"
#include "mbtcp_server.h"
```

### Linking

When linking your C project, you must link against the produced `.a` files as well as the FreeBASIC runtime and system dependencies.

Example linking flags (on Linux):

```bash
gcc your_code.c -o your_app \
    -L. -lmbtcp -lmbtcp_server \
    -L/usr/local/lib/freebasic/linux-x86_64 \
    -lfbmt -lpthread -ltinfo -no-pie
```

**Note**: The `-no-pie` flag may be required on modern Linux distributions if the FreeBASIC runtime was not compiled as position-independent code.

## Building

The libraries are built using the main project `GNUmakefile`:

```bash
make
```

This will produce the `.a` files and the `validation_c` test executable.

## API Overview

The C API follows the FreeBASIC API closely, but uses lowercase names:

- `MBTCP_Connect` -> `mbtcp_connect`
- `MBSE_StartServer` -> `mbse_start_server`
- etc.

See the header files for full function declarations.
