/* -------------------------------------------------------------------------
 / Project: FreeBASIC Modbus TCP library
 / -------------------------------------------------------------------------
 /
 / File: mbtcp_server.h
 /
 / Purpose:
 /
 /     C API header for the Modbus TCP server library.
 /
 / Responsibilities:
 /
 /      - Defining the C interface for server Modbus operations.
 /
 / This file intentionally does NOT contain:
 /
 /      - Implementation details (see mbtcp_server_wrapper.bas).
 / ------------------------------------------------------------------------- */

#ifndef MBTCP_SERVER_H
#define MBTCP_SERVER_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* -------------------------------------------------------------------------
 / Function Prototypes
 / ------------------------------------------------------------------------- */

void mbse_init(void);
void mbse_shutdown(void);

int32_t mbse_start_server(int32_t port);
void mbse_stop_server(void);

void mbse_set_server_id_string(const char* s);

/* Data Access Functions */
void mbse_write_coil(int32_t addr, uint8_t value);
uint8_t mbse_read_coil(int32_t addr);

void mbse_write_discrete_input(int32_t addr, uint8_t value);
uint8_t mbse_read_discrete_input(int32_t addr);

void mbse_write_holding_register(int32_t addr, uint16_t value);
uint16_t mbse_read_holding_register(int32_t addr);

void mbse_write_input_register(int32_t addr, uint16_t value);
uint16_t mbse_read_input_register(int32_t addr);

void mbse_write_long(int32_t addr, int32_t value);
int32_t mbse_read_long(int32_t addr);

void mbse_write_float(int32_t addr, float value);
float mbse_read_float(int32_t addr);

void mbse_write_input_long(int32_t addr, int32_t value);
int32_t mbse_read_input_long(int32_t addr);

void mbse_write_input_float(int32_t addr, float value);
float mbse_read_input_float(int32_t addr);

/* Config getters/setters */
void mbse_set_strict_unit_id(int32_t strict);
void mbse_set_expected_unit_id(uint8_t id);
void mbse_set_addr_ceiling(int32_t ceiling);
void mbse_set_client_timeouts(int32_t recv_ms, int32_t send_ms);
int32_t mbse_get_client_count(void);

#ifdef __cplusplus
}
#endif

#endif /* MBTCP_SERVER_H */

/* end of mbtcp_server.h */
