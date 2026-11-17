#include "SwiftUIWebBrowserIO.h"
#include <stdlib.h>
#include <time.h>
#if defined(__wasm__)
/* Embedded Swift Concurrency ABI hooks, kept private to this file so Swift never
 * sees them as mutable globals. SwiftUIWebBrowser installs the browser event-loop
 * executor through the browser_io_install_* functions below. */
#define SWUI_EXPORT_FROM(LIBRARY) __attribute__((visibility("default")))
SWUI_EXPORT_FROM(swift_Concurrency) extern void *swift_task_enqueueGlobal_hook;
SWUI_EXPORT_FROM(swift_Concurrency) extern void *swift_task_enqueueGlobalWithDelay_hook;
SWUI_EXPORT_FROM(swift_Concurrency) extern void *swift_task_enqueueMainExecutor_hook;
SWUI_EXPORT_FROM(swift_Concurrency) extern void *swift_task_getMainExecutor_hook;
SWUI_EXPORT_FROM(swift_Concurrency) extern void *swift_task_checkIsolated_hook;
SWUI_EXPORT_FROM(swift_Concurrency) extern void *swift_task_isIsolatingCurrentContext_hook;
SWUI_EXPORT_FROM(swift_Concurrency) extern void *swift_task_isOnExecutor_hook;
SWUI_EXPORT_FROM(swift_Concurrency) extern void *swift_task_isMainExecutor_hook;
#endif
#if defined(__wasm__)
/* The C++ runtime's pure-virtual trap. libswift_Concurrency.a (TaskGroup.cpp) references it, and wasi-libc does not
 * provide it; a pure virtual call is a bug in the runtime, so trapping is the behaviour. */
void __cxa_pure_virtual(void) { __builtin_trap(); }
#endif
#if defined(__wasm__)
#define IMPORT(name) __attribute__((import_module("browser_io"), import_name(name)))
#define EXPORT(name) __attribute__((export_name(name), visibility("default")))
IMPORT("request") extern int32_t host_request(uint32_t, uint32_t, const uint8_t *, uint32_t);
IMPORT("cancel") extern void host_cancel(uint32_t);
IMPORT("sync") extern uint32_t host_sync(uint32_t, const uint8_t *, uint32_t);
IMPORT("length") extern uint32_t host_length(uint32_t);
IMPORT("copy") extern int32_t host_copy(uint32_t, uint8_t *, uint32_t);
IMPORT("release") extern void host_release(uint32_t);
IMPORT("wake") extern void host_wake(void);
IMPORT("stack_headroom") extern void host_stack_headroom(uint32_t);
IMPORT("binary_atoms") extern uint32_t host_binary_atoms(uint8_t *, uint32_t);
#else
#define EXPORT(name)
static int32_t host_request(uint32_t id,uint32_t op,const uint8_t *p,uint32_t n) {(void)id;(void)op;(void)p;(void)n;return -7;}
static void host_cancel(uint32_t id) {(void)id;}
static uint32_t host_sync(uint32_t op,const uint8_t *p,uint32_t n) {(void)op;(void)p;(void)n;return 0;}
static uint32_t host_length(uint32_t h) {(void)h;return 0;}
static int32_t host_copy(uint32_t h,uint8_t *p,uint32_t n) {(void)h;(void)p;(void)n;return -7;}
static void host_release(uint32_t h) {(void)h;}
static void host_wake(void) {}
static void host_stack_headroom(uint32_t depth) {(void)depth;}
static uint32_t host_binary_atoms(uint8_t *p,uint32_t n) {(void)p;(void)n;return 0;}
#endif
static browser_io_callback callback = NULL;
void browser_io_install_concurrency_hooks(void *global, void *global_with_delay, void *main_executor) {
#if defined(__wasm__)
    swift_task_enqueueGlobal_hook = global;
    swift_task_enqueueGlobalWithDelay_hook = global_with_delay;
    swift_task_enqueueMainExecutor_hook = main_executor;
#else
    (void)global; (void)global_with_delay; (void)main_executor;
#endif
}
void browser_io_install_main_executor_getter(void *getter, void *check_isolated, void *is_isolating, void *is_on_executor, void *is_main_executor) {
#if defined(__wasm__)
    swift_task_getMainExecutor_hook = getter;
    swift_task_checkIsolated_hook = check_isolated;
    swift_task_isIsolatingCurrentContext_hook = is_isolating;
    swift_task_isOnExecutor_hook = is_on_executor;
    swift_task_isMainExecutor_hook = is_main_executor;
#else
    (void)getter; (void)check_isolated; (void)is_isolating; (void)is_on_executor; (void)is_main_executor;
#endif
}
void browser_io_set_callback(browser_io_callback value) {callback=value;}
int32_t browser_io_request(uint32_t id,uint32_t op,const uint8_t *p,uint32_t n) {return host_request(id,op,p,n);}
void browser_io_cancel_request(uint32_t id) {host_cancel(id);}
void browser_io_free(void *pointer) {free(pointer);}
uint32_t browser_io_sync_request(uint32_t op,const uint8_t *p,uint32_t n) {return host_sync(op,p,n);}
uint32_t browser_io_result_length(uint32_t h) {return host_length(h);}
int32_t browser_io_result_copy(uint32_t h,uint8_t *p,uint32_t n) {return host_copy(h,p,n);}
void browser_io_result_release(uint32_t h) {host_release(h);}
void browser_io_wake_executor(void) {host_wake();}
void browser_io_stack_headroom(uint32_t depth) {host_stack_headroom(depth);}
uint32_t browser_io_binary_atoms(uint8_t *p,uint32_t n) {return host_binary_atoms(p,n);}
/* WASI environment entries the host supplied at instantiation (the browser
 * runtime reads `<meta name="runtime-environment">` and passes them). */
const char *browser_io_environment_value(const char *key) {
    return key ? getenv(key) : NULL;
}
double browser_io_wall_time_seconds(void) {
    struct timespec value;
    if (clock_gettime(CLOCK_REALTIME, &value) != 0) return 0.0;
    return (double)value.tv_sec + (double)value.tv_nsec / 1000000000.0;
}
uint64_t browser_io_monotonic_nanoseconds(void) {
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) return 0;
    return (uint64_t)value.tv_sec * 1000000000ull + (uint64_t)value.tv_nsec;
}
EXPORT("browser_io_alloc") void *browser_io_alloc(uint32_t length) {
    if (length > 67108864u) return NULL;
    return malloc(length ? length : 1u);
}
/* Ownership of bytes is transferred by the JS host and released after callback. */
EXPORT("browser_io_deliver") void browser_io_deliver(uint32_t id,int32_t status,uint8_t *bytes,uint32_t length) {
    if (length <= 67108864u && (bytes || !length)) {
#if defined(__wasm__)
        // A direct cdecl export avoids retaining a Swift closure pointer in
        // the Embedded WASM ABI. Native builds continue using the callback.
        browser_io_receive(id, status, bytes, length);
#elif !defined(__wasm__)
        if (callback) callback(id,status,bytes,length);
#endif
    }
    free(bytes);
}
