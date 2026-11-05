# Nova Programming Language: Master Roadmap (12 Stages, 60 Milestones)

## 🌌 Triết lý thiết kế (Design Philosophy)
- **Dễ viết như Python**: Indentation-sensitive, bidirectional type inference, không lifetime `'a`, cú pháp tối giản < 25 từ khóa.
- **An toàn hơn Rust**: Refinement Types (Z3 SMT), Reference Capabilities + Session Types (không data race, không deadlock), Capability-gated Unsafe.
- **Nhanh ngang C/C++**: Zero-GC, Perceus Reference Counting (tái sử dụng bộ nhớ tại chỗ), LLVM backend, Bounds-check elimination.

---

## 🧬 Ma trận Tiến hóa Trình biên dịch (Bootstrapping Matrix)

| Đời (Stage) | Mã nguồn viết bằng | Biên dịch bởi | Đầu ra (Output) | Mục đích cốt lõi |
| :--- | :--- | :--- | :--- | :--- |
| **Stage 0** | Haskell (GHC) | `ghc` | `novac-0` (Binary) | Trình biên dịch mồi khởi thủy (Genesis Compiler). |
| **Stage 1** | Nova | `novac-0` | `novac-1` (Binary) | Trình biên dịch Nova đầu tiên tự viết bằng chính Nova. |
| **Stage 2** | Nova | `novac-1` | `novac-2` (Binary) | Dùng bản dịch của Nova để tự biên dịch lại mã nguồn của nó. |
| **Stage 3** | Nova | `novac-2` | `novac-3` (Binary) | Kiểm chứng điểm bất động: mã nhị phân `novac-2` và `novac-3` khớp 100% (SHA-256). |

---

## 🗺️ Lộ trình 12 Giai đoạn (60 Cột mốc)

### Giai đoạn 0: Đặc tả Hình thức & Kiến trúc Lõi (Formal Specification)
- [ ] **M0.1 Định nghĩa ngữ pháp EBNF**: Chốt bộ quy tắc cú pháp không nhập nhằng (unambiguous grammar), ưu tiên thụt lề (indentation-sensitive) kết hợp từ khóa tự nhiên.
- [ ] **M0.2 Thiết kế hệ thống từ khóa tối giản**: Chốt dưới 25 từ khóa cốt lõi (`fn`, `let`, `mut`, `type`, `match`, `where`, `unsafe`, `cap`, `region`, `pub`, `return`, ...).
- [ ] **M0.3 Đặc tả mô hình bộ nhớ (Memory Model)**: Cơ chế lai giữa Region-based Memory Management và Perceus Reference Counting.
- [ ] **M0.4 Đặc tả hệ thống kiểu (Type Rules)**: Viết quy tắc suy diễn kiểu theo ký hiệu toán học (Typing Judgments) trước khi code.
- [ ] **M0.5 Quy hoạch hệ thống Báo lỗi (Diagnostic Spec)**: Thiết kế khung thông báo lỗi tiếng người: dòng, cột, nguyên nhân gốc, gợi ý sửa tự động.

### Giai đoạn 1: Frontend Stage 0 bằng Haskell (Lexing & Parsing)
- [ ] **M1.1 Khởi tạo dự án Haskell**: Dựng cấu trúc bằng Cabal, module hóa: `Syntax`, `Parser`, `Typecheck`, `HIR`, `Codegen`.
- [ ] **M1.2 Bộ đọc mã nguồn (Source Loader)**: Đọc UTF-8 hoàn chỉnh, đánh số `Span` / `SourceLoc` gắn vào từng ký tự.
- [ ] **M1.3 Xây dựng Indentation Lexer**: Dùng Megaparsec chuyển khoảng trắng đầu dòng thành các token ảo `INDENT`, `DEDENT`, `NEWLINE`.
- [ ] **M1.4 Định nghĩa Cây cú pháp Bề mặt (Surface AST)**: ADT của Haskell mô hình hóa toàn bộ biểu thức, câu lệnh và kiểu.
- [ ] **M1.5 Xây dựng Parser**: Megaparsec kết hợp Pratt Parsing xử lý độ ưu tiên toán tử mượt mà $O(n)$.
- [ ] **M1.6 Cơ chế Phục hồi Lỗi Cú pháp (Error Recovery)**: Gom toàn bộ lỗi cú pháp trong file báo một lần.

