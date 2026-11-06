# Nova Systems Programming Language - Formal Specification v0.1.0

## 1. Introduction & Guiding Principles
Nova is an industrial-grade systems programming language combining:
1. **Zero Garbage Collection (Zero GC)**: Deterministic memory management via Perceus reference counting and compile-time in-place buffer recycling.
2. **Refinement Safety via SMT**: First-class refinement types verified formally at compile time via Microsoft Z3 SMT solver.
3. **Capability-Gated Concurrency & Hardware**: Static isolation (`iso`), immutable sharing (`val`), thread-local mutable references (`ref`), and root hardware tokens (`cap`).
4. **Bare-Metal Systems Parity**: Raw pointers (`*mut T`, `*const T`), address-of (`&val`), dereference (`*ptr`), and inline assembly (`asm`).

---

## 2. Syntax & Lexical Grammar

### 2.1 Indentation & Layout (Off-Side Rule)
Nova uses significant whitespace indentation (4 spaces per level) or explicit curly braces `{}`. Colons `:` introduce indented blocks. Comments begin with `#`.

### 2.2 Primitive Types
- Integers: `Int` (64-bit signed), `i8`, `i16`, `i32`, `i64`, `isize`, `u8`, `u16`, `u32`, `u64`, `usize`.
- Floating-point: `Float` (64-bit IEEE 754), `f32`, `f64`.
- Boolean: `Bool` (`true`, `false`).
- String: `String` (UTF-8 immutable string slice).
- Unit: `()` / void.

### 2.3 Algebraic Data Types
```nova
type Point = struct:
    x: Int
    y: Int

type Option[T] = enum:
    Some(val: T)
    None
```

### 2.4 Traits & Zero-Cost Monomorphization
```nova
trait Display:
    fn to_string(x: Int) -> String

impl Display for Int:
    fn to_string(x: Int) -> String:
        "formatted_int"
```

### 2.5 Refinement Types & Z3 Proofs
Refinement types attach mathematical predicates to base types. The compiler translates invariants into SMT-LIB2 assertions and queries Z3:
```nova
type NonZero = n: Int where n != 0
type BoundedInt = n: Int where n >= 0 and n <= 100

pub fn safe_divide(a: Int, b: NonZero) -> Int:
    a / b
```
If denominator `b` cannot be proven non-zero at compile time, compilation is rejected with code `E0401`.

### 2.6 Hardware Concurrency & Capabilities
- `iso T`: Isolated unique reference. Can be moved across threads with zero copy and zero data races.
- `val T`: Globally immutable reference. Can be shared safely across any number of concurrent threads.
- `ref T`: Thread-local mutable reference. Cannot cross thread boundaries.
- `cap UnsafeHardwareCap`: Capability token required to execute `unsafe(cap):` blocks.

### 2.7 Bare-Metal Pointers & Inline Assembly
```nova
pub fn read_io_port(cap: HardwareCap) -> Int:
    unsafe(cap):
        asm("nop")
        let mut reg = 1337
        let p: *mut Int = &reg
        let val = *p
        val
```

---

## 3. Memory & Execution Model
- **No Stop-The-World GC**: Memory is released immediately when reference count drops to zero.
- **In-Place Reuse**: When an object's reference count is 1, mutations update the buffer in place without memory allocation.
- **Region Arenas**: Ephemeral memory chunks allocated sequentially and reclaimed in $O(1)$ time upon exiting a `region r:` block.
