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
#include <stdint.h>
#include <limits.h>
#include <errno.h>
#include <pthread.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include "mbtcp.h"
#include "mbtcp_server.h"

/* -------------------------------------------------------------------------
 / Configuration and Globals
 / ------------------------------------------------------------------------- */

typedef struct
{
    char host[128];
    int32_t port;
    int32_t connect_timeout_ms;
    int32_t socket_timeout_ms;
    int32_t farm_connections;
    int32_t raw_client_threads;
    int32_t raw_client_iterations;
    int32_t raw_client_timeout_ms;
} harness_config_t;

int32_t g_pass = 0;
int32_t g_fail = 0;
static int32_t g_runtime_started = 0;
static harness_config_t g_cfg;

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

static int32_t parse_int_env(const char* name, int32_t default_value) {
    char* value = getenv(name);
    if (value == 0 || value[0] == 0) {
        return default_value;
    }

    char* end_ptr = 0;
    long parsed = strtol(value, &end_ptr, 10);
    if (end_ptr == value || *end_ptr != 0) {
        return default_value;
    }
    if (parsed <= 0 || parsed > INT32_MAX) {
        return default_value;
    }
    return (int32_t)parsed;
}

static void print_usage(const char* prog) {
    printf("Usage: %s [--host HOST] [--port PORT] [--connect-timeout MS] [--socket-timeout MS] ", prog);
    printf("[--farm COUNT] [--raw-workers COUNT] [--raw-iterations COUNT]\n");
    printf("Environment overrides:\n");
    printf("  MBTCP_HARNESS_HOST, MBTCP_HARNESS_PORT, MBTCP_CONNECT_TIMEOUT_MS\n");
    printf("  MBTCP_SOCKET_TIMEOUT_MS, MBTCP_FARM_CONNECTIONS\n");
    printf("  MBTCP_RAW_WORKERS, MBTCP_RAW_ITERATIONS\n");
}

static void config_init_from_env(harness_config_t* cfg) {
    const char* default_host = "127.0.0.1";
    const char* env_host = getenv("MBTCP_HARNESS_HOST");
    const char* host = (env_host != 0 && env_host[0] != 0) ? env_host : default_host;

    memset(cfg, 0, sizeof(*cfg));
    strncpy(cfg->host, host, sizeof(cfg->host) - 1);
    cfg->host[sizeof(cfg->host) - 1] = 0;
    cfg->port = parse_int_env("MBTCP_HARNESS_PORT", 1502);
    cfg->connect_timeout_ms = parse_int_env("MBTCP_CONNECT_TIMEOUT_MS", 3000);
    cfg->socket_timeout_ms = parse_int_env("MBTCP_SOCKET_TIMEOUT_MS", 1000);
    cfg->farm_connections = parse_int_env("MBTCP_FARM_CONNECTIONS", 64);
    cfg->raw_client_threads = parse_int_env("MBTCP_RAW_WORKERS", 8);
    cfg->raw_client_iterations = parse_int_env("MBTCP_RAW_ITERATIONS", 8);
    cfg->raw_client_timeout_ms = parse_int_env("MBTCP_RAW_TIMEOUT_MS", 1000);
}

static int32_t parse_int_arg(const char* value, int32_t default_value, int32_t min_value) {
    if (value == 0 || value[0] == 0) {
        return default_value;
    }
    char* end_ptr = 0;
    long parsed = strtol(value, &end_ptr, 10);
    if (end_ptr == value || *end_ptr != 0) {
        return default_value;
    }
    if (parsed < min_value || parsed > INT32_MAX) {
        return default_value;
    }
    return (int32_t)parsed;
}

static void config_apply_args(int argc, char** argv, harness_config_t* cfg) {
    int i = 1;
    while (i < argc) {
        if (strcmp(argv[i], "--host") == 0) {
            if (i + 1 >= argc) {
                print_usage(argv[0]);
                exit(1);
            }
            strncpy(cfg->host, argv[i + 1], sizeof(cfg->host) - 1);
            cfg->host[sizeof(cfg->host) - 1] = 0;
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--port") == 0) {
            if (i + 1 >= argc) {
                print_usage(argv[0]);
                exit(1);
            }
            cfg->port = parse_int_arg(argv[i + 1], cfg->port, 1);
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--connect-timeout") == 0) {
            if (i + 1 >= argc) {
                print_usage(argv[0]);
                exit(1);
            }
            cfg->connect_timeout_ms = parse_int_arg(argv[i + 1], cfg->connect_timeout_ms, 1);
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--socket-timeout") == 0) {
            if (i + 1 >= argc) {
                print_usage(argv[0]);
                exit(1);
            }
            cfg->socket_timeout_ms = parse_int_arg(argv[i + 1], cfg->socket_timeout_ms, 1);
            cfg->raw_client_timeout_ms = cfg->socket_timeout_ms;
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--farm") == 0) {
            if (i + 1 >= argc) {
                print_usage(argv[0]);
                exit(1);
            }
            cfg->farm_connections = parse_int_arg(argv[i + 1], cfg->farm_connections, 1);
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--raw-workers") == 0) {
            if (i + 1 >= argc) {
                print_usage(argv[0]);
                exit(1);
            }
            cfg->raw_client_threads = parse_int_arg(argv[i + 1], cfg->raw_client_threads, 1);
            i += 2;
            continue;
        }
        if (strcmp(argv[i], "--raw-iterations") == 0) {
            if (i + 1 >= argc) {
                print_usage(argv[0]);
                exit(1);
            }
            cfg->raw_client_iterations = parse_int_arg(argv[i + 1], cfg->raw_client_iterations, 1);
            i += 2;
            continue;
        }

        print_usage(argv[0]);
        exit(1);
    }
}

