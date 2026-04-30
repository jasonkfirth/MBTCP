/* -------------------------------------------------------------------------
 / Project: FreeBASIC Modbus TCP library
 / -------------------------------------------------------------------------
 /
 / File: mbtcp.h
 /
 / Purpose:
 /
 /     C API header for the Modbus TCP client library.
 /
 / Responsibilities:
 /
 /      - Defining the C interface for client Modbus operations.
 /
 / This file intentionally does NOT contain:
 /
 /      - Implementation details (see mbtcp_wrapper.bas).
 / ------------------------------------------------------------------------- */

#ifndef MBTCP_H
#define MBTCP_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* -------------------------------------------------------------------------
 / Constants and Types
 / ------------------------------------------------------------------------- */

#define MBTCP_COMM_ERROR -32768

typedef struct {
    uint16_t status;
    uint16_t event_count;
} mbtcp_comm_event_counter_result_t;

typedef struct {
    uint16_t status;
    uint16_t event_count;
    uint16_t message_count;
    int32_t  n_events;
    uint8_t  events[64];
} mbtcp_comm_event_log_result_t;

/* -------------------------------------------------------------------------
 / Function Prototypes
 / ------------------------------------------------------------------------- */

void mbtcp_init(void);
void mbtcp_set_port(int32_t port);
void mbtcp_connect(const char* ip);
void mbtcp_disconnect(void);

int32_t mbtcp_retrieve_coil(int32_t coil_number);
int32_t mbtcp_retrieve_discrete_input(int32_t coil_number);
int32_t mbtcp_retrieve_register(int32_t reg_number);
int32_t mbtcp_retrieve_input_register(int32_t reg_number);
int32_t mbtcp_retrieve_long_register(int32_t reg_number);
float   mbtcp_retrieve_float_register(int32_t reg_number);

int32_t mbtcp_write_coil(int32_t value, int32_t coil_number);
int32_t mbtcp_write_register(int16_t value, int32_t reg_number);
int32_t mbtcp_write_long_register(int32_t value, int32_t reg_number);
int32_t mbtcp_write_float_register(float value, int32_t reg_number);

int32_t mbtcp_write_multiple_registers(const uint16_t* values, int32_t count, int32_t start_reg);
int32_t mbtcp_write_multiple_coils(const uint8_t* values, int32_t count, int32_t start_coil);

int32_t mbtcp_read_exception_status(void);
int32_t mbtcp_diagnostics(uint16_t sub_func, uint16_t in_data, uint16_t* out_data);

int32_t mbtcp_get_comm_event_counter(mbtcp_comm_event_counter_result_t* out_res);
int32_t mbtcp_get_comm_event_log(mbtcp_comm_event_log_result_t* out_res);

int32_t mbtcp_report_server_id(char* out_id, int32_t max_len);

int32_t mbtcp_read_write_multiple_registers(
    int32_t  read_start,
    int32_t  read_qty,
    int32_t  write_start,
    const uint16_t* write_values,
    int32_t  write_qty,
    uint16_t* out_read_values);

int32_t mbtcp_mask_write_register(int32_t reg_number, uint16_t and_mask, uint16_t or_mask);

/* Global getters/setters */
void mbtcp_set_timeout(int32_t ms);
int32_t mbtcp_get_timeout(void);
void mbtcp_set_unit_id(int32_t id);
int32_t mbtcp_get_unit_id(void);
void mbtcp_set_zero_offset(int32_t offset);
int32_t mbtcp_get_zero_offset(void);
void mbtcp_get_last_error(char* out_err, int32_t max_len);

#ifdef __cplusplus
}
#endif

#endif /* MBTCP_H */

/* end of mbtcp.h */
