# TICKET 028 — Sửa lỗi Ví thanh toán & Danh mục bị xóa trắng ngay khi mở màn Sửa giao dịch

**Loại:** Bug fix (mất dữ liệu hiển thị — không phải thiếu tính năng)
**Độ ưu tiên:** Cao
**File bị ảnh hưởng:** `lib/screens/home/add_transaction_screen.dart`

---

## 1. Context (Bối cảnh)

Mở màn Sửa 1 giao dịch đã có đủ dữ liệu (Ví, Danh mục, Ghi chú, Địa điểm, Ngày) → **Số tiền, Ghi chú, Địa điểm, Ngày hiện đúng dữ liệu cũ**, nhưng **Ví thanh toán và Danh mục luôn hiện trống**, buộc người dùng phải tự chọn lại từ đầu dù giao dịch gốc đã có sẵn 2 thông tin này.

## 2. Root Cause (Nguyên nhân gốc — không phải thiếu code gán giá trị)

`initState()` **đã gán đúng** giá trị ban đầu từ giao dịch gốc:
```dart
if (widget.transactionToEdit != null) {
  final tx = widget.transactionToEdit!;
  ...
  _selectedWalletId = tx.walletId.isNotEmpty ? tx.walletId : null;
  _selectedCategoryId = tx.categoryId.isNotEmpty ? tx.categoryId : null;
  ...
}
```
Vấn đề nằm ở đoạn "dọn dẹp lựa chọn không hợp lệ" bên trong 2 `StreamBuilder` (Ví và Danh mục) — đoạn này vốn được thiết kế để tự động bỏ chọn nếu ví/danh mục đã bị **xóa thật** ở nơi khác (đúng mục đích ban đầu), nhưng lại chạy **cả trong lần build đầu tiên khi stream chưa kịp trả dữ liệu**:

```dart
StreamBuilder<List<Wallet>>(
  stream: _firestoreService.streamWallets(uid),
  builder: (context, snap) {
    final wallets = snap.data ?? [];   // ⚠️ lần build đầu: snap.data == null → wallets = []
    if (_selectedWalletId != null && !wallets.any((w) => w.walletId == _selectedWalletId)) {
      _selectedWalletId = null;        // ⚠️ danh sách RỖNG vì CHƯA TẢI XONG, không phải vì ví không tồn tại
    }
    ...
```
Cùng lỗi y hệt xảy ra ở `StreamBuilder<List<Category>>` với `allCategories`.

**Trình tự lỗi xảy ra:**
1. Mở màn Sửa → `initState` gán đúng `_selectedWalletId`/`_selectedCategoryId`.
2. Flutter build lần đầu → `StreamBuilder` chưa có snapshot dữ liệu (`snap.data == null`) → `wallets`/`allCategories` tạm thời là **danh sách rỗng**.
3. Điều kiện "không tìm thấy trong danh sách" bị đánh giá `true` (vì danh sách rỗng, chưa phải vì ví/danh mục không tồn tại) → `_selectedWalletId`/`_selectedCategoryId` bị set về `null` **ngay trong build method** (không qua `setState`, nhưng biến state đã bị mutate vĩnh viễn).
4. Vài mili-giây sau, stream trả dữ liệu thật → `StreamBuilder` build lại → nhưng lúc này `_selectedWalletId`/`_selectedCategoryId` **đã là `null` từ bước 3**, không còn cách nào khôi phục lại giá trị cũ.

Đây là race condition **cùng bản chất** với bug đã fix ở ticket 004 (chọn lựa hợp lệ bị xóa nhầm do đánh giá sai thời điểm dữ liệu chưa sẵn sàng), nhưng lần này nguyên nhân là **khoảng trễ tải dữ liệu ban đầu của `StreamBuilder`**, không phải do đổi `_type` tạo stream mới.

## 3. Fix Requirements

Chỉ chạy đoạn "dọn lựa chọn không hợp lệ" **sau khi** `StreamBuilder` đã thực sự có dữ liệu (`snap.hasData == true`), không chạy khi còn đang ở trạng thái tải lần đầu:

