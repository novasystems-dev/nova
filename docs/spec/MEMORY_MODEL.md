# Mô Hình Bộ Nhớ Nova (Nova Memory Model: Region + Perceus)

Nova loại bỏ hoàn toàn Trình thu gom rác (Garbage Collector - GC) và không bắt lập trình viên phải chú thích vòng đời biến (`'a`, `'b` lifetime) như Rust.

Mô hình bộ nhớ Nova được xây dựng dựa trên 2 trụ cột toán học vững chắc:
1. **Automatic Region Inference (Hệ thống suy luận vùng sống)**
2. **Perceus Precise Reference Counting with In-Place Reuse (Tái sử dụng bộ nhớ tại chỗ)**

---

## 1. Automatic Region Inference (Suy luận Vùng nhớ Tự động)

### Nguyên lý hoạt động
Mỗi giá trị được cấp phát trong Nova đều thuộc về một **Region (Vùng nhớ)**. Trình biên dịch phân tích đồ thị luồng điều khiển (Control Flow Graph - CFG) và đồ thị sống (Liveness Analysis) để xác định điểm đầu và điểm cuối của từng đối tượng:

- **Stack Promotion**: Nếu một đối tượng không thoát khỏi phạm vi hàm (no escape), nó tự động được cấp phát trên Call Stack của CPU (chi phí cấp phát = 0).
- **Region Bulk Deallocation**: Các đối tượng thuộc cùng một chu kỳ tính toán (ví dụ: một chu kỳ vòng lặp, một request mạng) được gom vào chung một Vùng (Arena). Khi phạm vi kết thúc, toàn bộ Vùng được giải phóng đồng loạt chỉ bằng một thao tác điều chỉnh con trỏ, triệt tiêu phân mảnh bộ nhớ.
- **Typed Region Indices**: Để giải quyết bài toán Đồ thị (Graph) hoặc Danh sách liên kết hai chiều (Doubly Linked List), Nova cho phép định nghĩa các chỉ mục có kiểm tra kiểu trỏ vào Region an toàn 100% mà không sợ Use-After-Free hay Dangling Pointers.

---

## 2. Cơ chế Perceus (In-Place Memory Reuse)

Kế thừa công trình nghiên cứu đột phá của Microsoft Research (trên ngôn ngữ Koka), Nova triển khai **Perceus RC**:

### Tái sử dụng ô nhớ tại chỗ (In-Place Reuse)
Khi một cấu trúc dữ liệu bị sửa đổi (ví dụ: cập nhật một nút trong cây nhị phân hoặc chèn phần tử vào mảng):
1. Trình biên dịch kiểm tra tĩnh số lượng tham chiếu: nếu tại thời điểm đó đối tượng chỉ có duy nhất 1 tham chiếu (Uniquely Referenced - RC == 1).
2. Thay vì cấp phát một nút mới và xóa nút cũ (tốn 2 lần gọi allocator `malloc`/`free`), Nova **ghi đè trực tiếp lên chính ô nhớ của nút cũ**.
3. Hiệu năng đạt mức tương đương với code C thuần (In-place mutation) trong khi mã nguồn vẫn giữ được tính chất thuần khiết hàm (Functional Purity).

---

## 3. Phân cấp Quyền hạn Concurrency (Reference Capabilities)

Để đảm bảo không bao giờ có **Data Race** giữa các luồng:

- **`iso` (Isolated)**: Đối tượng chỉ có duy nhất một con trỏ trỏ tới trên toàn hệ thống. Có thể chuyển giao quyền sở hữu (Send) giữa các luồng mà không cần khóa (lock-free).
- **`val` (Value / Globally Immutable)**: Đối tượng bất biến vĩnh viễn. Nhiều luồng có thể cùng đọc đồng thời mà không sợ xung đột.
- **`ref` (Thread-Local Reference)**: Tham chiếu có thể đọc/ghi nhưng bị khóa chặt trong luồng cục bộ; trình biên dịch cấm chia sẻ `ref` sang luồng khác.

---

## 4. Capability-Gated Unsafe (Kiểm soát Unsafe bằng Khóa phân quyền)

Khác với Rust nơi bất kỳ lập trình viên nào cũng có thể gõ `unsafe { ... }` và có nguy cơ giấu mã độc/bug trong crate bên thứ ba, Nova áp dụng cơ chế:

```nova
# Hàm này KHÔNG THỂ được gọi nếu caller không có UnsafeHardwareCap
fn write_raw_mmio(cap: UnsafeHardwareCap, addr: UInt64, val: UInt32):
    unsafe(cap):
        # Truy cập phần cứng trực tiếp
        ...
```

Chỉ có hàm `main` được cấp quyền tối cao từ Runtime, và `main` phải truyền quyền này xuống một cách tường minh. Lệnh `orbit audit` sẽ quét và liệt kê chính xác các cây phân quyền unsafe trong toàn bộ dự án.
