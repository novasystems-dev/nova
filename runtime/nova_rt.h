#ifndef NOVA_RT_H
#define NOVA_RT_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// NOVA MINIMAL RUNTIME (nova-rt)
// Region-Based Arena Allocation + Safe Reference Counting Support
// ============================================================================

typedef struct NovaArena {
    uint8_t *buffer;
    size_t capacity;
    size_t offset;
    struct NovaArena *next;
} NovaArena;

// Runtime Initialization and Teardown
void nova_rt_init(void);
void nova_rt_shutdown(void);

// Region Arena Management
NovaArena *nova_arena_create(size_t capacity);
void *nova_arena_alloc(NovaArena *arena, size_t size, size_t align);
void nova_arena_reset(NovaArena *arena);
void nova_arena_destroy(NovaArena *arena);

// Builtin Console Output
void nova_print_str(const char *str);
void nova_print_int(int64_t val);
void nova_print_float(double val);
void nova_print_bool(bool val);
void nova_print_newline(void);

// Panic handler
void nova_panic(const char *msg, const char *file, int line);

#ifdef __cplusplus
}
#endif

#endif // NOVA_RT_H
