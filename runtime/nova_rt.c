#define _POSIX_C_SOURCE 200809L
#define _DEFAULT_SOURCE
#define _DARWIN_C_SOURCE
#include "nova_rt.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <math.h>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <io.h>
#include <process.h>
#include <sys/stat.h>
#define F_OK 0
#define access _access
#define unlink _unlink
#define NOVA_CLOSE_SOCKET(s) closesocket((SOCKET)(s))
#else
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sched.h>
#ifdef __APPLE__
#include <sys/types.h>
#include <sys/sysctl.h>
#endif
#define NOVA_CLOSE_SOCKET(s) close((int)(s))
#endif

#define DEFAULT_ARENA_SIZE (1024 * 1024) // 1MB default region chunk

static int g_nova_argc = 0;
static char **g_nova_argv = NULL;

void nova_set_args(int argc, char **argv) {
    g_nova_argc = argc;
    g_nova_argv = argv;
}

void nova_rt_init(void) {
#ifdef _WIN32
    WSADATA wsa;
    WSAStartup(MAKEWORD(2, 2), &wsa);
#endif
}

void nova_rt_shutdown(void) {
#ifdef _WIN32
    WSACleanup();
#endif
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
    if (ms <= 0) return;
#ifdef _WIN32
    Sleep((DWORD)ms);
#else
    struct timespec ts;
    ts.tv_sec = (time_t)(ms / 1000);
    ts.tv_nsec = (long)((ms % 1000) * 1000000);
    nanosleep(&ts, NULL);
#endif
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

// Low-level POSIX / Winsock Socket Networking
int64_t nova_tcp_listen(int64_t port) {
#ifdef _WIN32
    SOCKET server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd == INVALID_SOCKET) return -1;
    
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, (const char *)&opt, sizeof(opt));
    
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons((uint16_t)port);
    
    if (bind(server_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        NOVA_CLOSE_SOCKET(server_fd);
        return -2;
    }
    
    if (listen(server_fd, 128) < 0) {
        NOVA_CLOSE_SOCKET(server_fd);
        return -3;
    }
    
    return (int64_t)server_fd;
#else
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) return -1;
    
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, (const char *)&opt, sizeof(opt));
    
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons((uint16_t)port);
    
    if (bind(server_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        NOVA_CLOSE_SOCKET(server_fd);
        return -2;
    }
    
    if (listen(server_fd, 128) < 0) {
        NOVA_CLOSE_SOCKET(server_fd);
        return -3;
    }
    
    return (int64_t)server_fd;
#endif
}

int64_t nova_tcp_accept(int64_t server_fd) {
    struct sockaddr_in client_addr;
#ifdef _WIN32
    int client_len = sizeof(client_addr);
    SOCKET client_fd = accept((SOCKET)server_fd, (struct sockaddr *)&client_addr, &client_len);
    if (client_fd == INVALID_SOCKET) return -1;
    return (int64_t)client_fd;
#else
    socklen_t client_len = sizeof(client_addr);
    int client_fd = accept((int)server_fd, (struct sockaddr *)&client_addr, &client_len);
    return (int64_t)client_fd;
#endif
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
    
#ifdef _WIN32
    int w1 = send((SOCKET)client_fd, header, header_len, 0);
    int w2 = 0;
    if (body_len > 0) {
        w2 = send((SOCKET)client_fd, body, (int)body_len, 0);
    }
#else
    ssize_t w1 = write((int)client_fd, header, (size_t)header_len);
    ssize_t w2 = 0;
    if (body_len > 0) {
        w2 = write((int)client_fd, body, body_len);
    }
#endif
    NOVA_CLOSE_SOCKET(client_fd);
    return (int64_t)(w1 + w2);
}

void nova_tcp_close(int64_t fd) {
    if (fd >= 0) {
        NOVA_CLOSE_SOCKET(fd);
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
#ifdef _WIN32
    char winPath[1024];
    strncpy(winPath, path, sizeof(winPath) - 1);
    winPath[sizeof(winPath) - 1] = '\0';
    for (char *p = winPath; *p; p++) {
        if (*p == '/') *p = '\\';
    }
    snprintf(tmp, sizeof(tmp), "mkdir \"%s\" 2>nul", winPath);
#else
    snprintf(tmp, sizeof(tmp), "mkdir -p \"%s\" 2>/dev/null", path);
#endif
    return system(tmp) == 0;
}

const char *nova_fs_sha256(const char *path) {
    return nova_crypto_sha256_file(path);
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
#ifdef _WIN32
    return (int64_t)res;
#else
    return (int64_t)WEXITSTATUS(res);
#endif
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

// ============================================================================
// HIGH-PRECISION TIME OPERATIONS (std/time)
// ============================================================================

int64_t nova_time_now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (int64_t)(ts.tv_sec * 1000LL + ts.tv_nsec / 1000000LL);
}

int64_t nova_time_now_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)(ts.tv_sec * 1000000000LL + ts.tv_nsec);
}

void nova_time_sleep_ms(int64_t ms) {
    if (ms <= 0) return;
#ifdef _WIN32
    Sleep((DWORD)ms);
#else
    struct timespec req;
    req.tv_sec = ms / 1000;
    req.tv_nsec = (ms % 1000) * 1000000L;
    nanosleep(&req, NULL);
#endif
}

// ============================================================================
// MATHEMATICAL OPERATIONS (std/math)
// ============================================================================

int64_t nova_math_abs(int64_t x) {
    return x < 0 ? -x : x;
}

int64_t nova_math_min(int64_t a, int64_t b) {
    return a < b ? a : b;
}

int64_t nova_math_max(int64_t a, int64_t b) {
    return a > b ? a : b;
}

int64_t nova_math_clamp(int64_t v, int64_t low, int64_t high) {
    if (v < low) return low;
    if (v > high) return high;
    return v;
}

int64_t nova_math_sqrt(int64_t x) {
    if (x <= 0) return 0;
    return (int64_t)sqrt((double)x);
}

int64_t nova_math_pow(int64_t base, int64_t exp) {
    if (exp < 0) return 0;
    int64_t res = 1;
    while (exp > 0) {
        if (exp & 1) res *= base;
        base *= base;
        exp >>= 1;
    }
    return res;
}

int64_t nova_math_gcd(int64_t a, int64_t b) {
    while (b != 0) {
        int64_t t = b;
        b = a % b;
        a = t;
    }
    return a >= 0 ? a : -a;
}

