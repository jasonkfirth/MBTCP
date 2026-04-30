# FreeBASIC Modbus TCP Library

A Modbus TCP library for FreeBASIC, providing both client (master) and server (slave) capabilities. This project is designed for maintainability, portability, and as an educational resource for systems programmers.

## Features

- **Client Library (`modbustcp.bi`)**: A lightweight wrapper for communicating with Modbus TCP devices (PLCs, sensors, controllers).
- **Server Emulator (`modbustcp_server.bi`)**: A multi-client, multi-threaded Modbus TCP server emulator for testing, training, and simulation.
- **Platform Agnostic**: Runs on Linux, Haiku, FreeBSD, OpenBSD, NetBSD, Dragonfly, macOS, and Windows (via Cygwin or MinGW).
- **Educational Design**: Code follows a clear style guide emphasizing intent-based commenting and architectural separation.

## Getting Started

### Prerequisites

- **FreeBASIC Compiler (`fbc`)**: Ensure the FreeBASIC compiler is installed and in your system PATH.
- **GNU Make**: Used for building the included test and validation suites.

### Installation

To use the library in your project, copy the appropriate `.bi` file into your project directory and include it:

```freebasic
#include "modbustcp.bi"
' or
#include "modbustcp_server.bi"
```

## Building and Validation

A `GNUmakefile` is provided to build all demonstration and test programs.

### Build all tests
```bash
make
```

### Run the Validation Harness
The validation harness (`validation.bas`) provides an automated end-to-end test suite that verifies client-server integration, protocol correctness, and error handling.

```bash
./validation
```

## Documentation

Detailed documentation for each component is available in the repository:
- [Client Library Manual](modbustcp%20manual.md)
- [Server Emulator Manual](modbustcp_server_manual.md)

## Coding Standards

This project follows a strict systems programming style guide. All source files include:
- Detailed headers explaining purpose and responsibilities.
- Section banners for easy navigation.
- Intent-based commenting ("Why", not "What").
- Explicit magic number documentation.
- Thread-safe memory access models.

## Reliability and Portability

- **Multi-threading**: The server uses a thread-per-connection model. Always use the `-mt` compiler flag when building.
- **No Dependencies**: Relies only on the standard FreeBASIC runtime and platform-native socket APIs.
- **Robust Access**: Memory regions in the emulator are protected by mutexes.

## License

This project is released under the MIT License. See the [LICENSE](LICENSE) file for details.
