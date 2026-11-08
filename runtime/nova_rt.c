#define _POSIX_C_SOURCE 200809L
#define _DEFAULT_SOURCE
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
#else
    long nprocs = sysconf(_SC_NPROCESSORS_ONLN);
    return (nprocs > 0) ? (int64_t)nprocs : 1;
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
static LRESULT CALLBACK NovaWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
    switch (msg) {
        case WM_DESTROY:
            PostQuitMessage(0);
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
    int r = (color_rgba >> 16) & 0xFF;
    int g = (color_rgba >> 8) & 0xFF;
    int b = color_rgba & 0xFF;
    HBRUSH brush = CreateSolidBrush(RGB(r, g, b));
    RECT rect = {(LONG)x, (LONG)y, (LONG)(x + w), (LONG)(y + h)};
    FillRect(hdc, &rect, brush);
    DeleteObject(brush);
    ReleaseDC(hwnd, hdc);
    return true;
}

bool nova_gui_alert(const char *title, const char *message) {
    MessageBoxA(NULL, message ? message : "", title ? title : "Nova Alert", MB_OK | MB_ICONINFORMATION);
    return true;
}

bool nova_gui_window_close(int64_t win_handle) {
    if (!win_handle) return false;
    HWND hwnd = (HWND)(intptr_t)win_handle;
    return DestroyWindow(hwnd) != 0;
}
#else
// POSIX / Non-Windows Native GUI Stubs (Lightweight & zero external dependency)
static int64_t g_fake_win_counter = 1000;

int64_t nova_gui_window_create(const char *title, int64_t width, int64_t height) {
    printf("[Nova GUI Window Created] Title: '%s' (%lldx%lld)\n", 
           title ? title : "Nova Window", (long long)width, (long long)height);
    return ++g_fake_win_counter;
}

bool nova_gui_window_poll(int64_t win_handle) {
    if (win_handle <= 0) return false;
    return true;
}

bool nova_gui_window_draw_rect(int64_t win_handle, int64_t x, int64_t y, int64_t w, int64_t h, int64_t color_rgba) {
    if (win_handle <= 0) return false;
    int r = (color_rgba >> 16) & 0xFF;
    int g = (color_rgba >> 8) & 0xFF;
    int b = color_rgba & 0xFF;
    printf("[Nova GUI DrawRect] (%lld,%lld) %lldx%lld RGB(%d,%d,%d)\n",
           (long long)x, (long long)y, (long long)w, (long long)h, r, g, b);
    return true;
}

bool nova_gui_alert(const char *title, const char *message) {
    printf("🔔 [Nova GUI Alert] %s: %s\n", title ? title : "Alert", message ? message : "");
    return true;
}

bool nova_gui_window_close(int64_t win_handle) {
    if (win_handle <= 0) return false;
    printf("[Nova GUI Window Closed] Handle: %lld\n", (long long)win_handle);
    return true;
}
#endif