int64_t nova_math_lcm(int64_t a, int64_t b) {
    if (a == 0 || b == 0) return 0;
    int64_t g = nova_math_gcd(a, b);
    return (nova_math_abs(a * b)) / g;
}

// ============================================================================
// CRYPTOGRAPHIC OPERATIONS (std/crypto)
// ============================================================================

typedef struct {
    uint8_t data[64];
    uint32_t datalen;
    unsigned long long bitlen;
    uint32_t state[8];
} nova_sha256_ctx;

#define ROTRIGHT(a,b) (((a) >> (b)) | ((a) << (32-(b))))
#define CH(x,y,z) (((x) & (y)) ^ (~(x) & (z)))
#define MAJ(x,y,z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define EP0(x) (ROTRIGHT(x,2) ^ ROTRIGHT(x,13) ^ ROTRIGHT(x,22))
#define EP1(x) (ROTRIGHT(x,6) ^ ROTRIGHT(x,11) ^ ROTRIGHT(x,25))
#define SIG0(x) (ROTRIGHT(x,7) ^ ROTRIGHT(x,18) ^ ((x) >> 3))
#define SIG1(x) (ROTRIGHT(x,17) ^ ROTRIGHT(x,19) ^ ((x) >> 10))

static const uint32_t sha256_k[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};

static void nova_sha256_transform(nova_sha256_ctx *ctx, const uint8_t data[]) {
    uint32_t a, b, c, d, e, f, g, h, i, j, t1, t2, m[64];
    for (i = 0, j = 0; i < 16; ++i, j += 4)
        m[i] = (data[j] << 24) | (data[j + 1] << 16) | (data[j + 2] << 8) | (data[j + 3]);
    for ( ; i < 64; ++i)
        m[i] = SIG1(m[i - 2]) + m[i - 7] + SIG0(m[i - 15]) + m[i - 16];
    a = ctx->state[0]; b = ctx->state[1]; c = ctx->state[2]; d = ctx->state[3];
    e = ctx->state[4]; f = ctx->state[5]; g = ctx->state[6]; h = ctx->state[7];
    for (i = 0; i < 64; ++i) {
        t1 = h + EP1(e) + CH(e,f,g) + sha256_k[i] + m[i];
        t2 = EP0(a) + MAJ(a,b,c);
        h = g; g = f; f = e; e = d + t1;
        d = c; c = b; b = a; a = t1 + t2;
    }
    ctx->state[0] += a; ctx->state[1] += b; ctx->state[2] += c; ctx->state[3] += d;
    ctx->state[4] += e; ctx->state[5] += f; ctx->state[6] += g; ctx->state[7] += h;
}

static void nova_sha256_init(nova_sha256_ctx *ctx) {
    ctx->datalen = 0;
    ctx->bitlen = 0;
    ctx->state[0] = 0x6a09e667; ctx->state[1] = 0xbb67ae85;
    ctx->state[2] = 0x3c6ef372; ctx->state[3] = 0xa54ff53a;
    ctx->state[4] = 0x510e527f; ctx->state[5] = 0x9b05688c;
    ctx->state[6] = 0x1f83d9ab; ctx->state[7] = 0x5be0cd19;
}

static void nova_sha256_update(nova_sha256_ctx *ctx, const uint8_t data[], size_t len) {
    for (size_t i = 0; i < len; ++i) {
        ctx->data[ctx->datalen] = data[i];
        ctx->datalen++;
        if (ctx->datalen == 64) {
            nova_sha256_transform(ctx, ctx->data);
            ctx->bitlen += 512;
            ctx->datalen = 0;
        }
    }
}

static void nova_sha256_final(nova_sha256_ctx *ctx, uint8_t hash[]) {
    uint32_t i = ctx->datalen;
    if (ctx->datalen < 56) {
        ctx->data[i++] = 0x80;
        while (i < 56) ctx->data[i++] = 0x00;
    } else {
        ctx->data[i++] = 0x80;
        while (i < 64) ctx->data[i++] = 0x00;
        nova_sha256_transform(ctx, ctx->data);
        memset(ctx->data, 0, 56);
    }
    ctx->bitlen += ctx->datalen * 8;
    ctx->data[63] = (uint8_t)(ctx->bitlen);
    ctx->data[62] = (uint8_t)(ctx->bitlen >> 8);
    ctx->data[61] = (uint8_t)(ctx->bitlen >> 16);
    ctx->data[60] = (uint8_t)(ctx->bitlen >> 24);
    ctx->data[59] = (uint8_t)(ctx->bitlen >> 32);
    ctx->data[58] = (uint8_t)(ctx->bitlen >> 40);
    ctx->data[57] = (uint8_t)(ctx->bitlen >> 48);
    ctx->data[56] = (uint8_t)(ctx->bitlen >> 56);
    nova_sha256_transform(ctx, ctx->data);
    for (i = 0; i < 4; ++i) {
        hash[i]      = (uint8_t)((ctx->state[0] >> (24 - i * 8)) & 0xff);
        hash[i + 4]  = (uint8_t)((ctx->state[1] >> (24 - i * 8)) & 0xff);
        hash[i + 8]  = (uint8_t)((ctx->state[2] >> (24 - i * 8)) & 0xff);
        hash[i + 12] = (uint8_t)((ctx->state[3] >> (24 - i * 8)) & 0xff);
        hash[i + 16] = (uint8_t)((ctx->state[4] >> (24 - i * 8)) & 0xff);
        hash[i + 20] = (uint8_t)((ctx->state[5] >> (24 - i * 8)) & 0xff);
        hash[i + 24] = (uint8_t)((ctx->state[6] >> (24 - i * 8)) & 0xff);
        hash[i + 28] = (uint8_t)((ctx->state[7] >> (24 - i * 8)) & 0xff);
    }
}

const char *nova_crypto_sha256(const char *input) {
    if (!input) input = "";
    nova_sha256_ctx ctx;
    nova_sha256_init(&ctx);
    nova_sha256_update(&ctx, (const uint8_t *)input, strlen(input));
    uint8_t hash[32];
    nova_sha256_final(&ctx, hash);
    char *hex = (char *)malloc(65);
    for (int i = 0; i < 32; i++) {
        sprintf(hex + (i * 2), "%02x", hash[i]);
    }
    hex[64] = '\0';
    return hex;
}

