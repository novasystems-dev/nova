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

// Panic handler
void nova_panic(const char *msg, const char *file, int line);

#ifdef __cplusplus
}
#endif

#endif // NOVA_RT_H
