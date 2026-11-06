#define _POSIX_C_SOURCE 200809L
#define _DEFAULT_SOURCE
#include "nova_rt.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/stat.h>
#include <sys/wait.h>

#define DEFAULT_ARENA_SIZE (1024 * 1024) // 1MB default region chunk

static int g_nova_argc = 0;
static char **g_nova_argv = NULL;

void nova_set_args(int argc, char **argv) {
    g_nova_argc = argc;
    g_nova_argv = argv;
}

void nova_rt_init(void) {
    // Runtime initialization hooks
}

void nova_rt_shutdown(void) {
    // Teardown
}

NovaArena *nova_arena_create(size_t capacity) {
    if (capacity == 0) {
        capacity = DEFAULT_ARENA_SIZE;
    }
    NovaArena *arena = (NovaArena *)malloc(sizeof(NovaArena));
    if (!arena) {
        nova_panic("Out of memory allocating NovaArena header", __FILE__, __LINE__);
    }
    arena->buffer = (uint8_t *)malloc(capacity);
    if (!arena->buffer) {
        free(arena);
        nova_panic("Out of memory allocating NovaArena buffer", __FILE__, __LINE__);
    }
    arena->capacity = capacity;
    arena->offset = 0;
    arena->next = NULL;
    return arena;
}

void *nova_arena_alloc(NovaArena *arena, size_t size, size_t align) {
    if (align == 0) align = sizeof(void *);
    
    size_t current = (size_t)(arena->buffer + arena->offset);
    size_t aligned = (current + (align - 1)) & ~(align - 1);
    size_t padding = aligned - current;

    if (arena->offset + padding + size > arena->capacity) {
        size_t next_cap = arena->capacity * 2;
        if (next_cap < size + padding) next_cap = size + padding + DEFAULT_ARENA_SIZE;
        NovaArena *next_chunk = nova_arena_create(next_cap);
        arena->next = next_chunk;
        return nova_arena_alloc(next_chunk, size, align);
    }

    arena->offset += padding;
    void *ptr = arena->buffer + arena->offset;
    arena->offset += size;
    return ptr;
}

void nova_arena_reset(NovaArena *arena) {
    while (arena) {
        arena->offset = 0;
        arena = arena->next;
    }
}

void nova_arena_destroy(NovaArena *arena) {
    while (arena) {
        NovaArena *next = arena->next;
        if (arena->buffer) free(arena->buffer);
        free(arena);
        arena = next;
    }
}

// ============================================================================
// CONCURRENCY CHANNELS & THREADS
// ============================================================================

NovaChannel *nova_channel_create(size_t capacity) {
    if (capacity == 0) capacity = 64;
    NovaChannel *chan = (NovaChannel *)malloc(sizeof(NovaChannel));
    if (!chan) nova_panic("Failed to allocate NovaChannel", __FILE__, __LINE__);
    
    chan->buffer = (void **)malloc(sizeof(void *) * capacity);
    if (!chan->buffer) nova_panic("Failed to allocate channel buffer", __FILE__, __LINE__);
    
    chan->capacity = capacity;
    chan->count = 0;
    chan->head = 0;
    chan->tail = 0;
    chan->closed = false;

    pthread_mutex_init(&chan->mutex, NULL);
    pthread_cond_init(&chan->not_empty, NULL);
    pthread_cond_init(&chan->not_full, NULL);
    return chan;
}

void nova_channel_send(NovaChannel *chan, void *item) {
    pthread_mutex_lock(&chan->mutex);
    if (chan->closed) {
        pthread_mutex_unlock(&chan->mutex);
        nova_panic("Attempted to send on closed channel", __FILE__, __LINE__);
    }

    while (chan->count == chan->capacity && !chan->closed) {
        pthread_cond_wait(&chan->not_full, &chan->mutex);
    }

    if (chan->closed) {
        pthread_mutex_unlock(&chan->mutex);
        nova_panic("Channel closed during send", __FILE__, __LINE__);
    }

    chan->buffer[chan->tail] = item;
    chan->tail = (chan->tail + 1) % chan->capacity;
    chan->count++;

    pthread_cond_signal(&chan->not_empty);
    pthread_mutex_unlock(&chan->mutex);
}

void *nova_channel_recv(NovaChannel *chan) {
    pthread_mutex_lock(&chan->mutex);

    while (chan->count == 0 && !chan->closed) {
        pthread_cond_wait(&chan->not_empty, &chan->mutex);
    }

    if (chan->count == 0 && chan->closed) {
        pthread_mutex_unlock(&chan->mutex);
        return NULL; // Closed and empty (Option::None)
    }

    void *item = chan->buffer[chan->head];
    chan->head = (chan->head + 1) % chan->capacity;
    chan->count--;

    pthread_cond_signal(&chan->not_full);
    pthread_mutex_unlock(&chan->mutex);
    return item;
}