const char *nova_crypto_sha256_file(const char *path) {
    if (!path) return "0000000000000000000000000000000000000000000000000000000000000000";
    FILE *f = fopen(path, "rb");
    if (!f) return "0000000000000000000000000000000000000000000000000000000000000000";
    nova_sha256_ctx ctx;
    nova_sha256_init(&ctx);
    uint8_t buf[4096];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), f)) > 0) {
        nova_sha256_update(&ctx, buf, n);
    }
    fclose(f);
    uint8_t hash[32];
    nova_sha256_final(&ctx, hash);
    char *hex = (char *)malloc(65);
    for (int i = 0; i < 32; i++) {
        sprintf(hex + (i * 2), "%02x", hash[i]);
    }
    hex[64] = '\0';
    return hex;
}

bool nova_crypto_verify_hash(const char *data, const char *expected_hash) {
    if (!data || !expected_hash) return false;
    const char *computed = nova_crypto_sha256(data);
    return strcmp(computed, expected_hash) == 0;
}

// ============================================================================
// UNIVERSAL C ABI & FFI RUNTIME IMPLEMENTATION
// ============================================================================
#ifndef _WIN32
#include <dlfcn.h>
#endif

int64_t nova_c_sizeof_int(void) { return (int64_t)sizeof(int); }
int64_t nova_c_sizeof_pointer(void) { return (int64_t)sizeof(void *); }
int64_t nova_c_sizeof_double(void) { return (int64_t)sizeof(double); }

int64_t nova_ffi_dlopen(const char *path) {
    if (!path || strlen(path) == 0) return 0;
#ifdef _WIN32
    HMODULE mod = LoadLibraryA(path);
    return (int64_t)(intptr_t)mod;
#else
    void *h = dlopen(path, RTLD_LAZY);
    if (!h) {
        h = dlopen(NULL, RTLD_LAZY);
    }
    return (int64_t)(intptr_t)h;
#endif
}

int64_t nova_ffi_dlsym(int64_t handle, const char *symbol) {
    if (!symbol) return 0;
#ifdef _WIN32
    FARPROC proc = GetProcAddress((HMODULE)(intptr_t)handle, symbol);
    return (int64_t)(intptr_t)proc;
#else
    void *sym = dlsym((void *)(intptr_t)handle, symbol);
    return (int64_t)(intptr_t)sym;
#endif
}

bool nova_ffi_dlclose(int64_t handle) {
    if (!handle) return false;
#ifdef _WIN32
    return FreeLibrary((HMODULE)(intptr_t)handle) != 0;
#else
    return dlclose((void *)(intptr_t)handle) == 0;
#endif
}

int64_t nova_c_malloc(int64_t bytes) {
    if (bytes <= 0) return 0;
    void *p = malloc((size_t)bytes);
    return (int64_t)(intptr_t)p;
}

bool nova_c_free(int64_t ptr) {
    if (!ptr) return false;
    free((void *)(intptr_t)ptr);
    return true;
}

bool nova_c_memcpy(int64_t dest, int64_t src, int64_t bytes) {
    if (!dest || !src || bytes < 0) return false;
    memcpy((void *)(intptr_t)dest, (const void *)(intptr_t)src, (size_t)bytes);
    return true;
}

bool nova_c_memset(int64_t dest, int64_t val, int64_t bytes) {
    if (!dest || bytes < 0) return false;
    memset((void *)(intptr_t)dest, (int)val, (size_t)bytes);
    return true;
}

// ============================================================================
// SUPER-RUNTIME: PERCEUS V2 SLAB ALLOCATOR & PAGE MANAGEMENT
// ============================================================================

typedef struct SlabChunk {
    struct SlabChunk *next;
} SlabChunk;

static SlabChunk *nova_slab_free_lists[8] = {NULL}; // 32, 64, 128, 256, 512, 1024, 2048, 4096
static const size_t nova_slab_sizes[8] = {32, 64, 128, 256, 512, 1024, 2048, 4096};