static void set_socket_timeout(int32_t sock, int32_t timeout_ms) {
    struct timeval tv;
    tv.tv_sec = timeout_ms / 1000;
    tv.tv_usec = (timeout_ms % 1000) * 1000;
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, (const void*) &tv, sizeof(tv));
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, (const void*) &tv, sizeof(tv));
}

static int32_t recv_exact(int32_t sock, uint8_t* out, int32_t expected) {
    int32_t total = 0;
    while (total < expected) {
        int32_t got = recv(sock, out + total, expected - total, 0);
        if (got == 0) return 0;
        if (got < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK || errno == ETIMEDOUT) {
                return -1;
            }
            return -2;
        }
        total += got;
    }
    return total;
}

static int32_t open_raw_socket(const char* host, int32_t port, int32_t timeout_ms, char* err_out, int32_t err_len) {
    int32_t sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (sock < 0) {
        if (err_out && err_len > 0) {
            snprintf(err_out, err_len, "socket() failed");
        }
        return -1;
    }

    set_socket_timeout(sock, timeout_ms);

    struct sockaddr_in sa;
    sa.sin_family = AF_INET;
    sa.sin_port = htons((uint16_t)port);
    if (inet_pton(AF_INET, host, &sa.sin_addr) != 1) {
        close(sock);
        if (err_out && err_len > 0) {
            snprintf(err_out, err_len, "inet_pton() failed for %s", host);
        }
        return -1;
    }

    if (connect(sock, (struct sockaddr*)&sa, sizeof(sa)) != 0) {
        close(sock);
        if (err_out && err_len > 0) {
            snprintf(err_out, err_len, "connect() failed");
        }
        return -1;
    }

    return sock;
}

static int32_t raw_read_register_once(
        const char* host,
        int32_t port,
        uint16_t reg,
        uint8_t trans_lo,
        int32_t timeout_ms,
        uint16_t* value_out,
        char* err_out,
        int32_t err_len) {

    int32_t sock = open_raw_socket(host, port, timeout_ms, err_out, err_len);
    if (sock < 0) return MBTCP_COMM_ERROR;

    uint8_t req[12] = {0};
    req[1] = trans_lo;
    req[4] = 0;
    req[5] = 6;
    req[6] = 255;
    req[7] = 3;
    req[8] = (uint8_t) ((reg >> 8) & 0xFF);
    req[9] = (uint8_t) (reg & 0xFF);
    req[10] = 0;
    req[11] = 1;

    if (send(sock, req, sizeof(req), 0) < (int32_t)sizeof(req)) {
        if (err_out && err_len > 0) snprintf(err_out, err_len, "send() failed");
        close(sock);
        return MBTCP_COMM_ERROR;
    }

    uint8_t hdr[6];
    int32_t got = recv_exact(sock, hdr, 6);
    if (got <= 0) {
        if (err_out && err_len > 0) snprintf(err_out, err_len, "recv() failed on MBAP header");
        close(sock);
        return MBTCP_COMM_ERROR;
    }

    uint16_t length = (uint16_t)(hdr[4] << 8 | hdr[5]);
    if (length < 5) {
        if (err_out && err_len > 0) snprintf(err_out, err_len, "invalid MBAP length");
        close(sock);
        return MBTCP_COMM_ERROR;
    }
    if (length > 255) {
        if (err_out && err_len > 0) snprintf(err_out, err_len, "MBAP length too large");
        close(sock);
        return MBTCP_COMM_ERROR;
    }

    uint8_t* body = malloc(length);
    if (body == 0) {
        if (err_out && err_len > 0) snprintf(err_out, err_len, "malloc(%u) failed", length);
        close(sock);
        return MBTCP_COMM_ERROR;
    }
    if (recv_exact(sock, body, length) <= 0) {
        free(body);
        if (err_out && err_len > 0) snprintf(err_out, err_len, "recv() failed on PDU");
        close(sock);
        return MBTCP_COMM_ERROR;
    }

    close(sock);

    if (hdr[0] != 0 || hdr[1] != trans_lo) {
        if (err_out && err_len > 0) snprintf(err_out, err_len, "unexpected transaction");
        free(body);
        return MBTCP_COMM_ERROR;
    }
    if (hdr[2] != 0 || hdr[3] != 0) {
        if (err_out && err_len > 0) snprintf(err_out, err_len, "protocol id mismatch");
        free(body);
        return MBTCP_COMM_ERROR;
    }
    if (body[0] != 255 || body[1] != 3) {
        if (err_out && err_len > 0) snprintf(err_out, err_len, "unexpected unit/function");
        free(body);
        return MBTCP_COMM_ERROR;
    }
    if (body[2] != 2 || length < 5) {
        if (err_out && err_len > 0) snprintf(err_out, err_len, "invalid byte count");
        free(body);
        return MBTCP_COMM_ERROR;
    }

    if (value_out != 0) {
        *value_out = (uint16_t)((body[3] << 8) | body[4]);
    }
    free(body);
    return 0;
}