### Giai đoạn 2: Hạ cấp Cú pháp & Biểu diễn Trung gian Cao (AST → HIR)
- [ ] **M2.1 Khử đường cú pháp (Desugaring)**: Chuyển cú pháp viết tắt (`for`, chuỗi nội suy, toán tử `?`) về cấu trúc nguyên thủy.
- [ ] **M2.2 Phân giải Tên & Phạm vi (Name Resolution)**: Duyệt AST gắn tên biến/hàm với định danh duy nhất (`DefId`).
- [ ] **M2.3 Kiểm tra Chu trình Module (Import Cycle Detection)**: Dùng thuật toán đồ thị Tarjan chặn import vòng tròn.
- [ ] **M2.4 Sinh HIR (High-Level IR)**: Chuyển Surface AST thành cây HIR đã chuẩn hóa.
- [ ] **M2.5 Hệ thống Macro Vệ sinh (Hygienic AST Macros)**: Mở rộng cú pháp an toàn lúc biên dịch.

### Giai đoạn 3: Hệ thống Kiểu Tĩnh Cốt lõi (Core Type Engine)
- [ ] **M3.1 Suy luận kiểu hai chiều (Bidirectional Type Inference)**: Kết hợp Hindley-Milner với kiểm tra kiểu hai chiều.
- [ ] **M3.2 Kiểu dữ liệu Đại số (Sum & Product Types)**: Hỗ trợ `struct` và `enum` mang dữ liệu, loại bỏ `null` (dùng `Option[T]`).
- [ ] **M3.3 Kiểm tra Vét cạn Mẫu (Exhaustiveness Checking)**: Đảm bảo mọi khối `match` xử lý đủ 100% trường hợp dữ liệu.
- [ ] **M3.4 Hệ thống Đa hình & Ràng buộc (Generics & Traits)**: Tự động đơn hình hóa (monomorphization) lúc dịch.
- [ ] **M3.5 Xử lý lỗi bằng Giá trị (Value-based Error Handling)**: Tích hợp `Result[T, E]`, loại bỏ `try/catch`.

### Giai đoạn 4: Động cơ Chứng minh Logic — "An toàn hơn Rust" Tập 1 (Refinement Types)
- [ ] **M4.1 Cú pháp Kiểu Tinh chỉnh (Refinement Syntax)**: Gắn mệnh đề logic trực tiếp vào kiểu (`type NonZero = x: Int where x != 0`).
- [ ] **M4.2 Sinh Điều kiện Kiểm chứng (Verification Condition Generation - VCG)**: Biến ràng buộc thành công thức logic toán học.
- [ ] **M4.3 Tích hợp Bộ giải SMT (Z3 Solver Binding)**: Kết nối trình biên dịch Haskell với Microsoft Z3.
- [ ] **M4.4 Loại bỏ Lỗi Chia cho 0 & Tràn Mảng lúc Biên dịch**: Ép mẫu số `NonZero`, truy cập mảng $0 \le i < \text{len}(arr)$.
- [ ] **M4.5 Kiểm chứng chống Tràn số học (Overflow Verification)**: Chứng minh phép tính không vượt giới hạn bit CPU.

### Giai đoạn 5: Quản lý Bộ nhớ Vùng & Khóa Phân quyền — "An toàn hơn Rust" Tập 2
- [ ] **M5.1 Suy luận Vùng nhớ Tự động (Automatic Region Inference)**: Phân tích đồ thị sống, gom biến vào Regions/Arenas không cần `'a`.
- [ ] **M5.2 Giải cứu Cấu trúc Tự tham chiếu (Safe Graphs & Doubly Linked Lists)**: Cho phép tạo đồ thị an toàn qua Typed Region Indices.
- [ ] **M5.3 Cơ chế Perceus (Compile-time Reuse Analysis)**: Thu hồi và tái sử dụng ô nhớ tại chỗ, tốc độ ngang C thuần.
- [ ] **M5.4 Thiết kế unsafe dựa trên Quyền hạn (Capability-gated Unsafe)**: Hàm unsafe phải nhận tham số `cap: UnsafeHardwareCap`.
- [ ] **M5.5 Kiểm toán Khối unsafe (Unsafe Auditing)**: Xuất báo cáo dòng/thư viện nào đang giữ quyền unsafe.

### Giai đoạn 6: Đa luồng Không Deadlock — "An toàn hơn Rust" Tập 3 (Concurrency)
- [ ] **M6.1 Hệ thống Quyền Truy cập Dữ liệu (Reference Capabilities)**: Phân loại biến thành `iso`, `val`, `ref`.
- [ ] **M6.2 Triệt tiêu Data Race từ Gốc**: Chặn 2 luồng cùng giữ quyền ghi ngay ở bước kiểm tra kiểu.
- [ ] **M6.3 Tích hợp Session Types cho Kênh giao tiếp (Channels)**: Ràng buộc giao thức trạng thái trên kênh truyền.
- [ ] **M6.4 Phát hiện Deadlock lúc Biên dịch (Lock-Order & Protocol Verification)**: Phân tích đồ thị chờ và thứ tự khóa, chặn circular wait.