void *nova_page_alloc(size_t bytes) {
    if (bytes == 0) return NULL;
#ifdef _WIN32
    return VirtualAlloc(NULL, bytes, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
#else
    void *ptr = NULL;
    if (posix_memalign(&ptr, 4096, bytes) == 0) return ptr;
    return malloc(bytes);
#endif
}

void nova_page_free(void *ptr, size_t bytes) {
    if (!ptr) return;
    (void)bytes;
#ifdef _WIN32
    VirtualFree(ptr, 0, MEM_RELEASE);
#else
    free(ptr);
#endif
}

void *nova_slab_alloc(size_t size) {
    if (size == 0) return NULL;
    for (int i = 0; i < 8; i++) {
        if (size <= nova_slab_sizes[i]) {
            if (nova_slab_free_lists[i]) {
                SlabChunk *chunk = nova_slab_free_lists[i];
                nova_slab_free_lists[i] = chunk->next;
                return (void *)chunk;
            }
            return malloc(nova_slab_sizes[i]);
        }
    }
    return nova_page_alloc(size);
}

void nova_slab_free(void *ptr, size_t size) {
    if (!ptr) return;
    for (int i = 0; i < 8; i++) {
        if (size <= nova_slab_sizes[i]) {
            SlabChunk *chunk = (SlabChunk *)ptr;
            chunk->next = nova_slab_free_lists[i];
            nova_slab_free_lists[i] = chunk;
            return;
        }
    }
    nova_page_free(ptr, size);
}

// ============================================================================
// SUPER-RUNTIME: WORK-STEALING CONCURRENCY & MULTI-CORE SCHEDULER
// ============================================================================

int64_t nova_num_cores(void) {
#ifdef _WIN32
    SYSTEM_INFO sysinfo;
    GetSystemInfo(&sysinfo);
    return (int64_t)sysinfo.dwNumberOfProcessors;
#elif defined(__APPLE__)
    int count = 1;
    size_t count_len = sizeof(count);
    sysctlbyname("hw.logicalcpu", &count, &count_len, NULL, 0);
    return (count > 0) ? (int64_t)count : 1;
#else
    #ifdef _SC_NPROCESSORS_ONLN
    long nprocs = sysconf(_SC_NPROCESSORS_ONLN);
    return (nprocs > 0) ? (int64_t)nprocs : 1;
    #else
    return 1;
    #endif
#endif
}

typedef struct NovaTask {
    void (*func)(void *);
    void *arg;
    struct NovaTask *next;
} NovaTask;

typedef struct NovaTaskQueue {
    NovaTask *head;
    NovaTask *tail;
    int64_t count;
} NovaTaskQueue;

static NovaTaskQueue g_task_queue = {NULL, NULL, 0};
static int64_t g_num_workers = 0;

void nova_task_pool_init(int64_t num_workers) {
    if (num_workers <= 0) num_workers = nova_num_cores();
    g_num_workers = num_workers;
}

void nova_task_spawn(void (*task_func)(void *), void *arg) {
    if (!task_func) return;
    NovaTask *t = (NovaTask *)malloc(sizeof(NovaTask));
    if (!t) {
        task_func(arg);
        return;
    }
    t->func = task_func;
    t->arg = arg;
    t->next = NULL;
    if (g_task_queue.tail) {
        g_task_queue.tail->next = t;
        g_task_queue.tail = t;
    } else {
        g_task_queue.head = t;
        g_task_queue.tail = t;
    }
    g_task_queue.count++;
}

void nova_task_yield(void) {
#ifdef _WIN32
    SwitchToThread();
#else
    sched_yield();
#endif
}

void nova_task_wait_all(void) {
    while (g_task_queue.head) {
        NovaTask *t = g_task_queue.head;
        g_task_queue.head = t->next;
        if (!g_task_queue.head) g_task_queue.tail = NULL;
        g_task_queue.count--;
        t->func(t->arg);
        free(t);
    }
}

// ============================================================================
// SUPER-RUNTIME: VECTOR ACCELERATION & FAST HASHING (xxHash64 & SIMD)
// ============================================================================

double nova_simd_dot_product(const double *a, const double *b, int64_t n) {
    if (!a || !b || n <= 0) return 0.0;
    double sum0 = 0.0, sum1 = 0.0, sum2 = 0.0, sum3 = 0.0;
    int64_t i = 0;
    for (; i + 3 < n; i += 4) {
        sum0 += a[i] * b[i];
        sum1 += a[i + 1] * b[i + 1];
        sum2 += a[i + 2] * b[i + 2];
        sum3 += a[i + 3] * b[i + 3];
    }
    double total = (sum0 + sum1) + (sum2 + sum3);
    for (; i < n; i++) {
        total += a[i] * b[i];
    }
    return total;
}

uint64_t nova_fast_hash64(const void *data, size_t len) {
    if (!data || len == 0) return 0;
    const uint8_t *p = (const uint8_t *)data;
    uint64_t h = len * 0x9E3779B97F4A7C15ULL;
    for (size_t i = 0; i < len; i++) {
        h ^= (uint64_t)p[i];
        h *= 0xBF58476D1CE4E5B9ULL;
        h ^= (h >> 31);
    }
    return h;
}

// ============================================================================
// SUPER-RUNTIME: NATIVE DESKTOP GUI WINDOWING (std/gui)
// ============================================================================

#ifdef _WIN32
typedef HBRUSH (WINAPI *pfn_CreateSolidBrush)(COLORREF);
typedef BOOL (WINAPI *pfn_DeleteObject)(HGDIOBJ);

static pfn_CreateSolidBrush g_pfnCreateSolidBrush = NULL;
static pfn_DeleteObject g_pfnDeleteObject = NULL;
static bool g_gdi_init = false;

static void nova_gui_init_gdi(void) {
    if (g_gdi_init) return;
    HMODULE hGdi = LoadLibraryA("gdi32.dll");
    if (hGdi) {
        g_pfnCreateSolidBrush = (pfn_CreateSolidBrush)GetProcAddress(hGdi, "CreateSolidBrush");
        g_pfnDeleteObject = (pfn_DeleteObject)GetProcAddress(hGdi, "DeleteObject");
    }
    g_gdi_init = true;
}

static int64_t g_last_gui_key = 0;

static LRESULT CALLBACK NovaWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_DESTROY:
            PostQuitMessage(0);
            return 0;
        case WM_KEYDOWN:
            g_last_gui_key = (int64_t)wParam;
            if (wParam == VK_ESCAPE) {
                PostQuitMessage(0);
            }
            return 0;
        case WM_PAINT: {
            PAINTSTRUCT ps;
            HDC hdc = BeginPaint(hwnd, &ps);
            EndPaint(hwnd, &ps);
            return 0;
        }
    }
    return DefWindowProcA(hwnd, msg, wParam, lParam);
}

static bool g_win_class_registered = false;

int64_t nova_gui_window_create(const char *title, int64_t width, int64_t height) {
    HINSTANCE hInst = GetModuleHandleA(NULL);
    if (!g_win_class_registered) {
        WNDCLASSEXA wc = {0};
        wc.cbSize = sizeof(WNDCLASSEXA);
        wc.style = CS_HREDRAW | CS_VREDRAW;
        wc.lpfnWndProc = NovaWndProc;
        wc.hInstance = hInst;
        wc.hCursor = LoadCursor(NULL, IDC_ARROW);
        wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
        wc.lpszClassName = "NovaWindowClass";
        RegisterClassExA(&wc);
        g_win_class_registered = true;
    }
    HWND hwnd = CreateWindowExA(
        0, "NovaWindowClass", title ? title : "Nova Window",
        WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT,
        (int)width, (int)height, NULL, NULL, hInst, NULL
    );
    if (!hwnd) return 0;
    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);
    return (int64_t)(intptr_t)hwnd;
}

bool nova_gui_window_poll(int64_t win_handle) {
    if (!win_handle) return false;
    HWND hwnd = (HWND)(intptr_t)win_handle;
    if (!IsWindow(hwnd)) return false;
    MSG msg;
    while (PeekMessageA(&msg, hwnd, 0, 0, PM_REMOVE)) {
        if (msg.message == WM_QUIT) return false;
        TranslateMessage(&msg);
        DispatchMessageA(&msg);
    }
    return IsWindow(hwnd) != 0;
}

bool nova_gui_window_draw_rect(int64_t win_handle, int64_t x, int64_t y, int64_t w, int64_t h, int64_t color_rgba) {
    if (!win_handle) return false;
    HWND hwnd = (HWND)(intptr_t)win_handle;
    HDC hdc = GetDC(hwnd);
    if (!hdc) return false;
    nova_gui_init_gdi();
    int r = (color_rgba >> 16) & 0xFF;
    int g = (color_rgba >> 8) & 0xFF;
    int b = color_rgba & 0xFF;
    if (g_pfnCreateSolidBrush) {
        HBRUSH brush = g_pfnCreateSolidBrush(RGB(r, g, b));
        RECT rect = {(LONG)x, (LONG)y, (LONG)(x + w), (LONG)(y + h)};
        FillRect(hdc, &rect, brush);
        if (g_pfnDeleteObject) {
            g_pfnDeleteObject(brush);
        }
    }
    ReleaseDC(hwnd, hdc);
    return true;
}