void nova_channel_close(NovaChannel *chan) {
    pthread_mutex_lock(&chan->mutex);
    chan->closed = true;
    pthread_cond_broadcast(&chan->not_empty);
    pthread_cond_broadcast(&chan->not_full);
    pthread_mutex_unlock(&chan->mutex);
}

void nova_channel_destroy(NovaChannel *chan) {
    if (!chan) return;
    free(chan->buffer);
    pthread_mutex_destroy(&chan->mutex);
    pthread_cond_destroy(&chan->not_empty);
    pthread_cond_destroy(&chan->not_full);
    free(chan);
}

pthread_t nova_spawn(void *(*func)(void *), void *arg) {
    pthread_t thread;
    if (pthread_create(&thread, NULL, func, arg) != 0) {
        nova_panic("Failed to spawn OS thread", __FILE__, __LINE__);
    }
    return thread;
}

void nova_join(pthread_t thread) {
    pthread_join(thread, NULL);
}

// ============================================================================
// CONSOLE I/O & PANIC
// ============================================================================

void nova_print_str(const char *str) {
    fputs(str, stdout);
    fflush(stdout);
}

void nova_print_int(int64_t val) {
    printf("%ld", (long)val);
    fflush(stdout);
}

void nova_print_float(double val) {
    printf("%f", val);
    fflush(stdout);
}

void nova_print_bool(bool val) {
    fputs(val ? "true" : "false", stdout);
    fflush(stdout);
}

void nova_print_newline(void) {
    putchar('\n');
    fflush(stdout);
}

void nova_sleep_ms(int64_t ms) {
    if (ms > 0) {
        struct timespec ts;
        ts.tv_sec = (time_t)(ms / 1000);
        ts.tv_nsec = (long)((ms % 1000) * 1000000);
        nanosleep(&ts, NULL);
    }
}

void nova_clear_screen(void) {
    fputs("\033[2J\033[H", stdout);
    fflush(stdout);
}

void nova_hide_cursor(void) {
    fputs("\033[?25l", stdout);
    fflush(stdout);
}

void nova_show_cursor(void) {
    fputs("\033[?25h", stdout);
    fflush(stdout);
}

int64_t nova_random_int(int64_t min, int64_t max) {
    if (min >= max) return min;
    static bool seeded = false;
    if (!seeded) {
        srand((unsigned int)time(NULL));
        seeded = true;
    }
    return min + (rand() % (max - min + 1));
}

// Low-level POSIX Socket Networking
int64_t nova_tcp_listen(int64_t port) {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) return -1;
    
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons((uint16_t)port);
    
    if (bind(server_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(server_fd);
        return -2;
    }
    
    if (listen(server_fd, 128) < 0) {
        close(server_fd);
        return -3;
    }
    
    return (int64_t)server_fd;
}

int64_t nova_tcp_accept(int64_t server_fd) {
    struct sockaddr_in client_addr;
    socklen_t client_len = sizeof(client_addr);
    int client_fd = accept((int)server_fd, (struct sockaddr *)&client_addr, &client_len);
    return (int64_t)client_fd;
}

int64_t nova_tcp_send_response(int64_t client_fd, const char *status_code, const char *body) {
    if (client_fd < 0) return -1;
    char header[512];
    size_t body_len = body ? strlen(body) : 0;
    int header_len = snprintf(header, sizeof(header),
        "HTTP/1.1 %s\r\n"
        "Server: Nova-Native/0.1.0\r\n"
        "Content-Type: text/plain; charset=utf-8\r\n"
        "Content-Length: %zu\r\n"
        "Connection: close\r\n\r\n",
        status_code ? status_code : "200 OK",
        body_len);
    
    ssize_t w1 = write((int)client_fd, header, (size_t)header_len);
    ssize_t w2 = 0;
    if (body_len > 0) {
        w2 = write((int)client_fd, body, body_len);
    }
    close((int)client_fd);
    return (int64_t)(w1 + w2);
}

void nova_tcp_close(int64_t fd) {
    if (fd >= 0) {
        close((int)fd);
    }
}

void nova_panic(const char *msg, const char *file, int line) {
    fprintf(stderr, "\n[NOVA RUNTIME PANIC] %s at %s:%d\n", msg, file, line);
    exit(1);
}

// ============================================================================
// ATOMIC OPERATIONS (std/sync)
// ============================================================================

int64_t nova_atomic_load(int64_t *ptr) {
    return __atomic_load_n(ptr, __ATOMIC_SEQ_CST);
}

void nova_atomic_store(int64_t *ptr, int64_t val) {
    __atomic_store_n(ptr, val, __ATOMIC_SEQ_CST);
}

int64_t nova_atomic_add(int64_t *ptr, int64_t delta) {
    return __atomic_fetch_add(ptr, delta, __ATOMIC_SEQ_CST);
}

int64_t nova_atomic_sub(int64_t *ptr, int64_t delta) {
    return __atomic_fetch_sub(ptr, delta, __ATOMIC_SEQ_CST);
}

