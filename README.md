# The Nova Systems Programming Language

> **Zero GC | Perceus In-Place Reuse | Refinement Safety via Z3 | Bare-Metal Parity**

Nova is a modern systems programming language engineered to achieve the memory safety and ergonomics of Rust, the raw execution speed and bare-metal hardware control of C/C++, and the formal correctness guarantees of SMT-backed Refinement Types.

---

## Key Pillars

1. **Deterministic Zero-GC Memory**:
   Nova employs the **Perceus reference-counting model** with compile-time in-place buffer recycling. When an object's reference count is 1, mutations execute destructively in place without allocating new memory chunks.
2. **Compile-Time Formal Verification**:
   Invariants such as non-zero division, array bounds, and arithmetic overflow bounds are proven at compile time using the **Microsoft Z3 SMT solver**.
3. **Capability-Gated Concurrency**:
   Static tracking of isolation (`iso`), immutable sharing (`val`), and thread-local references (`ref`) prevents data races and deadlocks at compile time.
4. **Bare-Metal Systems Parity**:
   Hardware raw pointers (`*mut T`, `*const T`), address-of (`&val`), dereference (`*ptr`), and inline assembly (`asm("...")`) for operating systems, hypervisors, and embedded kernels.
5. **Universal Toolchain**:
   Includes compiler (`novac`), package manager (`orbit`), interactive REPL (`nova-repl`), formatter (`nova-fmt`), linter (`nova-lint`), and language server (`nova-lsp`).

---

## Quickstart

### Installation
```bash
./install.sh
export PATH="$HOME/.local/bin:$PATH"
```

### Running an Example
```bash
novac run examples/01_hello.nova
novac run examples/08_traits_and_baremetal.nova
novac run examples/09_std_industrial.nova
```

### Interactive REPL
```bash
nova-repl
# or: novac repl
```

### Package Management with Orbit
```bash
orbit new my_project
cd my_project
orbit lock
orbit run
```

---

## Documentation
- [Language Specification](docs/spec.md)
- [Standard Library Reference](docs/stdlib.md)

---

## License
MIT License. See [LICENSE](LICENSE) for details.
