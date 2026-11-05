# Bảng Từ Khóa Cốt Lõi (Nova Core Keywords Specification)

Nova tuân thủ triết lý tối giản nhận thức: **tổng số từ khóa nhỏ hơn 25**. Mọi cấu trúc phức tạp đều được suy diễn hoặc khử đường cú pháp (desugared) về tập từ khóa nguyên thủy này.

---

## 🔑 Danh sách 24 Từ khóa Cốt lõi (Core Keywords)

| STT | Từ khóa | Mục đích sử dụng | Ví dụ |
| :--- | :--- | :--- | :--- |
| 1 | `fn` | Khai báo hàm hoặc thủ tục | `fn add(a: Int, b: Int) -> Int:` |
| 2 | `let` | Khai báo biến (mặc định là immutable) | `let x = 42` |
| 3 | `mut` | Đánh dấu biến có thể thay đổi giá trị | `let mut counter = 0` |
| 4 | `type` | Khai báo kiểu (Struct, Enum, Alias, Refinement) | `type Point = struct { x: Float, y: Float }` |
| 5 | `match` | So khớp mẫu vét cạn (Exhaustive Pattern Matching) | `match opt: Some(v) => v, None => 0` |
| 6 | `where` | Gắn mệnh đề logic kiểm chứng (Refinement Type) | `type NonZero = x: Int where x != 0` |
| 7 | `if` | Rẽ nhánh điều kiện | `if x > 0:` |
| 8 | `else` | Nhánh rẽ phụ khi điều kiện `if` sai | `else:` |
| 9 | `for` | Vòng lặp duyệt phần tử (desugars to iterator) | `for item in items:` |
| 10 | `while` | Vòng lặp điều kiện | `while is_running:` |
| 11 | `return` | Trả về giá trị từ hàm | `return a + b` |
| 12 | `break` | Thoát khỏi vòng lặp sớm | `break` |
| 13 | `continue`| Bỏ qua vòng lặp hiện tại | `continue` |
| 14 | `pub` | Đánh dấu thực thể công khai ra ngoài module | `pub fn api_call():` |
| 15 | `import` | Nạp module hoặc gói ngoại vi | `import std.io` |
| 16 | `as` | Đổi tên định danh khi import hoặc ép kiểu an toàn | `import std.io as sys_io` |
| 17 | `trait` | Định nghĩa giao diện hành vi (Typeclass/Trait) | `trait Show:` |
| 18 | `impl` | Cài đặt hành vi cho một kiểu | `impl Show for Point:` |
| 19 | `unsafe` | Mở khối thao tác phần cứng cấp thấp | `unsafe(cap): ...` |
| 20 | `cap` | Khai báo quyền hạn (Capability Token) | `cap NetCap, FsCap` |
| 21 | `region` | Tạo phạm vi vùng nhớ tường minh (Explicit Arena) | `region r:` |
| 22 | `iso` | Quyền sở hữu cô lập (Concurrency: Isolated) | `let msg: iso Message = Message()` |
| 23 | `val` | Quyền đọc bất biến toàn cục (Concurrency: Value) | `let config: val Config = load()` |
| 24 | `ref` | Quyền tham chiếu cục bộ luồng (Concurrency: Reference)| `let buffer: ref Buffer = get_buf()` |

---

## 🚫 Những từ khóa BỊ LOẠI BỎ khỏi Nova và Lý do

1. **`null` / `nil` / `undefined`**: Bị loại bỏ hoàn toàn. Thay thế bằng `Option[T] = Some(T) | None`.
2. **`try` / `catch` / `throw`**: Bị loại bỏ. Lỗi trong Nova là giá trị trả về tường minh `Result[T, E] = Ok(T) | Err(E)`.
3. **`goto`**: Không hỗ trợ.
4. **`class` / `inheritance`**: Không hỗ trợ kế thừa lớp (OOP inheritance). Dùng Composition (`struct`) + Polymorphism (`trait` / `impl`).
5. **`lifetime` (`'a`)**: Trình biên dịch tự phân tích Region qua đồ thị sống của biến; lập trình viên không bao giờ cần khai báo lifetime.