### Giai đoạn 7: Biểu diễn Trung gian Cấp thấp & Tối ưu hóa (HIR → MIR)
- [ ] **M7.1 Chuyển đổi sang Đồ thị Luồng Điều khiển (Control Flow Graph - MIR)**: Đưa code về Basic Blocks & SSA form.
- [ ] **M7.2 Phân tích Khởi tạo Biến (Definite Initialization Analysis)**: Đảm bảo không đọc biến trước khi gán.
- [ ] **M7.3 Tối ưu hóa cấp độ MIR**: Constant Folding, Dead Code Elimination, Function Inlining.
- [ ] **M7.4 Chèn lệnh Giải phóng Bộ nhớ Tĩnh (Drop Insertion)**: Tính toán vị trí chính xác trên CFG để thu hồi vùng nhớ.
- [ ] **M7.5 Xóa bỏ Kiểm tra Dư thừa (Bounds Check Elimination)**: Gỡ bỏ kiểm tra runtime ở các vị trí Z3 đã chứng minh an toàn.

### Giai đoạn 8: Backend Sinh Mã Máy & Tối ưu Phần cứng (MIR → LLVM / C)
- [ ] **M8.1 Xây dựng C-Transpiler Backend**: Dịch MIR ra C99 chuẩn để biên dịch qua GCC/Clang.
- [ ] **M8.2 Tích hợp LLVM Backend (llvm-hs)**: Dịch MIR sang LLVM IR để hưởng tối ưu hóa `-O3`.
- [ ] **M8.3 Thiết lập ABI & Giao tiếp Ngoại ngữ (Zero-cost C FFI)**: Gọi trực tiếp thư viện C/C++.
- [ ] **M8.4 Tối ưu hóa Vector hóa Tự động (SIMD Auto-Vectorization)**: Đánh dấu `noalias`, đẩy tính toán vào AVX-512/NEON.
- [ ] **M8.5 Sinh Thông tin Gỡ lỗi (DWARF / PDB Debug Info)**: Nhúng metadata để debug bằng gdb/lldb.

### Giai đoạn 9: Hệ thống Thực thi & Thư viện Chuẩn (Runtime & Stdlib)
- [ ] **M9.1 Viết nova-rt (Minimal Runtime)**: Lớp đệm mỏng (<2000 dòng) quản lý cấp phát bộ nhớ (mimalloc) và tiến trình.
- [ ] **M9.2 Thư viện core**: Kiểu nguyên thủy, math, slice, string tĩnh, chạy được no_std/embedded.
- [ ] **M9.3 Thư viện std**: `Vec`, `Map`, `Set`, `String` UTF-8, IO File, TCP/UDP.
- [ ] **M9.4 Bộ lập lịch Đa luồng Nhẹ (M:N Work-Stealing Scheduler)**: Green Threads chạy hàng triệu tác vụ đồng thời.

### Giai đoạn 10: Chiến dịch Tự Nuôi (Self-Hosting Bootstrap)
- [ ] **M10.1 Viết lại Lexer & Parser bằng Nova**: Chuyển logic phân tích cú pháp sang mã nguồn Nova.
- [ ] **M10.2 Viết lại Typechecker, SMT Bridge & MIR bằng Nova**.
- [ ] **M10.3 Biên dịch Stage 1**: `novac-0` (Haskell) dịch mã Nova → `novac-1`.
- [ ] **M10.4 Biên dịch Stage 2**: `novac-1` tự dịch lại mã Nova → `novac-2`.
- [ ] **M10.5 Kiểm định Điểm Bất Động (Stage 3 Fixed-Point Test)**: `novac-2` dịch mã Nova → `novac-3`. So sánh SHA-256 (`novac-2` == `novac-3`).

### Giai đoạn 11: Hệ sinh thái, Công cụ & Kiểm thử Cực hạn (Tooling & Hardening)
- [ ] **M11.1 Trình quản lý Gói & Build (orbit)**: Quản lý dependency, audit quyền unsafe (`orbit audit`).
- [ ] **M11.2 Language Server Protocol (nova-lsp)**: Autocomplete, go-to-definition, real-time diagnostics.
- [ ] **M11.3 Công cụ Định dạng & Phân tích Tĩnh (nova-fmt & nova-lint)**.
- [ ] **M11.4 Kiểm thử Đột biến & Fuzzing (Compiler Fuzzing)**.
- [ ] **M11.5 Bộ Kiểm thử Chuẩn (Test Suite & Benchmarks)**: 10.000+ tests đối đầu C++, Rust, Go.
- [ ] **M11.6 Đóng gói Phát hành (Nova 1.0 Toolchain)**.
