# TICKET 027 — Nhấn giữ để xóa/ẩn ví & Sửa lỗi mất dữ liệu khi đổi loại giao dịch trong màn Sửa

**Loại:** Bug fix + Cải tiến UX
**Độ ưu tiên:** Cao (Phần B là lỗi mất dữ liệu người dùng)
**File bị ảnh hưởng:** `lib/screens/management/wallet_management_screen.dart`, `lib/screens/home/add_transaction_screen.dart`

---

## PHẦN A — Xóa/Ẩn ví bằng nhấn giữ (thay cho vuốt)

### Context

Sau ticket 026, `wallet_management_screen.dart` xử lý xóa ví qua `Dismissible` (vuốt). Yêu cầu đổi sang **nhấn giữ (long-press)**, theo đúng pattern đã có ở `category_management_screen.dart` (`GestureDetector.onLongPress` → `AlertDialog` xác nhận), để nhất quán thao tác xóa giữa Danh mục và Ví trong toàn app — đặc biệt sau khi card ví được redesign có thêm progress bar, thao tác vuốt dễ bị che khuất/kém trực quan hơn.

### Fix Requirements

1. Đọc lại đúng cấu trúc `_buildCategoryList()` trong `category_management_screen.dart` (đoạn `onLongPress` xử lý `checkCategoryInUse` → dialog xác nhận / dialog chuyển & xóa) làm mẫu.
2. Áp dụng lại tương tự cho danh sách ví: bọc mỗi `WalletCard` bằng `GestureDetector` với `onLongPress`, **giữ nguyên toàn bộ logic nghiệp vụ đã có từ ticket 026** (`checkWalletInUse`, `setWalletActive` để "Ẩn ví", `reassignAndDeleteWallet` để "Chuyển & Xóa") — chỉ đổi cách kích hoạt từ vuốt (`Dismissible`) sang nhấn giữ, **không đổi logic bên trong các nhánh xử lý**.
3. Bỏ `Dismissible` bọc ngoài `WalletCard`, thay bằng `GestureDetector`.

### Không đổi (Out of scope)

- Không đổi nội dung/văn bản các dialog đã có.
- Không đổi `checkWalletInUse`/`setWalletActive`/`reassignAndDeleteWallet` ở `FirestoreService`.

### Acceptance Criteria

- [ ] Nhấn giữ 1 ví chưa có giao dịch → hiện dialog xác nhận xóa, xóa thành công.
- [ ] Nhấn giữ 1 ví đã có giao dịch → hiện dialog "Ẩn ví" / "Chuyển & Xóa" như logic ticket 026 đã làm.
- [ ] Test cụ thể trường hợp thực tế đã gặp: nhấn giữ ví "ZaloPay" đang có giao dịch 130.000đ → xác nhận đúng 2 lựa chọn hiện ra, không xóa nhầm mất lịch sử giao dịch.

---

## PHẦN B — Sửa lỗi mất dữ liệu khi chạm nút loại giao dịch trong màn Sửa

### Context

`_typeToggleButton()` được thiết kế ở ticket 007 để dọn sạch form khi người dùng tạo giao dịch mới và đổi tab Chi tiêu/Thu nhập — đây là hành vi đúng cho màn Thêm. Nhưng hàm này cũng đang được dùng chung cho màn Sửa giao dịch (`widget.transactionToEdit != null`), khiến việc chạm vào nút loại giao dịch trong lúc sửa (kể cả chạm nhầm vào nút đang active) xóa sạch toàn bộ dữ liệu đã điền sẵn từ giao dịch gốc.

### Root Cause

```dart
Widget _typeToggleButton(String label, String type, Color color) {
  final selected = _type == type;
  return ElevatedButton(
    onPressed: () => setState(() {
      _type = type;
      _selectedCategoryId = null;
      _selectedWalletId = null;
      _amountController.clear();
      _noteController.clear();
      _locationController.clear();
      _receiptImageBytes = null;
      _existingImagePath = null;
      ...
    }),
    ...
  );
}
```

`onPressed` luôn chạy toàn bộ đoạn dọn dẹp này bất kể đang ở màn Thêm hay Sửa, và bất kể loại giao dịch có thực sự thay đổi hay không.

### Fix Requirements

Sửa `_typeToggleButton()` để phân biệt 2 trường hợp:

- **Màn Thêm mới** (`widget.transactionToEdit == null`): giữ nguyên hành vi cũ — đổi loại thì dọn sạch form (đúng như ticket 007 đã chốt).
- **Màn Sửa** (`widget.transactionToEdit != null`): khi chạm nút loại giao dịch, **giữ nguyên** số tiền, ví, ghi chú, địa điểm, ảnh đã có — chỉ đổi `_type` và reset `_selectedCategoryId` về `null` (vì danh mục Thu/Chi là 2 danh sách khác nhau, không thể giữ nguyên danh mục cũ khi đổi loại), sau đó gọi lại `_runValidation()`.

**Gợi ý cấu trúc:**

```dart
onPressed: () async {
  setState(() {
    if (widget.transactionToEdit == null) {
      // Giữ nguyên logic dọn form cũ cho màn Thêm mới
      _type = type;
      _selectedCategoryId = null;
      _selectedWalletId = null;
      _amountController.clear();
      _noteController.clear();
      _locationController.clear();
      _receiptImageBytes = null;
      _existingImagePath = null;
      _walletBalanceExceeded = false;
      _budgetExceeded = false;
    } else {
      // Màn Sửa: chỉ đổi loại + reset danh mục, giữ nguyên toàn bộ dữ liệu còn lại
      _type = type;
      _selectedCategoryId = null;
    }
  });
  await _runValidation();
},
```

Đảm bảo `_runValidation()` vẫn được gọi lại sau khi đổi (kiểm tra xem `onPressed` hiện tại có `await _runValidation()` không — nếu không, cần thêm để nhất quán với các nơi khác trong file).

### Không đổi (Out of scope)

- Không đổi hành vi màn Thêm mới.
- Không đổi bất kỳ hàm nào khác trong file.

### Acceptance Criteria

- [ ] Mở sửa 1 giao dịch chi tiêu đã có đủ ví/danh mục/ghi chú/ảnh → chạm nút "Thu nhập" → toàn bộ số tiền/ví/ghi chú/ảnh vẫn còn nguyên, chỉ có Danh mục về trống (do đổi loại), người dùng tự chọn lại danh mục phù hợp rồi mới lưu.
- [ ] Chạm nhầm vào nút loại giao dịch đang active (VD đang sửa giao dịch Chi tiêu, chạm lại đúng nút "Chi tiêu") trong màn Sửa → không có gì bị mất, dữ liệu giữ nguyên 100%.
- [ ] Màn Thêm giao dịch mới vẫn giữ đúng hành vi cũ (đổi loại thì dọn sạch form) — không bị ảnh hưởng bởi thay đổi này.
