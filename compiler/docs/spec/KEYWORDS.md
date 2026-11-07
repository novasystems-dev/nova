# Nova Core Keywords Specification

Nova strictly adheres to cognitive minimalism: **the total number of keywords is strictly under 25**. All complex patterns are inferred or desugared into this minimal primitive set.

---

## Core 24 Keywords

| # | Keyword | Purpose | Example |
| :--- | :--- | :--- | :--- |
| 1 | `fn` | Function and procedure definition | `fn add(a: Int, b: Int) -> Int:` |
| 2 | `let` | Immutable variable binding by default | `let x = 42` |
| 3 | `mut` | Explicit mutable variable modifier | `let mut counter = 0` |
| 4 | `type` | Type definition (Struct, Enum, Alias, Refinement) | `type Point = struct { x: Float, y: Float }` |
| 5 | `match` | Exhaustive pattern matching | `match opt: Some(v) => v, None => 0` |
| 6 | `where` | Refinement type predicate clause | `type NonZero = x: Int where x != 0` |
| 7 | `if` | Conditional branch | `if x > 0:` |
| 8 | `else` | Fallback branch | `else:` |
| 9 | `for` | Iterator loop (desugars to iter step) | `for item in items:` |
| 10 | `while` | Predicate loop | `while is_running:` |
| 11 | `return` | Explicit return statement | `return a + b` |
| 12 | `break` | Terminate loop execution | `break` |
| 13 | `continue`| Advance loop iteration | `continue` |
| 14 | `pub` | Public module export modifier | `pub fn api_call():` |
| 15 | `import` | Import module or external namespace | `import std.io` |
| 16 | `as` | Import alias or explicit safe cast | `import std.io as sys_io` |
| 17 | `trait` | Behavior contract definition | `trait Show:` |
| 18 | `impl` | Trait implementation block | `impl Show for Point:` |
| 19 | `unsafe` | Scoped low-level hardware operation | `unsafe(cap): ...` |
| 20 | `cap` | Capability token declaration | `cap NetCap, FsCap` |
| 21 | `region` | Explicit memory arena scope | `region r:` |
| 22 | `iso` | Isolated linear reference (concurrency) | `let msg: iso Message = Message()` |
| 23 | `val` | Globally immutable reference | `let config: val Config = load()` |
| 24 | `ref` | Thread-local mutable reference | `let buffer: ref Buffer = get_buf()` |

---

## Explicitly Excluded Language Features

1. **`null` / `nil` / `undefined`**: Completely omitted. Replaced with `Option[T] = Some(T) | None`.
2. **`try` / `catch` / `throw`**: Omitted. Errors are first-class values via `Result[T, E] = Ok(T) | Err(E)`.
3. **`goto`**: Not supported.
4. **OOP Inheritance**: Not supported. Composition (`struct`) + Polymorphism (`trait` / `impl`) is enforced.
5. **Lifetime annotations (`'a`)**: Completely automated by Region Inference.
