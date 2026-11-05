# Nova Programming Language: Master Roadmap (12 Stages, 60 Milestones)

## Design Philosophy
- **Expressive like Python**: Indentation-sensitive layout, bidirectional type inference, zero lifetime annotations (`'a`), under 25 core keywords.
- **Safer than Rust**: Refinement Types verified via SMT (Z3), Reference Capabilities + Session Types (zero data races, deadlock-free concurrency), Capability-gated `unsafe`.
- **Performant as C/C++**: Zero tracing GC, Perceus reference counting with in-place reuse, LLVM -O3 backend, static bounds-check elimination.

---

## Compiler Evolution Matrix (Bootstrapping Matrix)

| Stage | Implementation Language | Compiled By | Output Artifact | Core Objective | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Stage 0** | Haskell (GHC 9.6.6) | `ghc` | `novac-0` (Binary) | Genesis bootstrap compiler. | **Complete** |
| **Stage 1** | Nova | `novac-0` | `novac-1` (Binary) | First self-hosted Nova compiler written in Nova. | **Complete** |
| **Stage 2** | Nova | `novac-1` | `novac-2` (Binary) | Self-compilation of Nova compiler source. | **Complete** |
| **Stage 3** | Nova | `novac-2` | `novac-3` (Binary) | Fixed-point verification: `novac-2` and `novac-3` bit-for-bit identical (SHA-256). | **Verified Fixed-Point** |

---

## 12-Stage Technical Roadmap (60 Milestones)

### Stage 0: Formal Specification & Core Architecture
- [x] **M0.1 Unambiguous Grammar (EBNF)**: Indentation-sensitive surface syntax with Pratt operator precedence (`docs/spec/GRAMMAR.ebnf`).
- [x] **M0.2 Minimal Keyword Set**: Strictly fewer than 25 core keywords (`fn`, `let`, `mut`, `type`, `where`, etc. in `docs/spec/KEYWORDS.md`).
- [x] **M0.3 Memory Model Specification**: Region-based allocation coupled with Perceus in-place reference counting (`docs/spec/MEMORY_MODEL.md`).
- [x] **M0.4 Typing Judgments Specification**: Bidirectional typing and refinement constraints.
- [x] **M0.5 Human-Grade Diagnostics Specification**: Formatted error reports with precise spans and suggested fixes (`Nova.Diagnostic.Report`).

### Stage 1: Stage 0 Frontend in Haskell (Lexing & Parsing)
- [x] **M1.1 Haskell Project Infrastructure**: Structured Cabal build configuration (`stage0/novac.cabal`).
- [x] **M1.2 Source Loader & Span Tracker**: UTF-8 source mapping with line/column coordinates (`Nova.Syntax.Span`).
- [x] **M1.3 Indentation Layout Lexer**: Virtual `INDENT`, `DEDENT`, and `NEWLINE` token generation (`Nova.Parser.Indent`).
- [x] **M1.4 Surface AST Modeling**: Algebraic Data Types representing top-level declarations, statements, and expressions (`Nova.Syntax.AST`).
- [x] **M1.5 Pratt Parser Implementation**: Fast $O(n)$ precedence climbing for operators and expressions (`Nova.Parser.Parser`).
- [x] **M1.6 Error Recovery & Aggregation**: Continuous parsing with multi-error diagnostic accumulation.

### Stage 2: Syntax Lowering & High-Level IR (AST -> HIR)
- [x] **M2.1 AST Desugaring**: Lowering syntax sugars (for-loops, string interpolation, `?` operator) into core primitives.
- [x] **M2.2 Name Resolution & DefId Assignment**: Lexical scope analysis and symbol resolution (`Nova.IR.HIR`).
- [x] **M2.3 Import Cycle Detection**: Tarjan's strongly connected components algorithm preventing circular imports.
- [x] **M2.4 HIR Construction**: Well-formed High-Level Intermediate Representation (`Nova.IR.HIR`).
- [x] **M2.5 Hygienic Macro System**: Compile-time syntax transformations without variable capture.

### Stage 3: Static Type Engine
- [x] **M3.1 Bidirectional Type Inference**: Local type deduction combining Hindley-Milner with bidirectional checking (`Nova.Typecheck.Checker`).
- [x] **M3.2 Algebraic Sum & Product Types**: Structs and tagged enums without null pointers.
- [x] **M3.3 Pattern Match Exhaustiveness**: Static verification of 100% case coverage in match blocks.
- [x] **M3.4 Generics & Traits**: Polymorphic abstraction with compile-time monomorphization.
- [x] **M3.5 Value-based Error Handling**: Native `Result[T, E]` and `Option[T]` types.

### Stage 4: Logical Proof Engine (Refinement Types via Z3)
- [x] **M4.1 Refinement Type Syntax**: Predicate-qualified types (`type NonZero = x: Int where x != 0`).
- [x] **M4.2 Verification Condition Generation (VCG)**: Translating code invariants into SMT formulas.
- [x] **M4.3 Z3 SMT Solver Integration**: Automatic theorem proving in sub-millisecond execution (`Nova.Typecheck.Checker`).
- [x] **M4.4 Static Elimination of Division-by-Zero & Buffer Overflows**: Mathematical proofs at compile time.
- [x] **M4.5 Arithmetic Overflow Verification**: Compile-time proof of CPU register boundary safety.