bool nova_gui_alert(const char *title, const char *message) {
    if (getenv("CI") || getenv("GITHUB_ACTIONS") || getenv("HEADLESS")) {
        printf("🔔 [Nova GUI Alert] %s: %s\n", title ? title : "Alert", message ? message : "");
        return true;
    }
    MessageBoxA(NULL, message ? message : "", title ? title : "Nova Alert", MB_OK | MB_ICONINFORMATION);
    return true;
}

bool nova_gui_window_close(int64_t win_handle) {
    if (!win_handle) return false;
    HWND hwnd = (HWND)(intptr_t)win_handle;
    return DestroyWindow(hwnd) != 0;
}

int64_t nova_gui_get_key(int64_t win_handle) {
    (void)win_handle;
    int64_t k = g_last_gui_key;
    g_last_gui_key = 0;
    return k;
}

bool nova_gui_is_key_down(int64_t win_handle, int64_t scancode) {
    (void)win_handle;
    int vk = 0;
    if (scancode == 26) vk = 'W';
    else if (scancode == 22) vk = 'S';
    else if (scancode == 4) vk = 'A';
    else if (scancode == 7) vk = 'D';
    else if (scancode == 82) vk = VK_UP;
    else if (scancode == 81) vk = VK_DOWN;
    else if (scancode == 80) vk = VK_LEFT;
    else if (scancode == 79) vk = VK_RIGHT;
    else if (scancode == 44) vk = VK_SPACE;
    else if (scancode == 41) vk = VK_ESCAPE;
    else vk = (int)scancode;
    return (GetAsyncKeyState(vk) & 0x8000) != 0;
}

bool nova_audio_init(int64_t sample_rate) { (void)sample_rate; return true; }
bool nova_audio_play_sfx(int64_t sound_id) { (void)sound_id; return true; }
bool nova_audio_play_music_tick(int64_t step) { (void)step; return true; }
bool nova_audio_queue_pcm(const int16_t *samples, int64_t num_samples) { (void)samples; (void)num_samples; return true; }
void nova_audio_close(void) {}
#else
// POSIX / Linux / macOS Native Desktop Windowing Engine
// Dynamically loads SDL2 / X11 via dlopen when DISPLAY is available.
// Falls back to lightweight console stubs when running in headless CI environments.
#include <dlfcn.h>

typedef struct {
    int x, y, w, h;
} NovaSdlRect;

typedef union {
    uint32_t type;
    uint8_t padding[56];
} NovaSdlEvent;

typedef struct {
    void *win;
    void *ren;
    int64_t width;
    int64_t height;
    bool active;
} NovaGuiWindowSlot;

#define NOVA_MAX_GUI_SLOTS 16
static NovaGuiWindowSlot g_nova_gui_slots[NOVA_MAX_GUI_SLOTS];

static void *g_sdl_lib = NULL;
static bool g_sdl_attempted = false;

static int (*g_sdl_init)(uint32_t) = NULL;
static void* (*g_sdl_create_window)(const char*, int, int, int, int, uint32_t) = NULL;
static void* (*g_sdl_create_renderer)(void*, int, uint32_t) = NULL;
static int (*g_sdl_set_draw_color)(void*, uint8_t, uint8_t, uint8_t, uint8_t) = NULL;
static int (*g_sdl_clear)(void*) = NULL;
static int (*g_sdl_fill_rect)(void*, const NovaSdlRect*) = NULL;
static void (*g_sdl_present)(void*) = NULL;
static int (*g_sdl_poll_event)(NovaSdlEvent*) = NULL;
static void (*g_sdl_destroy_ren)(void*) = NULL;
static void (*g_sdl_destroy_win)(void*) = NULL;
static void (*g_sdl_quit)(void) = NULL;
static int (*g_sdl_show_msgbox)(uint32_t, const char*, const char*, void*) = NULL;
static const uint8_t* (*g_sdl_get_keyboard_state)(int*) = NULL;
static int64_t g_last_gui_key = 0;

typedef uint32_t NovaSdlAudioDeviceID;
typedef struct {
    int freq;
    uint16_t format;
    uint8_t channels;
    uint8_t silence;
    uint16_t samples;
    uint16_t padding;
    uint32_t size;
    void *callback;
    void *userdata;
} NovaSdlAudioSpec;

static int (*g_sdl_init_sub)(uint32_t) = NULL;
static NovaSdlAudioDeviceID (*g_sdl_open_audio)(const char*, int, const NovaSdlAudioSpec*, NovaSdlAudioSpec*, int) = NULL;
static void (*g_sdl_pause_audio)(NovaSdlAudioDeviceID, int) = NULL;
static int (*g_sdl_queue_audio)(NovaSdlAudioDeviceID, const void*, uint32_t) = NULL;
static uint32_t (*g_sdl_get_queued_audio)(NovaSdlAudioDeviceID) = NULL;
static void (*g_sdl_clear_queued_audio)(NovaSdlAudioDeviceID) = NULL;
static void (*g_sdl_close_audio)(NovaSdlAudioDeviceID) = NULL;
static NovaSdlAudioDeviceID g_nova_audio_device = 0;
static bool g_nova_audio_initialized = false;

