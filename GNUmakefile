# -------------------------------------------------------------------------
# Project: FreeBASIC Modbus TCP library
# -------------------------------------------------------------------------

FBC = fbc
FBCFLAGS = -mt -exx -g

# Display the compiler's lib/ path
FBLIBDIR := $(shell $(FBC) -print fblibdir)

TESTS = ModbusTCP_Test ModbusTCP_Server_Test validation TestPLC pulldata

CLIB_DIR = C_Library
CLIB_CLIENT = $(CLIB_DIR)/libmbtcp.a
CLIB_SERVER = $(CLIB_DIR)/libmbtcp_server.a
C_VAL = $(CLIB_DIR)/validation_c

all: $(TESTS) $(CLIB_CLIENT) $(CLIB_SERVER) $(C_VAL)

# Rule for building each test program
%: %.bas modbustcp.bi modbustcp_server.bi fix_errno.bi
	@echo "Building $@..."
	$(FBC) $(FBCFLAGS) $< -x $@

# Rules for building the C library
$(CLIB_CLIENT): mbtcp_wrapper.bas modbustcp.bi
	@echo "Building C Client Library..."
	$(FBC) -lib mbtcp_wrapper.bas -x $@

$(CLIB_SERVER): mbtcp_server_wrapper.bas modbustcp_server.bi fix_errno.bi
	@echo "Building C Server Library..."
	$(FBC) -lib mbtcp_server_wrapper.bas -x $@

$(C_VAL): $(CLIB_DIR)/validation_c.c $(CLIB_CLIENT) $(CLIB_SERVER)
	@echo "Building C Validation Harness..."
	gcc -no-pie -I$(CLIB_DIR) $< -o $@ $(CLIB_CLIENT) $(CLIB_SERVER) -L$(FBLIBDIR) -lfbmt -lpthread -ltinfo

clean:
	@echo "Cleaning up..."
	rm -f $(TESTS)
	rm -f $(CLIB_CLIENT) $(CLIB_SERVER) $(C_VAL)

.PHONY: all clean