**Dropdown Ví thanh toán:**
```dart
StreamBuilder<List<Wallet>>(
  stream: _firestoreService.streamWallets(uid),
  builder: (context, snap) {
    if (snap.hasError) return StreamErrorWidget(error: snap.error.toString());
    final wallets = snap.data ?? [];

    // Chỉ dọn lựa chọn không hợp lệ SAU KHI đã có dữ liệu thật — danh sách
    // rỗng lúc stream CHƯA tải xong không có nghĩa ví đã bị xóa.
    if (snap.hasData &&
        _selectedWalletId != null &&
        !wallets.any((w) => w.walletId == _selectedWalletId)) {
      _selectedWalletId = null;
    }

    return DropdownButtonFormField<String>(
      value: _selectedWalletId,
      ...
```

**Dropdown Danh mục:**
```dart
StreamBuilder<List<Category>>(
  stream: _firestoreService.streamCategories(uid),
  builder: (context, snap) {
    if (snap.hasError) return StreamErrorWidget(error: snap.error.toString());
    final allCategories = snap.data ?? [];
    final categories = allCategories.where((c) => c.type == _type).toList();

    if (snap.hasData &&
        _selectedCategoryId != null &&
        !allCategories.any((c) => c.categoryId == _selectedCategoryId)) {
      _selectedCategoryId = null;
    }

    return DropdownButtonFormField<String>(
      value: categories.any((c) => c.categoryId == _selectedCategoryId) ? _selectedCategoryId : null,
      ...
```

**Chỉ thêm đúng 1 điều kiện `snap.hasData &&` vào 2 vị trí trên** — không đổi bất kỳ logic nào khác trong 2 khối `StreamBuilder` này (giữ nguyên cách lọc `categories` theo `_type`, giữ nguyên cách hiển thị `items`).

## 4. Không đổi (Out of scope)

- Không đổi `initState()` — phần gán giá trị ban đầu từ `transactionToEdit` đã đúng, không cần sửa.
- Không đổi logic "dọn lựa chọn không hợp lệ" khi ví/danh mục **thật sự** bị xóa sau khi màn Sửa đã mở (VD người dùng khác/tab khác xóa ví đang chọn trong lúc đang sửa) — hành vi này vẫn đúng và cần giữ, chỉ thêm điều kiện chặn trường hợp "chưa tải xong" bị hiểu nhầm thành "không tồn tại".
- Không đụng tới Ticket 027 Phần B (lỗi mất dữ liệu khi bấm nút loại giao dịch Chi tiêu/Thu nhập trong màn Sửa) — đây là 2 bug khác nhau, cùng nằm trong `add_transaction_screen.dart` nhưng độc lập, không gộp chung 1 lần sửa để dễ kiểm tra riêng từng bug.
- Không đổi `FirestoreService.streamWallets()`/`streamCategories()`.

## 5. Acceptance Criteria

- [ ] Mở Sửa 1 giao dịch có đủ Ví + Danh mục → **ngay khi màn hình vừa mở, chưa cần tương tác gì** → cả 2 dropdown đã hiện đúng đúng Ví và Danh mục cũ, không còn trống.
- [ ] Test với mạng chậm (throttle network trong DevTools hoặc thiết bị thật ở vùng sóng yếu) — trường hợp dễ lộ race condition nhất vì khoảng trễ tải dữ liệu dài hơn — vẫn phải hiện đúng Ví/Danh mục cũ, không bị trống dù tải chậm.
- [ ] Test 1 giao dịch mà Ví hoặc Danh mục gốc **đã bị xóa thật** trước đó (từ màn Quản lý ví/danh mục) → mở Sửa giao dịch này → dropdown tương ứng vẫn tự động về trống đúng như thiết kế cũ (không phá vỡ hành vi dọn dẹp hợp lệ này).
- [ ] Màn **Thêm giao dịch mới** (`transactionToEdit == null`) không bị ảnh hưởng — hành vi dropdown khi tạo mới giữ nguyên như cũ.
- [ ] `flutter analyze` không phát sinh lỗi/warning mới.
