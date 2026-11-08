#ifndef NOVA_RT_H
#define NOVA_RT_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <pthread.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// NOVA MINIMAL RUNTIME (nova-rt)
// Region-Based Arena Allocation + Safe Concurrency Channel Support
// ============================================================================

typedef struct NovaArena {
    uint8_t *buffer;
    size_t capacity;
    size_t offset;
    struct NovaArena *next;
} NovaArena;

// Concurrency: Thread-safe Bounded Channel (iso message passing)
typedef struct NovaChannel {
    void **buffer;
    size_t capacity;
    size_t count;
    size_t head;
    size_t tail;
    bool closed;
    pthread_mutex_t mutex;
    pthread_cond_t not_empty;
    pthread_cond_t not_full;
} NovaChannel;

// Runtime Initialization and Teardown
void nova_rt_init(void);
void nova_rt_shutdown(void);

// Region Arena Management
NovaArena *nova_arena_create(size_t capacity);
void *nova_arena_alloc(NovaArena *arena, size_t size, size_t align);
void nova_arena_reset(NovaArena *arena);
void nova_arena_destroy(NovaArena *arena);

// Concurrency Primitives
NovaChannel *nova_channel_create(size_t capacity);
void nova_channel_send(NovaChannel *chan, void *item);
void *nova_channel_recv(NovaChannel *chan);
void nova_channel_close(NovaChannel *chan);
void nova_channel_destroy(NovaChannel *chan);
pthread_t nova_spawn(void *(*func)(void *), void *arg);
void nova_join(pthread_t thread);

// Builtin Console Output
void nova_print_str(const char *str);
void nova_print_int(int64_t val);
void nova_print_float(double val);
void nova_print_bool(bool val);
void nova_print_newline(void);

// Terminal & Game Runtime Helpers
void nova_sleep_ms(int64_t ms);
void nova_clear_screen(void);
void nova_hide_cursor(void);
void nova_show_cursor(void);
int64_t nova_random_int(int64_t min, int64_t max);

// Low-level POSIX Socket Networking
int64_t nova_tcp_listen(int64_t port);
int64_t nova_tcp_accept(int64_t server_fd);
int64_t nova_tcp_send_response(int64_t client_fd, const char *status_code, const char *body);
void nova_tcp_close(int64_t fd);

// Hardware-level Atomic Operations (std/sync)
int64_t nova_atomic_load(int64_t *ptr);
void nova_atomic_store(int64_t *ptr, int64_t val);
int64_t nova_atomic_add(int64_t *ptr, int64_t delta);
int64_t nova_atomic_sub(int64_t *ptr, int64_t delta);
bool nova_atomic_cas(int64_t *ptr, int64_t expected, int64_t desired);

// Mutex Synchronization
pthread_mutex_t *nova_mutex_create(void);
void nova_mutex_lock(pthread_mutex_t *mutex);
void nova_mutex_unlock(pthread_mutex_t *mutex);
void nova_mutex_destroy(pthread_mutex_t *mutex);

// High-Performance Filesystem Operations (std/fs)
const char *nova_fs_read_to_string(const char *path);
bool nova_fs_write_string(const char *path, const char *content);
bool nova_fs_exists(const char *path);
int64_t nova_fs_file_size(const char *path);
bool nova_fs_remove(const char *path);
bool nova_fs_mkdir_p(const char *path);
const char *nova_fs_sha256(const char *path);

// OS & Process Operations (std/os)
void nova_set_args(int argc, char **argv);
int64_t nova_os_args_count(void);
const char *nova_os_args_get(int64_t idx);
int64_t nova_process_run(const char *cmd);
const char *nova_os_getenv(const char *name);

// String Utilities (std/string)
bool nova_str_eq(const char *a, const char *b);
const char *nova_str_concat(const char *a, const char *b);
const char *nova_str_concat3(const char *a, const char *b, const char *c);

// High-Precision Time Operations (std/time)
int64_t nova_time_now_ms(void);
int64_t nova_time_now_ns(void);
void nova_time_sleep_ms(int64_t ms);

// Mathematical Operations (std/math)
int64_t nova_math_abs(int64_t x);
int64_t nova_math_min(int64_t a, int64_t b);
int64_t nova_math_max(int64_t a, int64_t b);
int64_t nova_math_clamp(int64_t v, int64_t low, int64_t high);
int64_t nova_math_sqrt(int64_t x);
int64_t nova_math_pow(int64_t base, int64_t exp);
int64_t nova_math_gcd(int64_t a, int64_t b);
int64_t nova_math_lcm(int64_t a, int64_t b);

// Cryptographic Operations (std/crypto)
const char *nova_crypto_sha256(const char *input);
const char *nova_crypto_sha256_file(const char *path);
bool nova_crypto_verify_hash(const char *data, const char *expected_hash);

// ============================================================================
// UNIVERSAL C ABI & FFI RUNTIME PRIMITIVES
// ============================================================================
int64_t nova_c_sizeof_int(void);
int64_t nova_c_sizeof_pointer(void);
int64_t nova_c_sizeof_double(void);
int64_t nova_ffi_dlopen(const char *path);
int64_t nova_ffi_dlsym(int64_t handle, const char *symbol);
bool nova_ffi_dlclose(int64_t handle);
int64_t nova_c_malloc(int64_t bytes);
bool nova_c_free(int64_t ptr);
bool nova_c_memcpy(int64_t dest, int64_t src, int64_t bytes);
bool nova_c_memset(int64_t dest, int64_t val, int64_t bytes);

// ============================================================================
// SUPER-RUNTIME: PERCEUS V2 SLAB ALLOCATOR & PAGE MANAGEMENT
// ============================================================================
void *nova_slab_alloc(size_t size);
void nova_slab_free(void *ptr, size_t size);
void *nova_page_alloc(size_t bytes);
void nova_page_free(void *ptr, size_t bytes);

// ============================================================================
// SUPER-RUNTIME: WORK-STEALING CONCURRENCY & MULTI-CORE SCHEDULER
// ============================================================================
int64_t nova_num_cores(void);
void nova_task_pool_init(int64_t num_workers);
void nova_task_spawn(void (*task_func)(void *), void *arg);
void nova_task_yield(void);
void nova_task_wait_all(void);

// ============================================================================
// SUPER-RUNTIME: VECTOR ACCELERATION & FAST HASHING (xxHash64 & SIMD)
// ============================================================================
double nova_simd_dot_product(const double *a, const double *b, int64_t n);
uint64_t nova_fast_hash64(const void *data, size_t len);

// ============================================================================
// SUPER-RUNTIME: NATIVE DESKTOP GUI WINDOWING (std/gui)
// ============================================================================
int64_t nova_gui_window_create(const char *title, int64_t width, int64_t height);
bool nova_gui_window_poll(int64_t win_handle);
bool nova_gui_window_draw_rect(int64_t win_handle, int64_t x, int64_t y, int64_t w, int64_t h, int64_t color_rgba);
bool nova_gui_alert(const char *title, const char *message);
bool nova_gui_window_close(int64_t win_handle);

// Panic handler
void nova_panic(const char *msg, const char *file, int line);

#ifdef __cplusplus
}
#endif

#endif // NOVA_RT_H