static int32_t raw_send_and_expect_no_reply(
        const char* host,
        int32_t port,
        const uint8_t* frame,
        int32_t frame_len,
        int32_t timeout_ms,
        char* err_out,
        int32_t err_len) {

    int32_t sock = open_raw_socket(host, port, timeout_ms, err_out, err_len);
    if (sock < 0) return MBTCP_COMM_ERROR;

    if (send(sock, frame, frame_len, 0) < frame_len) {
        if (err_out && err_len > 0) snprintf(err_out, err_len, "send() failed");
        close(sock);
        return MBTCP_COMM_ERROR;
    }

    uint8_t buf[64];
    int32_t got = recv(sock, buf, sizeof(buf), 0);
    close(sock);
    if (got <= 0) {
        return 0;
    }
    if (err_out && err_len > 0) {
        snprintf(err_out, err_len, "unexpected response (%d bytes)", got);
    }
    return MBTCP_COMM_ERROR;
}

typedef struct {
    const char* host;
    int32_t port;
    int32_t start_reg;
    uint16_t expected_value;
    int32_t thread_index;
    int32_t iterations;
    int32_t timeout_ms;
} raw_client_ctx_t;

void* raw_client_worker(void* arg) {
    raw_client_ctx_t* ctx = (raw_client_ctx_t*)arg;
    uint16_t value = 0;
    char err[256];
    int32_t i = 0;

    for (i = 0; i < ctx->iterations; i++) {
        uint8_t tx = (uint8_t) ((ctx->thread_index + i + 1) & 0xFF);
        if (raw_read_register_once(ctx->host, ctx->port, (uint16_t)ctx->start_reg, tx, ctx->timeout_ms, &value, err, sizeof(err)) != 0) {
            return (void*)1;
        }
        if (value != ctx->expected_value) {
            return (void*)1;
        }
    }

    return 0;
}

/* -------------------------------------------------------------------------
 / FreeBASIC runtime bridge
 / ------------------------------------------------------------------------- */

extern void mbtcp_runtime_init(void);
extern void mbtcp_runtime_shutdown(void);

/* -------------------------------------------------------------------------
 / Client helper with retry loop
 / ------------------------------------------------------------------------- */

int32_t connect_with_retry( const char* host, char* err_out, int32_t err_len, int32_t timeout_ms ) {
    time_t start = time(0);

    while (1) {
        mbtcp_disconnect();
        mbtcp_connect(host);

        mbtcp_get_last_error(err_out, err_len);
        if (err_out[0] == 0) {
            return 1;
        }

        if ( (int32_t)(difftime(time(0), start) * 1000.0) >= timeout_ms ) {
            return 0;
        }

        usleep(50000);
    }
}

/* -------------------------------------------------------------------------
 / Main Entry Point
 / ------------------------------------------------------------------------- */