bool nova_atomic_cas(int64_t *ptr, int64_t expected, int64_t desired) {
    return __atomic_compare_exchange_n(ptr, &expected, desired, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
}

// ============================================================================
// MUTEX SYNCHRONIZATION
// ============================================================================

pthread_mutex_t *nova_mutex_create(void) {
    pthread_mutex_t *m = (pthread_mutex_t *)malloc(sizeof(pthread_mutex_t));
    if (m) pthread_mutex_init(m, NULL);
    return m;
}

void nova_mutex_lock(pthread_mutex_t *mutex) {
    if (mutex) pthread_mutex_lock(mutex);
}

void nova_mutex_unlock(pthread_mutex_t *mutex) {
    if (mutex) pthread_mutex_unlock(mutex);
}

void nova_mutex_destroy(pthread_mutex_t *mutex) {
    if (mutex) {
        pthread_mutex_destroy(mutex);
        free(mutex);
    }
}

// ============================================================================
// FILESYSTEM OPERATIONS (std/fs)
// ============================================================================

const char *nova_fs_read_to_string(const char *path) {
    if (!path) return "";
    FILE *f = fopen(path, "rb");
    if (!f) return "";
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (sz < 0) { fclose(f); return ""; }
    char *buf = (char *)malloc((size_t)sz + 1);
    if (!buf) { fclose(f); return ""; }
    size_t rd = fread(buf, 1, (size_t)sz, f);
    buf[rd] = '\0';
    fclose(f);
    return buf;
}

bool nova_fs_write_string(const char *path, const char *content) {
    if (!path) return false;
    FILE *f = fopen(path, "wb");
    if (!f) return false;
    if (content) {
        fputs(content, f);
    }
    fclose(f);
    return true;
}

bool nova_fs_exists(const char *path) {
    if (!path) return false;
    return access(path, F_OK) == 0;
}

int64_t nova_fs_file_size(const char *path) {
    if (!path) return -1;
    struct stat st;
    if (stat(path, &st) == 0) {
        return (int64_t)st.st_size;
    }
    return -1;
}

bool nova_fs_remove(const char *path) {
    if (!path) return false;
    return unlink(path) == 0;
}

bool nova_fs_mkdir_p(const char *path) {
    if (!path || strlen(path) == 0) return false;
    char tmp[1024];
    snprintf(tmp, sizeof(tmp), "mkdir -p \"%s\" 2>/dev/null", path);
    return system(tmp) == 0;
}

const char *nova_fs_sha256(const char *path) {
    if (!path) return "0000000000000000000000000000000000000000000000000000000000000000";
    char cmd[1024];
    snprintf(cmd, sizeof(cmd), "sha256sum \"%s\" 2>/dev/null | awk '{print $1}'", path);
    FILE *p = popen(cmd, "r");
    if (!p) return "0000000000000000000000000000000000000000000000000000000000000000";
    static char hash[65];
    if (fgets(hash, sizeof(hash), p)) {
        size_t len = strlen(hash);
        if (len > 0 && hash[len - 1] == '\n') hash[len - 1] = '\0';
        pclose(p);
        return strdup(hash);
    }
    pclose(p);
    return "0000000000000000000000000000000000000000000000000000000000000000";
}

// ============================================================================
// OS & PROCESS OPERATIONS (std/os)
// ============================================================================

int64_t nova_os_args_count(void) {
    return (int64_t)g_nova_argc;
}

const char *nova_os_args_get(int64_t idx) {
    if (idx >= 0 && idx < g_nova_argc && g_nova_argv) {
        return g_nova_argv[idx];
    }
    return "";
}

int64_t nova_process_run(const char *cmd) {
    if (!cmd) return -1;
    int res = system(cmd);
    return (int64_t)WEXITSTATUS(res);
}

const char *nova_os_getenv(const char *name) {
    if (!name) return "";
    const char *val = getenv(name);
    return val ? val : "";
}

// ============================================================================
// STRING UTILITIES (std/string)
// ============================================================================

bool nova_str_eq(const char *a, const char *b) {
    if (!a || !b) return a == b;
    return strcmp(a, b) == 0;
}

const char *nova_str_concat(const char *a, const char *b) {
    if (!a) a = "";
    if (!b) b = "";
    size_t la = strlen(a);
    size_t lb = strlen(b);
    char *res = (char *)malloc(la + lb + 1);
    if (!res) return "";
    memcpy(res, a, la);
    memcpy(res + la, b, lb);
    res[la + lb] = '\0';
    return res;
}

const char *nova_str_concat3(const char *a, const char *b, const char *c) {
    if (!a) a = "";
    if (!b) b = "";
    if (!c) c = "";
    size_t la = strlen(a);
    size_t lb = strlen(b);
    size_t lc = strlen(c);
    char *res = (char *)malloc(la + lb + lc + 1);
    if (!res) return "";
    memcpy(res, a, la);
    memcpy(res + la, b, lb);
    memcpy(res + la + lb, c, lc);
    res[la + lb + lc] = '\0';
    return res;
}
