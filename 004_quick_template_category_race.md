# TICKET 004 — Sửa race condition: chọn mẫu giao dịch làm mất lựa chọn Danh mục

**Loại:** Bug fix
**Độ ưu tiên:** Trung bình-Cao
**File bị ảnh hưởng:** `lib/screens/home/add_transaction_screen.dart`

---

## 1. Context (Bối cảnh)

Sau khi fix ticket 002, test thực tế phát hiện: khi bấm chọn 1 mẫu giao dịch (quick template) mà loại giao dịch của mẫu (`tmpl.type`) **khác** với loại đang chọn hiện tại trên form (VD form đang ở "Chi tiêu", mẫu là "Thu nhập" — Lương), thì **chỉ có Ví/Ghi chú/Địa điểm được điền đúng, riêng Danh mục bị reset về rỗng**. Phải bấm lại mẫu đó lần thứ 2 thì Danh mục mới điền đúng.

## 2. Root Cause (Nguyên nhân gốc)

Dropdown Danh mục lấy dữ liệu qua:
```dart
StreamBuilder<List<Category>>(
  stream: _firestoreService.streamCategories(uid, type: _type),
  builder: (context, snap) {
    final categories = snap.data ?? [];
    if (_selectedCategoryId != null && !categories.any((c) => c.categoryId == _selectedCategoryId)) {
      _selectedCategoryId = null;
    }
    ...
  },
)
```

Khi `onSelect` của template thay đổi **đồng thời** `_type` và `_selectedCategoryId` trong cùng 1 `setState`, việc đổi `_type` khiến biểu thức `_firestoreService.streamCategories(uid, type: _type)` tạo ra **một Stream Firestore hoàn toàn mới** (khác instance với stream cũ). Flutter's `StreamBuilder` phát hiện stream thay đổi → hủy đăng ký stream cũ, đăng ký stream mới, và trong khoảnh khắc chờ dữ liệu đầu tiên từ stream mới, `snap.data` tạm thời là danh sách rỗng hoặc dữ liệu cũ (loại giao dịch trước đó). Đúng lúc này, đoạn code "tự dọn lựa chọn không hợp lệ" (`if (... !categories.any(...)) _selectedCategoryId = null;`) chạy với danh sách sai (rỗng/cũ), thấy category vừa chọn "không có trong danh sách" → tự ý xóa về `null`. Khi stream mới thực sự có dữ liệu (khung hình sau), `_selectedCategoryId` đã bị xóa mất, không tự khôi phục lại — cần người dùng thao tác lại (bấm mẫu lần 2) để giá trị mới "dính" đúng.

## 3. Fix Requirements (Yêu cầu sửa)

Bỏ tham số `type` khỏi query Firestore cho danh mục — lấy **toàn bộ** danh mục của user 1 lần duy nhất (không phụ thuộc `_type`), lọc theo loại giao dịch **ở phía client** khi build danh sách hiển thị. Việc này loại bỏ hoàn toàn race condition vì thay đổi `_type` không còn kéo theo việc tạo stream Firestore mới.

Thay khối `StreamBuilder<List<Category>>` hiện tại bằng:
```dart
StreamBuilder<List<Category>>(
  stream: _firestoreService.streamCategories(uid), // Không truyền `type` — lấy toàn bộ 1 lần
  builder: (context, snap) {
    if (snap.hasError) return StreamErrorWidget(error: snap.error.toString());
    final allCategories = snap.data ?? [];
    // Lọc hiển thị theo loại giao dịch hiện tại — thao tác thuần client-side, không có async gap
    final categories = allCategories.where((c) => c.type == _type).toList();

    // Kiểm tra tồn tại dựa trên TOÀN BỘ danh mục (không phụ thuộc _type),
    // để đổi _type không làm mất lựa chọn hợp lệ đang có
    if (_selectedCategoryId != null &&
        !allCategories.any((c) => c.categoryId == _selectedCategoryId)) {
      _selectedCategoryId = null;
    }

    return DropdownButtonFormField<String>(
      value: _selectedCategoryId,
      decoration: const InputDecoration(labelText: 'Danh mục', prefixIcon: Icon(Icons.category_outlined)),
      items: categories.map((c) => DropdownMenuItem(value: c.categoryId, child: Text(c.name))).toList(),
      onChanged: (v) async {
        setState(() => _selectedCategoryId = v);
        await _runValidation();
      },
    );
  },
),
```

**Điểm mấu chốt:** điều kiện kiểm tra tồn tại (`!allCategories.any(...)`) dùng `allCategories` (chưa lọc theo `_type`), còn danh sách hiển thị trong dropdown (`items:`) dùng `categories` (đã lọc theo `_type`) — tách biệt 2 việc này để việc đổi `_type` không còn ảnh hưởng tới logic bảo vệ lựa chọn hợp lệ.

## 4. Không đổi (Out of scope)

- Không đổi `FirestoreService.streamCategories()` — hàm này đã hỗ trợ sẵn gọi không truyền `type` (tham số optional).
- Không đổi dropdown Ví (không có bug tương tự vì Ví không phụ thuộc `_type`).
- Không đổi `_typeToggleButton()` (vẫn giữ nguyên hành vi set `_selectedCategoryId = null` khi người dùng **tự tay** đổi tab Chi tiêu/Thu nhập — đây là hành vi đúng, khác với trường hợp chọn template).

## 5. Acceptance Criteria (Tiêu chí hoàn thành)

- [ ] Form đang ở "Chi tiêu" → bấm mẫu "Lương" (Thu nhập) → chỉ 1 lần bấm, cả Ví/Danh mục/Ghi chú/Địa điểm điền đúng ngay, không cần bấm lại lần 2.
- [ ] Ngược lại: form đang ở "Thu nhập" → bấm mẫu Chi tiêu → tương tự, điền đúng ngay 1 lần.
- [ ] Đổi tab Chi tiêu ⇄ Thu nhập bằng tay (không qua template) vẫn reset Danh mục về trống như hành vi cũ (không bị ảnh hưởng bởi fix này).
- [ ] Test tối thiểu 2 mẫu khác loại nhau (1 mẫu income, 1 mẫu expense), mỗi mẫu bấm ít nhất 2 lần độc lập để chắc chắn không phải ăn may.
