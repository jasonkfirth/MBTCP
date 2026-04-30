/* -------------------------------------------------------------------------
 / Project: FreeBASIC Modbus TCP library
 / -------------------------------------------------------------------------
 /
 / File: validation_c.c
 /
 / Purpose:
 /
 /     C Implementation of the Modbus TCP Integration / Validation Harness.
 /
 / Responsibilities:
 /
 /      - Executing Modbus client (MBTCP) tests from C.
 /      - Validating integration between C-API and FB-backend.
 /
 / This file intentionally does NOT contain:
 /
 /      - Core Modbus protocol logic (delegated to the library).
 / ------------------------------------------------------------------------- */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <math.h>
#include <time.h>
#include "mbtcp.h"
#include "mbtcp_server.h"

/* -------------------------------------------------------------------------
 / Configuration and Globals
 / ------------------------------------------------------------------------- */

#define HARNESS_HOST "127.0.0.1"
#define HARNESS_PORT 1502

int32_t g_pass = 0;
int32_t g_fail = 0;

/* -------------------------------------------------------------------------
 / Helper Functions
 / ------------------------------------------------------------------------- */

void test_result(const char* test_name, int32_t passed, const char* details) {
    if (passed) {
        g_pass++;
        printf("[PASS] %s", test_name);
        if (details && details[0]) printf(" -- %s\n", details);
        else printf("\n");
    } else {
        g_fail++;
        printf("[FAIL] %s", test_name);
        if (details && details[0]) printf(" -- %s\n", details);
        else printf("\n");
    }
}

/* -------------------------------------------------------------------------
 / Main Entry Point
 / ------------------------------------------------------------------------- */

int main() {
    printf("========================================\n");
    printf(" Modbus TCP C Validation Harness\n");
    printf("========================================\n\n");

    // Initialize and start server
    mbse_init();
    if (mbse_start_server(HARNESS_PORT) == 0) {
        test_result("Server Start", 0, "Could not start MBSE server");
        return 1;
    }
    test_result("Server Start", 1, "Listening on port 1502");

    // Initialize client
    mbtcp_init();
    mbtcp_set_port(HARNESS_PORT);

    mbtcp_connect(HARNESS_HOST);

    char last_err[256];
    mbtcp_get_last_error(last_err, 256);

    if (last_err[0] == 0) {
        test_result("Client Connect", 1, "Connected to 127.0.0.1:1502");
    } else {
        test_result("Client Connect", 0, last_err);
        mbse_shutdown();
        return 1;
    }

    // Test #1: Read/Write Holding Register
    printf("\nTest #1: Read/Write Holding Register\n");
    uint16_t val = 0x1234;
    mbtcp_write_register(val, 100);
    int32_t read_val = mbtcp_retrieve_register(100);
    test_result("Holding Register 100", (read_val == val), (read_val == val ? "OK" : "Mismatch"));

    // Test #2: Read/Write Coil
    printf("\nTest #2: Read/Write Coil\n");
    mbtcp_write_coil(1, 50);
    int32_t coil_val = mbtcp_retrieve_coil(50);
    test_result("Coil 50", (coil_val == 1), (coil_val == 1 ? "OK" : "Mismatch"));

    // Test #3: Multi-register write
    printf("\nTest #3: Multi-register write\n");
    uint16_t multi_vals[3] = {0x1111, 0x2222, 0x3333};
    mbtcp_write_multiple_registers(multi_vals, 3, 200);
    int32_t multi_ok = 1;
    if (mbtcp_retrieve_register(200) != 0x1111) multi_ok = 0;
    if (mbtcp_retrieve_register(201) != 0x2222) multi_ok = 0;
    if (mbtcp_retrieve_register(202) != 0x3333) multi_ok = 0;
    test_result("Multiple Registers", multi_ok, (multi_ok ? "OK" : "Mismatch"));

    // Test #4: Farm Test (64 Sequential Connections)
    printf("\nTest #4: Farm Test (64 Sequential Connections)\n");
    int32_t farm_ok = 1;
    for (int i = 0; i < 64; i++) {
        mbtcp_disconnect();
        mbtcp_connect(HARNESS_HOST);
        if (mbtcp_retrieve_register(100) != 0x1234) {
            farm_ok = 0;
            break;
        }
    }
    test_result("Farm Test", farm_ok, (farm_ok ? "64 connections handled" : "Failed"));

    printf("\n========================================\n");
    printf(" Validation Complete\n");
    printf("----------------------------------------\n");
    printf(" PASS: %d\n", g_pass);
    printf(" FAIL: %d\n", g_fail);
    printf("========================================\n");

    mbtcp_disconnect();
    mbse_stop_server();
    mbse_shutdown();

    return g_fail > 0;
}

/* end of validation_c.c */
