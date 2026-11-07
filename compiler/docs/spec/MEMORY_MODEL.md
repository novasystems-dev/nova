# Nova Memory Architecture: Regions + Perceus Reference Counting

Nova completely eliminates tracing garbage collection while liberating developers from manual borrow-checker lifetime annotations (`'a`, `'b`).

The memory model is rooted in two formal pillars:
1. **Automatic Region Inference**
2. **Perceus Reference Counting with In-Place Memory Reuse**

---

## 1. Automatic Region Inference

Every heap allocation in Nova is assigned to a discrete lexical or dynamic Region:

- **Stack Promotion**: Values whose lifetimes are statically proven not to escape their calling frame are allocated directly on the CPU call stack (allocation cost = 0).
- **Region Bulk Deallocation**: Objects tied to a common lifecycle (such as a single HTTP request or loop cycle) share a bump-allocated arena. When the arena scope exits, memory is reclaimed en masse in $O(1)$ without heap fragmentation.
- **Typed Region Indices**: Graphs and doubly-linked structures utilize typed region indices, completely safe from dangling pointers and use-after-free bugs without requiring unsafe pointers.

---

## 2. Perceus Precise Reference Counting with In-Place Reuse

Adopting Microsoft Research's Perceus design:

1. **Uniqueness Analysis**: If an algebraic data type (e.g. tree node or list cell) has a reference count of 1 at an update point, it is guaranteed to be uniquely owned.
2. **In-Place Mutation**: Instead of allocating a new node and deallocating the old one, Nova reuses the exact memory cell in-place.
3. This achieves C-level performance while maintaining pure referential transparency in the surface language.

---

## 3. Concurrency via Reference Capabilities

To mathematically prevent data races:

- **`iso` (Isolated)**: Exactly one unique reference exists across the entire runtime. Can be sent across threads lock-free with zero copy.
- **`val` (Value)**: Deeply immutable. Freely shared across multiple threads without locking.
- **`ref` (Thread-Local Reference)**: Mutable reference strictly confined to the local thread. Passing across thread boundaries triggers a compile-time rejection.

---

## 4. Capability-Gated Unsafe

Arbitrary `unsafe` blocks are rejected. Unsafe primitives require an explicit capability token passed down from `main`:

```nova
fn write_raw_mmio(cap: UnsafeHardwareCap, addr: UInt64, val: UInt32):
    unsafe(cap):
        # Raw hardware write
        ...
```
Third-party libraries cannot execute unsafe code unless explicitly granted the capability token at call sites.
