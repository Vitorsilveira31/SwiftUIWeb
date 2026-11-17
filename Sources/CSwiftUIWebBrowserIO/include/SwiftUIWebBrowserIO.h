#ifndef SWIFTUIWEB_BROWSER_IO_H
#define SWIFTUIWEB_BROWSER_IO_H
#include <stdint.h>

#if defined(__wasm__)
void browser_io_receive(uint32_t, int32_t, const uint8_t *, uint32_t);
#endif
void browser_io_install_concurrency_hooks(void *global, void *global_with_delay, void *main_executor);
void browser_io_install_main_executor_getter(void *getter, void *check_isolated, void *is_isolating, void *is_on_executor, void *is_main_executor);
#ifdef __cplusplus
extern "C" {
#endif
typedef void (*browser_io_callback)(uint32_t, int32_t, const uint8_t *, uint32_t);
void browser_io_set_callback(browser_io_callback callback);
int32_t browser_io_request(uint32_t identifier, uint32_t operation, const uint8_t *bytes, uint32_t length);
void browser_io_cancel_request(uint32_t identifier);
void browser_io_free(void *pointer);
/* Asks the host to drain the Swift executor soon (queueMicrotask); a no-op off the browser. */
void browser_io_wake_executor(void);
/* Debug only: tells the host the render recursion depth so it can sample the call-stack headroom left. */
void browser_io_stack_headroom(uint32_t depth);
/* The atoms of the binary publication format, NUL-separated: written into `buffer` when `capacity` holds them; returns their
 * length. A release app.wasm reads them from the page instead of carrying them (SwiftUIWebHTML BinaryAtomTable). 0 off the
 * browser. */
uint32_t browser_io_binary_atoms(uint8_t *buffer, uint32_t capacity);
uint32_t browser_io_sync_request(uint32_t operation, const uint8_t *bytes, uint32_t length);
uint32_t browser_io_result_length(uint32_t handle);
int32_t browser_io_result_copy(uint32_t handle, uint8_t *destination, uint32_t capacity);
void browser_io_result_release(uint32_t handle);
void *browser_io_alloc(uint32_t length);
void browser_io_deliver(uint32_t identifier, int32_t status, uint8_t *bytes, uint32_t length);
double browser_io_wall_time_seconds(void);
uint64_t browser_io_monotonic_nanoseconds(void);
const char *browser_io_environment_value(const char *key);
#ifdef __cplusplus
}
#endif
#endif