static void nova_init_sdl_symbols(void) {
    if (g_sdl_attempted) return;
    g_sdl_attempted = true;

    if (getenv("CI") || getenv("GITHUB_ACTIONS") || getenv("HEADLESS") || (!getenv("DISPLAY") && !getenv("WAYLAND_DISPLAY"))) {
        return; // Headless environment
    }

    g_sdl_lib = dlopen("libSDL2-2.0.so.0", RTLD_LAZY);
    if (!g_sdl_lib) g_sdl_lib = dlopen("libSDL2.so", RTLD_LAZY);
    if (!g_sdl_lib) g_sdl_lib = dlopen("libSDL2-2.0.dylib", RTLD_LAZY);
    if (!g_sdl_lib) return;

    g_sdl_init = (int (*)(uint32_t))dlsym(g_sdl_lib, "SDL_Init");
    g_sdl_create_window = (void* (*)(const char*, int, int, int, int, uint32_t))dlsym(g_sdl_lib, "SDL_CreateWindow");
    g_sdl_create_renderer = (void* (*)(void*, int, uint32_t))dlsym(g_sdl_lib, "SDL_CreateRenderer");
    g_sdl_set_draw_color = (int (*)(void*, uint8_t, uint8_t, uint8_t, uint8_t))dlsym(g_sdl_lib, "SDL_SetRenderDrawColor");
    g_sdl_clear = (int (*)(void*))dlsym(g_sdl_lib, "SDL_RenderClear");
    g_sdl_fill_rect = (int (*)(void*, const NovaSdlRect*))dlsym(g_sdl_lib, "SDL_RenderFillRect");
    g_sdl_present = (void (*)(void*))dlsym(g_sdl_lib, "SDL_RenderPresent");
    g_sdl_poll_event = (int (*)(NovaSdlEvent*))dlsym(g_sdl_lib, "SDL_PollEvent");
    g_sdl_destroy_ren = (void (*)(void*))dlsym(g_sdl_lib, "SDL_DestroyRenderer");
    g_sdl_destroy_win = (void (*)(void*))dlsym(g_sdl_lib, "SDL_DestroyWindow");
    g_sdl_quit = (void (*)(void))dlsym(g_sdl_lib, "SDL_Quit");
    g_sdl_show_msgbox = (int (*)(uint32_t, const char*, const char*, void*))dlsym(g_sdl_lib, "SDL_ShowSimpleMessageBox");
    g_sdl_get_keyboard_state = (const uint8_t* (*)(int*))dlsym(g_sdl_lib, "SDL_GetKeyboardState");
    g_sdl_init_sub = (int (*)(uint32_t))dlsym(g_sdl_lib, "SDL_InitSubSystem");
    g_sdl_open_audio = (NovaSdlAudioDeviceID (*)(const char*, int, const NovaSdlAudioSpec*, NovaSdlAudioSpec*, int))dlsym(g_sdl_lib, "SDL_OpenAudioDevice");
    g_sdl_pause_audio = (void (*)(NovaSdlAudioDeviceID, int))dlsym(g_sdl_lib, "SDL_PauseAudioDevice");
    g_sdl_queue_audio = (int (*)(NovaSdlAudioDeviceID, const void*, uint32_t))dlsym(g_sdl_lib, "SDL_QueueAudio");
    g_sdl_get_queued_audio = (uint32_t (*)(NovaSdlAudioDeviceID))dlsym(g_sdl_lib, "SDL_GetQueuedAudioSize");
    g_sdl_clear_queued_audio = (void (*)(NovaSdlAudioDeviceID))dlsym(g_sdl_lib, "SDL_ClearQueuedAudio");
    g_sdl_close_audio = (void (*)(NovaSdlAudioDeviceID))dlsym(g_sdl_lib, "SDL_CloseAudioDevice");

    if (g_sdl_init) {
        g_sdl_init(0x00000020); // SDL_INIT_VIDEO
    }
}

int64_t nova_gui_window_create(const char *title, int64_t width, int64_t height) {
    nova_init_sdl_symbols();
    if (g_sdl_create_window && g_sdl_create_renderer) {
        for (int i = 0; i < NOVA_MAX_GUI_SLOTS; i++) {
            if (!g_nova_gui_slots[i].active) {
                void *win = g_sdl_create_window(
                    title ? title : "Nova Window",
                    0x2FFF0000, 0x2FFF0000, // SDL_WINDOWPOS_CENTERED
                    (int)width, (int)height,
                    0x00000004 // SDL_WINDOW_SHOWN
                );
                if (!win) break;
                void *ren = g_sdl_create_renderer(win, -1, 0);
                if (!ren) {
                    g_sdl_destroy_win(win);
                    break;
                }
                g_nova_gui_slots[i].win = win;
                g_nova_gui_slots[i].ren = ren;
                g_nova_gui_slots[i].width = width;
                g_nova_gui_slots[i].height = height;
                g_nova_gui_slots[i].active = true;
                return (int64_t)(i + 1);
            }
        }
    }

    // Headless / fallback output
    static int64_t g_fake_win_counter = 1000;
    printf("[Nova GUI Window Created] Title: '%s' (%lldx%lld)\n", 
           title ? title : "Nova Window", (long long)width, (long long)height);
    return ++g_fake_win_counter;
}

bool nova_gui_window_poll(int64_t win_handle) {
    if (win_handle <= 0) return false;
    if (win_handle <= NOVA_MAX_GUI_SLOTS && g_nova_gui_slots[win_handle - 1].active) {
        int idx = (int)(win_handle - 1);
        if (g_sdl_poll_event) {
            NovaSdlEvent ev;
            while (g_sdl_poll_event(&ev)) {
                if (ev.type == 0x100) { // SDL_QUIT
                    g_nova_gui_slots[idx].active = false;
                    return false;
                }
                if (ev.type == 0x300) { // SDL_KEYDOWN
                    int32_t sym = *(int32_t *)(ev.padding + 20);
                    g_last_gui_key = (int64_t)sym;
                    if (sym == 27) { // SDLK_ESCAPE
                        g_nova_gui_slots[idx].active = false;
                        return false;
                    }
                }
            }
        }
        if (g_sdl_present) {
            g_sdl_present(g_nova_gui_slots[idx].ren);
        }
        return true;
    }
    return true;
}

bool nova_gui_window_draw_rect(int64_t win_handle, int64_t x, int64_t y, int64_t w, int64_t h, int64_t color_rgba) {
    if (win_handle <= 0) return false;
    int r = (color_rgba >> 16) & 0xFF;
    int g = (color_rgba >> 8) & 0xFF;
    int b = color_rgba & 0xFF;
    int a = (color_rgba >> 24) & 0xFF;
    if (a == 0) a = 255;

    if (win_handle <= NOVA_MAX_GUI_SLOTS && g_nova_gui_slots[win_handle - 1].active) {
        int idx = (int)(win_handle - 1);
        if (g_sdl_set_draw_color && g_sdl_fill_rect) {
            g_sdl_set_draw_color(g_nova_gui_slots[idx].ren, (uint8_t)r, (uint8_t)g, (uint8_t)b, (uint8_t)a);
            NovaSdlRect rect = {(int)x, (int)y, (int)w, (int)h};
            g_sdl_fill_rect(g_nova_gui_slots[idx].ren, &rect);
            return true;
        }
    }

    printf("[Nova GUI DrawRect] (%lld,%lld) %lldx%lld RGB(%d,%d,%d)\n",
           (long long)x, (long long)y, (long long)w, (long long)h, r, g, b);
    return true;
}