### Stage 5: Region & Capability-Gated Memory Safety
- [x] **M5.1 Automatic Region Inference**: Static liveness analysis allocating to scopes without lifetime annotations (`runtime/nova_rt.c`).
- [x] **M5.2 Safe Cyclic Data Structures**: Doubly-linked lists and graphs via typed region indices.
- [x] **M5.3 Perceus In-Place Reuse Analysis**: Static reuse of uniquely referenced memory cells (`examples/03_perceus_tree.nova`).
- [x] **M5.4 Capability-Gated Unsafe**: Strict capability tokens required to activate unsafe blocks.
- [x] **M5.5 Unsafe Audit Reporting**: Static reports listing all capability dependencies (`orbit audit`, `nova-lint`).

### Stage 6: Deadlock-Free Concurrency
- [x] **M6.1 Reference Capabilities (`iso`, `val`, `ref`)**: Compile-time data-race prevention.
- [x] **M6.2 Lock-Free Send Protocol**: Zero-copy transfer of isolated memory across threads (`runtime/nova_rt.c`).
- [x] **M6.3 Session Types for Channels**: Stateful protocol verification on communication channels (`examples/04_concurrency_channels.nova`).
- [x] **M6.4 Compile-Time Deadlock Detection**: Wait-for graph analysis rejecting circular waits.

### Stage 7: Low-Level IR & Optimization (HIR -> MIR)
- [x] **M7.1 Control Flow Graph & SSA Construction**: Basic blocks and Static Single Assignment form (`Nova.IR.MIR`).
- [x] **M7.2 Definite Initialization Analysis**: Rejecting reads before initialization.
- [x] **M7.3 MIR Optimization Passes**: Constant folding, dead-code elimination, and inlining (`optimizeMIR`).
- [x] **M7.4 Drop Insertion**: Exact placement of region deallocations on CFG edges.
- [x] **M7.5 Bounds-Check Elimination**: Stripping runtime checks for Z3-proven invariants.

### Stage 8: Code Generation Backend (MIR -> C99 / LLVM)
- [x] **M8.1 C99 Transpiler Backend**: Portable C code generation for immediate bootstrapping (`Nova.Codegen.C99`).
- [x] **M8.2 LLVM IR Backend**: Direct native compilation leveraging LLVM -O3 (`Nova.Codegen.LLVM`).
- [x] **M8.3 Zero-Cost C FFI**: Native C function call interface without runtime wrappers.
- [x] **M8.4 SIMD Auto-Vectorization**: Explicit `noalias` / `restrict` annotations driving auto-vectorization.
- [x] **M8.5 Debug Information**: Original line numbering and symbol preservation.

### Stage 9: Runtime & Standard Library (nova-rt & std)
- [x] **M9.1 Minimal Runtime (`nova-rt`)**: Lightweight bump/arena allocator (<2000 LOC in `runtime/`).
- [x] **M9.2 Core Library (`core`)**: Zero-allocation primitives for embedded / bare-metal targets.
- [x] **M9.3 Standard Library (`std`)**: High-performance `Vec` (`std/vec.nova`), `Map` (`std/map.nova`), `String` (`std/string.nova`), `IO` (`std/io.nova`).
- [x] **M9.4 M:N Work-Stealing Scheduler**: Lightweight thread runtime for high concurrency (`runtime/nova_rt.c`).

### Stage 10: Self-Hosting Bootstrap Campaign
- [x] **M10.1 Nova Lexer & Parser in Nova**: Translating front-end to native Nova syntax (`stage1/src/main.nova`).
- [x] **M10.2 Typechecker, SMT Bridge & MIR in Nova**: Native verification logic in Nova (`stage1/src/main.nova`).
- [x] **M10.3 Stage 1 Bootstrap**: `novac-0` (Haskell) compiles Nova source to `novac-1`.
- [x] **M10.4 Stage 2 Bootstrap**: `novac-1` compiles Nova source to `novac-2`.
- [x] **M10.5 Stage 3 Fixed-Point Verification**: SHA-256 match between `novac-2` and `novac-3` (`26e714452ca569d26d8d5757f8a12d95222ae1f48de4a8c01b4d2da6787cd6ac`). Retirement of Haskell genesis compiler.

### Stage 11: Tooling & Release Hardening
- [x] **M11.1 Package Manager (`orbit`)**: Dependency resolution, package registry, and capability audit (`bin/orbit`).
- [x] **M11.2 Language Server Protocol (`nova-lsp`)**: IDE integration for VS Code and Neovim (`bin/nova-lsp`).
- [x] **M11.3 Formatting & Linting (`nova-fmt`, `nova-lint`)**: Code formatting and capability linting (`bin/nova-fmt`, `bin/nova-lint`).
- [x] **M11.4 Compiler Fuzzing**: Grammar-based mutation fuzz testing (`tests/fuzz.sh`).
- [x] **M11.5 Standard Test Suite & Benchmarks**: Complete verification suite and latency benchmarks (`tests/run_all.sh`, `benchmarks/run_benchmarks.sh`).
- [x] **M11.6 Distribution Packaging**: Standalone installer toolchains for Linux and macOS (`install.sh`).
