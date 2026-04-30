# -------------------------------------------------------------------------
# Project: FreeBASIC Modbus TCP library
# -------------------------------------------------------------------------

FBC = fbc
FBCFLAGS = -mt -exx -g

TESTS = ModbusTCP_Test ModbusTCP_Server_Test validation TestPLC pulldata

all: $(TESTS)

# Rule for building each test program
%: %.bas modbustcp.bi modbustcp_server.bi
	@echo "Building $@..."
	$(FBC) $(FBCFLAGS) $< -x $@

clean:
	@echo "Cleaning up..."
	rm -f $(TESTS)

.PHONY: all clean
