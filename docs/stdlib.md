# Nova Standard Library Reference Manual (v0.1.0)

The Nova standard library (`std/`) provides zero-GC, memory-safe, and high-performance systems programming primitives.

---

## 1. `std.sync` - Hardware Atomics & Mutex
Hardware-level lockless synchronization primitives and thread mutual exclusion.

- `type AtomicInt = struct: val: Int`
- `fn atomic_new(initial: Int) -> AtomicInt`
- `fn atomic_get(a: AtomicInt) -> Int`
- `fn atomic_set(a: AtomicInt, v: Int)`
- `fn atomic_fetch_add(a: AtomicInt, delta: Int) -> Int`
- `fn atomic_fetch_sub(a: AtomicInt, delta: Int) -> Int`
- `fn atomic_compare_and_swap(a: AtomicInt, expected: Int, desired: Int) -> Bool`
- `type Mutex = struct: handle: Int`
- `fn mutex_new() -> Mutex`
- `fn mutex_acquire(m: Mutex)`
- `fn mutex_release(m: Mutex)`
- `fn mutex_free(m: Mutex)`

---

## 2. `std.fs` - POSIX Filesystem Engine
Safe POSIX file operations and path manipulation.

- `type Path = struct: raw: String`
- `fn path_new(s: String) -> Path`
- `fn fs_read(p: Path) -> String`
- `fn fs_write(p: Path, content: String) -> Bool`
- `fn fs_check_exists(p: Path) -> Bool`
- `fn fs_get_size(p: Path) -> Int`
- `fn fs_delete(p: Path) -> Bool`

---

## 3. `std.net` - High-Performance TCP Networking
Raw POSIX socket server and HTTP response streaming abstractions.

- `type TcpListener = struct: port: Int, fd: Int, is_active: Bool`
- `fn tcp_listener_bind(port: Int) -> TcpListener`
- `fn tcp_listener_accept(listener: TcpListener) -> Int`
- `fn tcp_listener_close(listener: TcpListener)`
- `type HttpResponse = struct: status_code: String, body: String`
- `fn http_response_ok(body: String) -> HttpResponse`
- `fn http_response_not_found() -> HttpResponse`
- `fn http_send(client_fd: Int, resp: HttpResponse) -> Int`

---

## 4. `std.json` - Zero-Copy JSON
Fast zero-copy serialization and parsing using Perceus reference reuse.

- `type JsonValue = enum: Null, BoolVal(Bool), NumVal(Int), StrVal(String)`
- `fn json_null() -> JsonValue`
- `fn json_bool(b: Bool) -> JsonValue`
- `fn json_number(n: Int) -> JsonValue`
- `fn json_string(s: String) -> JsonValue`
- `fn json_stringify_bool(b: Bool) -> String`
- `fn json_stringify_null() -> String`

---

## 5. `std.vec` - Resizable Dynamic Array
Dynamic contiguous vector with Perceus in-place buffer recycling.

- `type Vec = struct: data: Int, len: Int, cap: Int`
- `fn vec_new() -> Vec`
- `fn vec_with_capacity(capacity: Int) -> Vec`
- `fn vec_len(v: Vec) -> Int`
- `fn vec_cap(v: Vec) -> Int`
- `fn vec_is_empty(v: Vec) -> Bool`
- `fn vec_push(v: Vec, elem: Int) -> Vec`
- `fn vec_pop(v: Vec) -> Vec`
- `fn vec_clear(v: Vec) -> Vec`

---

## 6. `std.map` - Hash Map Key-Value Store
Associative hash table with collision resolution.

- `type Map = struct: size: Int, capacity: Int`
- `fn map_new() -> Map`
- `fn map_with_capacity(capacity: Int) -> Map`
- `fn map_len(m: Map) -> Int`
- `fn map_is_empty(m: Map) -> Bool`
- `fn map_insert(m: Map, key: String, val: Int) -> Map`
- `fn map_contains(m: Map, key: String) -> Bool`

---

## 7. `std.string` - String Manipulation
Immutable UTF-8 string manipulation and formatting.

- `type StringView = struct: len: Int, is_empty: Bool`
- `fn string_view_new(len: Int) -> StringView`
- `fn string_len(s: StringView) -> Int`
- `fn string_is_empty(s: StringView) -> Bool`
- `fn string_concat(a: String, b: String) -> String`

---

## 8. `std.io` - Streaming & File Descriptors
Core low-level I/O streams and file descriptor wrappers.

- `type FileHandle = struct: descriptor: Int, is_open: Bool`
- `fn io_open(fd: Int) -> FileHandle`
- `fn io_close(handle: FileHandle) -> FileHandle`
- `fn io_is_valid(handle: FileHandle) -> Bool`