int main(int argc, char* argv[]) {
    int32_t exit_code = 1;
    char last_err[256];

    config_init_from_env(&g_cfg);
    config_apply_args(argc, argv, &g_cfg);

    printf("========================================\n");
    printf(" Modbus TCP C Validation Harness\n");
    printf("========================================\n\n");
    printf("Config: host=%s port=%d connect_timeout_ms=%d socket_timeout_ms=%d farm=%d raw_workers=%d raw_iterations=%d\n",
           g_cfg.host,
           g_cfg.port,
           g_cfg.connect_timeout_ms,
           g_cfg.socket_timeout_ms,
           g_cfg.farm_connections,
           g_cfg.raw_client_threads,
           g_cfg.raw_client_iterations);
    printf("\n");

    mbtcp_runtime_init();
    g_runtime_started = 1;

    // Initialize and start server
    mbse_init();
    if (mbse_start_server(g_cfg.port) == 0) {
        test_result("Server Start", 0, "Could not start MBSE server");
        goto cleanup;
    }
    char serverStartMsg[64];
    snprintf(serverStartMsg, sizeof(serverStartMsg), "Listening on port %d", g_cfg.port);
    test_result("Server Start", 1, serverStartMsg);

    // Initialize client
    mbtcp_init();
    mbtcp_set_port(g_cfg.port);
    mbtcp_set_timeout(g_cfg.socket_timeout_ms);

    if (connect_with_retry(g_cfg.host, last_err, sizeof(last_err), g_cfg.connect_timeout_ms)) {
    char status[256];
        snprintf(status, sizeof(status), "Connected to %.127s:%d", g_cfg.host, g_cfg.port);
        test_result("Client Connect", 1, status);
    } else {
        test_result("Client Connect", 0, last_err);
        goto cleanup;
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
    for (int i = 0; i < g_cfg.farm_connections; i++) {
        if (!connect_with_retry(g_cfg.host, last_err, sizeof(last_err), g_cfg.connect_timeout_ms)) {
            farm_ok = 0;
            break;
        }

        if (mbtcp_retrieve_register(100) != 0x1234) {
            farm_ok = 0;
            break;
        }

        mbtcp_disconnect();
    }
    test_result("Farm Test", farm_ok, (farm_ok ? "64 connections handled" : "Failed"));

    printf("\nTest #5: Raw transport - malformed MBAP protocol ID\n");
    {
        uint8_t bad_proto_frame[12] = {0, 1, 0, 1, 0, 6, 255, 3, 0, 0, 0, 1};
        int32_t no_reply = raw_send_and_expect_no_reply(
            g_cfg.host,
            g_cfg.port,
            bad_proto_frame,
            sizeof(bad_proto_frame),
            g_cfg.raw_client_timeout_ms,
            last_err,
            sizeof(last_err)
        );
        test_result("Raw transport rejects invalid protocol ID", (no_reply == 0), last_err);
    }

    printf("\nTest #6: Raw transport - truncated MBAP frame\n");
    {
        uint8_t truncated[6] = {0, 1, 0, 0, 0, 6};
        int32_t no_reply = raw_send_and_expect_no_reply(
            g_cfg.host,
            g_cfg.port,
            truncated,
            sizeof(truncated),
            g_cfg.raw_client_timeout_ms,
            last_err,
            sizeof(last_err)
        );
        test_result("Raw transport ignores truncated frame", (no_reply == 0), last_err);
    }

    printf("\nTest #7: Concurrent raw clients\n");
    {
        int32_t threads_ok = 1;
        int32_t i = 0;
        raw_client_ctx_t* contexts = malloc(sizeof(raw_client_ctx_t) * g_cfg.raw_client_threads);
        if (contexts == 0) {
            test_result("Concurrent raw clients", 0, "malloc(contexts) failed");
            threads_ok = 0;
        } else {
            pthread_t* workers = malloc(sizeof(pthread_t) * g_cfg.raw_client_threads);
            if (workers == 0) {
                free(contexts);
                test_result("Concurrent raw clients", 0, "malloc(workers) failed");
                threads_ok = 0;
            } else {
                for (i = 0; i < g_cfg.raw_client_threads; i++) {
                    contexts[i].host = g_cfg.host;
                    contexts[i].port = g_cfg.port;
                    contexts[i].start_reg = 100;
                    contexts[i].expected_value = 0x1234;
                    contexts[i].thread_index = i;
                    contexts[i].iterations = g_cfg.raw_client_iterations;
                    contexts[i].timeout_ms = g_cfg.raw_client_timeout_ms;

                    if (pthread_create(&workers[i], 0, raw_client_worker, &contexts[i]) != 0) {
                        if (g_cfg.raw_client_threads > 0) {
                            printf("pthread_create failed at %d\n", i);
                        }
                        threads_ok = 0;
                        break;
                    }
                }

                for (int32_t t = 0; t < g_cfg.raw_client_threads; t++) {
                    void* r = 0;
                    pthread_join(workers[t], &r);
                    if (r != 0) threads_ok = 0;
                }

                free(workers);
                free(contexts);
            }
        }
        test_result("Concurrent raw clients", threads_ok, "parallel readback");
    }

    printf("\n========================================\n");
    printf(" Validation Complete\n");
    printf("----------------------------------------\n");
    printf(" PASS: %d\n", g_pass);
    printf(" FAIL: %d\n", g_fail);
    printf("========================================\n");

cleanup:
    mbtcp_disconnect();
    mbse_stop_server();
    mbse_shutdown();
    if (g_runtime_started) {
        g_runtime_started = 0;
        mbtcp_runtime_shutdown();
    }

    exit_code = (g_fail > 0);
    return exit_code;
}

/* end of validation_c.c */