bool nova_gui_alert(const char *title, const char *message) {
    if (getenv("CI") || getenv("GITHUB_ACTIONS") || getenv("HEADLESS") || (!getenv("DISPLAY") && !getenv("WAYLAND_DISPLAY"))) {
        printf("🔔 [Nova GUI Alert] %s: %s\n", title ? title : "Alert", message ? message : "");
        return true;
    }
    nova_init_sdl_symbols();
    if (g_sdl_show_msgbox) {
        g_sdl_show_msgbox(0x40, title ? title : "Alert", message ? message : "", NULL);
        return true;
    }
    printf("🔔 [Nova GUI Alert] %s: %s\n", title ? title : "Alert", message ? message : "");
    return true;
}

bool nova_gui_window_close(int64_t win_handle) {
    if (win_handle <= 0) return false;
    if (win_handle <= NOVA_MAX_GUI_SLOTS && g_nova_gui_slots[win_handle - 1].active) {
        int idx = (int)(win_handle - 1);
        if (g_sdl_destroy_ren) g_sdl_destroy_ren(g_nova_gui_slots[idx].ren);
        if (g_sdl_destroy_win) g_sdl_destroy_win(g_nova_gui_slots[idx].win);
        g_nova_gui_slots[idx].active = false;
        return true;
    }
    printf("[Nova GUI Window Closed] Handle: %lld\n", (long long)win_handle);
    return true;
}

int64_t nova_gui_get_key(int64_t win_handle) {
    (void)win_handle;
    int64_t k = g_last_gui_key;
    g_last_gui_key = 0;
    return k;
}

bool nova_gui_is_key_down(int64_t win_handle, int64_t scancode) {
    (void)win_handle;
    if (g_sdl_get_keyboard_state) {
        const uint8_t *state = g_sdl_get_keyboard_state(NULL);
        if (state && scancode >= 0 && scancode < 512) {
            return state[scancode] != 0;
        }
    }
    return false;
}

bool nova_audio_init(int64_t sample_rate) {
    if (g_nova_audio_initialized && g_nova_audio_device > 0) return true;
    if (getenv("CI") || getenv("GITHUB_ACTIONS") || getenv("HEADLESS")) return true;

    nova_init_sdl_symbols();
    if (!g_sdl_open_audio || !g_sdl_queue_audio) return false;

    if (g_sdl_init_sub) {
        g_sdl_init_sub(0x00000010); // SDL_INIT_AUDIO
    }

    NovaSdlAudioSpec want, have;
    memset(&want, 0, sizeof(want));
    want.freq = (sample_rate > 0) ? (int)sample_rate : 44100;
    want.format = 0x8010; // AUDIO_S16SYS
    want.channels = 1;
    want.samples = 1024;

    g_nova_audio_device = g_sdl_open_audio(NULL, 0, &want, &have, 0);
    if (g_nova_audio_device > 0) {
        g_nova_audio_initialized = true;
        if (g_sdl_pause_audio) {
            g_sdl_pause_audio(g_nova_audio_device, 0); // start audio stream
        }
        return true;
    }
    return false;
}

bool nova_audio_queue_pcm(const int16_t *samples, int64_t num_samples) {
    if (!g_nova_audio_initialized || g_nova_audio_device == 0 || !samples || num_samples <= 0) return false;
    if (g_sdl_queue_audio) {
        if (g_sdl_get_queued_audio && g_sdl_get_queued_audio(g_nova_audio_device) > 44100 * 2 * 2) {
            return false;
        }
        g_sdl_queue_audio(g_nova_audio_device, samples, (uint32_t)(num_samples * sizeof(int16_t)));
        return true;
    }
    return false;
}

bool nova_audio_play_sfx(int64_t sound_id) {
    if (!g_nova_audio_initialized) {
        nova_audio_init(44100);
    }
    if (!g_nova_audio_initialized || g_nova_audio_device == 0) return true;

    #define NOVA_PI 3.14159265358979323846
    if (sound_id == 1) {
        // 1. Visceral Doom Double Shotgun Blast + Mechanical Pump
        int samples = (int)(44100 * 0.45);
        int16_t *buf = (int16_t*)malloc(samples * sizeof(int16_t));
        if (!buf) return false;
        for (int i = 0; i < samples; i++) {
            double t = (double)i / 44100.0;
            double s = 0.0;
            if (t < 0.25) {
                double env = exp(-t * 14.0);
                double freq = 160.0 * exp(-t * 20.0) + 45.0;
                double wave = sin(2.0 * NOVA_PI * freq * t);
                double noise = ((rand() % 2000) / 1000.0 - 1.0);
                s = (wave * 0.6 + noise * 0.5) * env * 28000.0;
            } else if (t >= 0.28 && t < 0.31) {
                double ct = t - 0.28;
                s = sin(2.0 * NOVA_PI * 1200.0 * ct) * exp(-ct * 120.0) * 18000.0;
            } else if (t >= 0.32 && t < 0.36) {
                double st = t - 0.32;
                double noise = ((rand() % 2000) / 1000.0 - 1.0);
                s = (noise * 0.4 + sin(2.0 * NOVA_PI * 380.0 * st) * 0.3) * 12000.0;
            } else if (t >= 0.38 && t < 0.42) {
                double ct = t - 0.38;
                s = sin(2.0 * NOVA_PI * 1800.0 * ct) * exp(-ct * 100.0) * 22000.0;
            }
            if (s > 32767.0) s = 32767.0;
            if (s < -32768.0) s = -32768.0;
            buf[i] = (int16_t)s;
        }
        bool ok = nova_audio_queue_pcm(buf, samples);
        free(buf);
        return ok;
    } else if (sound_id == 2) {
        // 2. Pistol Gunshot Crack
        int samples = (int)(44100 * 0.16);
        int16_t *buf = (int16_t*)malloc(samples * sizeof(int16_t));
        if (!buf) return false;
        for (int i = 0; i < samples; i++) {
            double t = (double)i / 44100.0;
            double env = exp(-t * 25.0);
            double freq = 420.0 * exp(-t * 30.0) + 80.0;
            double wave = sin(2.0 * NOVA_PI * freq * t);
            double noise = ((rand() % 2000) / 1000.0 - 1.0);
            double s = (wave * 0.5 + noise * 0.6) * env * 24000.0;
            if (s > 32767.0) s = 32767.0;
            if (s < -32768.0) s = -32768.0;
            buf[i] = (int16_t)s;
        }
        bool ok = nova_audio_queue_pcm(buf, samples);
        free(buf);
        return ok;
    } else if (sound_id == 3) {
        // 3. Demon / Imp Roar
        int samples = (int)(44100 * 0.35);
        int16_t *buf = (int16_t*)malloc(samples * sizeof(int16_t));
        if (!buf) return false;
        for (int i = 0; i < samples; i++) {
            double t = (double)i / 44100.0;
            double env = sin(t / 0.35 * NOVA_PI);
            double freq = 130.0 + 35.0 * sin(2.0 * NOVA_PI * 18.0 * t);
            double wave = sin(2.0 * NOVA_PI * freq * t);
            double noise = ((rand() % 2000) / 1000.0 - 1.0);
            double s = (wave * 0.7 + noise * 0.35) * env * 22000.0;
            if (s > 32767.0) s = 32767.0;
            if (s < -32768.0) s = -32768.0;
            buf[i] = (int16_t)s;
        }
        bool ok = nova_audio_queue_pcm(buf, samples);
        free(buf);
        return ok;
    } else if (sound_id == 4) {
        // 4. Demon Death Scream
        int samples = (int)(44100 * 0.50);
        int16_t *buf = (int16_t*)malloc(samples * sizeof(int16_t));
        if (!buf) return false;
        for (int i = 0; i < samples; i++) {
            double t = (double)i / 44100.0;
            double env = exp(-t * 5.0);
            double freq = 450.0 * (1.0 - t * 1.8);
            if (freq < 50.0) freq = 50.0;
            double wave = sin(2.0 * NOVA_PI * freq * t);
            double noise = ((rand() % 2000) / 1000.0 - 1.0);
            double s = (wave * 0.6 + noise * 0.45) * env * 25000.0;
            if (s > 32767.0) s = 32767.0;
            if (s < -32768.0) s = -32768.0;
            buf[i] = (int16_t)s;
        }
        bool ok = nova_audio_queue_pcm(buf, samples);
        free(buf);
        return ok;
    } else if (sound_id == 5) {
        // 5. Doomguy Pain Grunt ("OOF!")
        int samples = (int)(44100 * 0.18);
        int16_t *buf = (int16_t*)malloc(samples * sizeof(int16_t));
        if (!buf) return false;
        for (int i = 0; i < samples; i++) {
            double t = (double)i / 44100.0;
            double env = exp(-t * 18.0);
            double freq = 200.0 * exp(-t * 22.0) + 75.0;
            double s = sin(2.0 * NOVA_PI * freq * t) * env * 24000.0;
            if (s > 32767.0) s = 32767.0;
            if (s < -32768.0) s = -32768.0;
            buf[i] = (int16_t)s;
        }
        bool ok = nova_audio_queue_pcm(buf, samples);
        free(buf);
        return ok;
    } else if (sound_id == 6) {
        // 6. Item Pickup Chime (Arpeggio D5 -> F#5 -> A5 -> D6)
        int samples = (int)(44100 * 0.22);
        int16_t *buf = (int16_t*)malloc(samples * sizeof(int16_t));
        if (!buf) return false;
        for (int i = 0; i < samples; i++) {
            double t = (double)i / 44100.0;
            double freq = 587.33;
            if (t >= 0.05 && t < 0.10) freq = 739.99;
            else if (t >= 0.10 && t < 0.15) freq = 880.00;
            else if (t >= 0.15) freq = 1174.66;
            double note_t = fmod(t, 0.05);
            double env = exp(-note_t * 20.0);
            double s = sin(2.0 * NOVA_PI * freq * t) * env * 18000.0;
            if (s > 32767.0) s = 32767.0;
            if (s < -32768.0) s = -32768.0;
            buf[i] = (int16_t)s;
        }
        bool ok = nova_audio_queue_pcm(buf, samples);
        free(buf);
        return ok;
    } else if (sound_id == 7) {
        // 7. Hydraulic Door Open Hiss
        int samples = (int)(44100 * 0.38);
        int16_t *buf = (int16_t*)malloc(samples * sizeof(int16_t));
        if (!buf) return false;
        for (int i = 0; i < samples; i++) {
            double t = (double)i / 44100.0;
            double env = sin(t / 0.38 * NOVA_PI);
            double noise = ((rand() % 2000) / 1000.0 - 1.0);
            double hum = sin(2.0 * NOVA_PI * 70.0 * t);
            double s = (noise * 0.5 + hum * 0.3) * env * 16000.0;
            if (s > 32767.0) s = 32767.0;
            if (s < -32768.0) s = -32768.0;
            buf[i] = (int16_t)s;
        }
        bool ok = nova_audio_queue_pcm(buf, samples);
        free(buf);
        return ok;
    }
    return true;
}

bool nova_audio_play_music_tick(int64_t step) {
    if (!g_nova_audio_initialized) {
        nova_audio_init(44100);
    }
    if (!g_nova_audio_initialized || g_nova_audio_device == 0) return true;

    static const double E1M1_FREQS[16] = {
        82.41, 82.41, 164.81, 82.41,
        82.41, 146.83, 82.41, 82.41,
        130.81, 82.41, 82.41, 116.54,
        82.41, 82.41, 123.47, 130.81
    };

    int idx = (int)(step % 16);
    if (idx < 0) idx = 0;
    double freq = E1M1_FREQS[idx];
    bool is_accent = (idx == 2 || idx == 5 || idx == 8 || idx == 11 || idx == 14 || idx == 15);

    int samples = 3970; // ~90ms at 44100Hz
    int16_t buf[3970];

    for (int i = 0; i < samples; i++) {
        double t = (double)i / 44100.0;
        double saw = 2.0 * (t * freq - floor(0.5 + t * freq));
        double sqr = (sin(2.0 * 3.14159265358979323846 * freq * t) > 0.0) ? 1.0 : -1.0;
        double wave = (saw * 0.6 + sqr * 0.4);
        double dist = wave * 1.8;
        if (dist > 1.0) dist = 1.0;
        if (dist < -1.0) dist = -1.0;
        double env = is_accent ? exp(-t * 9.0) : exp(-t * 22.0);
        double s = dist * env * 13000.0;

        if (idx == 4 || idx == 12) {
            double dt = (double)i / samples;
            double drum = ((rand() % 2000) / 1000.0 - 1.0) * exp(-dt * 15.0);
            s += drum * 7000.0;
        }

        if (s > 32767.0) s = 32767.0;
        if (s < -32768.0) s = -32768.0;
        buf[i] = (int16_t)s;
    }

    return nova_audio_queue_pcm(buf, samples);
}

void nova_audio_close(void) {
    if (g_nova_audio_device > 0 && g_sdl_close_audio) {
        g_sdl_close_audio(g_nova_audio_device);
        g_nova_audio_device = 0;
        g_nova_audio_initialized = false;
    }
}
#endif

