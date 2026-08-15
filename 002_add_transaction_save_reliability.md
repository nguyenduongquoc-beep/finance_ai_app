# TICKET 002 — Sửa lỗi luồng "Thêm giao dịch" không lưu được & mẫu giao dịch điền thiếu field

**Loại:** Bug fix (nghiêm trọng — chặn luồng chính của app)
**Độ ưu tiên:** Cao
**File bị ảnh hưởng:** `lib/screens/home/add_transaction_screen.dart`

---

## 1. Context (Bối cảnh)

Test trên thiết bị thật phát hiện 2 hiện tượng tưởng chừng không liên quan, nhưng **cùng chung 1 root cause**:

- **Hiện tượng A:** Nhập giao dịch **Thu nhập** (income), điền đầy đủ số tiền/ví/danh mục/ghi chú → nút "Lưu giao dịch" không bấm được (nút ở trạng thái disabled vĩnh viễn).
- **Hiện tượng B:** Nhập giao dịch **Chi tiêu** sau khi dùng camera chụp hóa đơn → OCR trích xuất thành công (điền được số tiền + ghi chú), nhưng khi bấm "Lưu giao dịch" thì báo lỗi không lưu được.
- **Hiện tượng C (bug độc lập, không liên quan A/B):** Bấm vào 1 "mẫu giao dịch" đã lưu trước đó (quick template) → chỉ điền đúng số tiền, các field khác (ví, danh mục, ghi chú, địa điểm) không được điền dù lúc lưu mẫu đã lưu đầy đủ các field này.

## 2. Root Cause (Nguyên nhân gốc)

### 2.1. Hiện tượng A + B: `_runValidation()` có 2 lỗi cấu trúc khiến `_isValidating` bị kẹt `true` vĩnh viễn

Code hiện tại:
```dart
Future<void> _runValidation() async {
  setState(() => _isValidating = true);
  final amount = AppFormatters.parseCurrencyInput(_amountController.text);

  if (_type == 'income') {
    setState(() {
      _walletBalanceExceeded = false;
      _budgetExceeded = false;
    });
    return; // ❌ BUG 1: return sớm, bỏ qua dòng setState(_isValidating=false) cuối hàm
  }

  if (_selectedWalletId != null) {
    final exceed = await ValidationUtils.exceedsWalletBalance(...); // ❌ BUG 2: không có try/catch
    setState(() => _walletBalanceExceeded = exceed);
  }
  if (_selectedCategoryId != null) {
    final exceed = await ValidationUtils.exceedsCategoryBudget(...);
    setState(() => _budgetExceeded = exceed);
  }
  setState(() => _isValidating = false); // chỉ chạy tới đây khi type == 'expense' VÀ không có exception
}
```

- **BUG 1** (gây hiện tượng A): với `_type == 'income'`, hàm `return` ngay sau khi set `_walletBalanceExceeded`/`_budgetExceeded`, **không bao giờ chạy tới dòng `setState(() => _isValidating = false)` ở cuối hàm** → `_isValidating` giữ nguyên `true` từ lúc đầu hàm, khóa nút Lưu vĩnh viễn cho mọi giao dịch Thu nhập.
- **BUG 2** (gây hiện tượng B): với `_type == 'expense'`, nếu `ValidationUtils.exceedsWalletBalance()` hoặc `exceedsCategoryBudget()` throw exception (lỗi mạng, timeout, lỗi Firestore...) — tình huống này **dễ xảy ra hơn trên thiết bị thật** so với môi trường dev quen thuộc — exception sẽ ném thẳng ra ngoài hàm `_runValidation()` mà không được bắt, khiến dòng `setState(() => _isValidating = false)` cuối hàm **không bao giờ chạy tới**, nút Lưu bị khóa vĩnh viễn y hệt hiện tượng A.

`_runValidation()` được gọi lại **mỗi khi** người dùng đổi số tiền, chọn ví, chọn danh mục — nghĩa là chỉ cần 1 lần gọi bị dính 1 trong 2 bug trên là nút Lưu bị khóa cho tới khi thoát màn hình.

### 2.2. Hiện tượng C: callback chọn mẫu chỉ áp dụng 2/6 field

```dart
onSelect: (tmpl) async {
  setState(() {
    _type = tmpl.type;
    _amountController.text = AppFormatters.number(tmpl.amount);
    // ❌ Thiếu: tmpl.walletId, tmpl.categoryId, tmpl.note, tmpl.location
  });
  await _runValidation();
},
```
`QuickTemplate` model đã có sẵn đủ field (`walletId`, `categoryId`, `note`, `location`) và được lưu đúng khi tạo mẫu (`_saveAsTemplate()`), nhưng khi **áp dụng lại** mẫu, code chỉ gán `_type` và `_amountController.text`, bỏ sót toàn bộ các field còn lại.

## 3. Fix Requirements (Yêu cầu sửa)

### 3.1. Sửa `_runValidation()` — bọc try/catch/finally, đảm bảo `_isValidating` LUÔN được reset

Thay toàn bộ thân hàm bằng:
```dart
Future<void> _runValidation() async {
  setState(() => _isValidating = true);
  try {
    final amount = AppFormatters.parseCurrencyInput(_amountController.text);

    if (_type == 'income') {
      setState(() {
        _walletBalanceExceeded = false;
        _budgetExceeded = false;
      });
      return; // an toàn: finally bên dưới vẫn luôn chạy để reset _isValidating
    }

    if (_selectedWalletId != null) {
      final exceed = await ValidationUtils.exceedsWalletBalance(
        walletId: _selectedWalletId!,
        amount: amount,
        firestoreService: _firestoreService,
      );
      setState(() => _walletBalanceExceeded = exceed);
    }
    if (_selectedCategoryId != null) {
      final exceed = await ValidationUtils.exceedsCategoryBudget(
        categoryId: _selectedCategoryId!,
        amount: amount,
        firestoreService: _firestoreService,
      );
      setState(() => _budgetExceeded = exceed);
    }
  } catch (e) {
    debugPrint('⚠️ Lỗi khi kiểm tra vượt số dư ví/ngân sách: $e');
    // Không để lỗi kiểm tra cảnh báo (vốn chỉ mang tính gợi ý) chặn luôn việc lưu giao dịch
    setState(() {
      _walletBalanceExceeded = false;
      _budgetExceeded = false;
    });
  } finally {
    if (mounted) setState(() => _isValidating = false);
  }
}
```
Nguyên tắc: **bất kể nhánh nào chạy (income/expense/lỗi/thành công), `_isValidating` luôn được set về `false` ở khối `finally` duy nhất.** Đây là điểm mấu chốt để không lặp lại lỗi "sửa chỗ này lòi chỗ khác" — thay vì thêm từng patch nhỏ, cấu trúc lại để về mặt logic không còn đường nào thoát khỏi hàm mà quên reset flag.

Cần thêm import nếu chưa có: hàm đã dùng `debugPrint` ở nơi khác trong file (`_handleSave`) nên không cần import mới.

### 3.2. Sửa callback `onSelect` của `QuickTemplateChip` — áp dụng đủ field

```dart
onSelect: (tmpl) async {
  setState(() {
    _type = tmpl.type;
    _amountController.text = AppFormatters.number(tmpl.amount);
    _selectedWalletId = tmpl.walletId.isNotEmpty ? tmpl.walletId : null;
    _selectedCategoryId = tmpl.categoryId.isNotEmpty ? tmpl.categoryId : null;
    _noteController.text = tmpl.note;
    _locationController.text = tmpl.location;
  });
  await _runValidation();
},
```
Lưu ý: không cần validate thêm `wallets.any(...)`/`categories.any(...)` tại đây — logic đó **đã có sẵn** trong phần `StreamBuilder` build dropdown (tự động reset về `null` nếu id không còn tồn tại trong danh sách mới), giữ nguyên không đổi.

`imagePath` của template **không** áp dụng lại (out of scope) — vì ảnh hóa đơn cũ có thể đã bị dọn khỏi cache thiết bị, tránh gán đường dẫn ảnh không còn tồn tại.

## 4. Không đổi (Out of scope)

- Không đổi `_handleSave()`, `_parseReceipt()`, `_pickImage()`.
- Không đổi `ValidationUtils`, `TemplateService`, `QuickTemplate` model.
- Không đổi UI/layout, chỉ đổi logic bên trong 2 hàm nêu trên.

## 5. Acceptance Criteria (Tiêu chí hoàn thành)

- [ ] Tạo giao dịch **Thu nhập** (điền đủ số tiền/ví/danh mục) → nút "Lưu giao dịch" bấm được ngay, không bị khóa.
- [ ] Tạo giao dịch **Chi tiêu** bằng camera OCR → sau khi OCR điền xong, chọn thêm ví + danh mục → bấm "Lưu giao dịch" thành công, không báo lỗi.
- [ ] Giả lập lỗi mạng khi đang chọn ví/danh mục (tắt wifi/data giữa chừng) → nút Lưu **không bị khóa vĩnh viễn** sau khi có mạng lại (verify `_isValidating` luôn trở về `false`).
- [ ] Lưu 1 mẫu giao dịch mới có đầy đủ ví/danh mục/ghi chú/địa điểm → bấm lại mẫu đó ở lần sau → toàn bộ 4 field trên được điền đúng, không chỉ mỗi số tiền.
- [ ] Test tối thiểu 2 lần cho mỗi trường hợp trên (income + expense) để chắc chắn không phải may rủi.

---

**Lưu ý cho agent thực thi:** Đọc `content/RULES.md` trước khi sửa — đặc biệt mục coding principles (không đổi phạm vi ngoài yêu cầu). Đây là fix có phạm vi rõ ràng: chỉ 2 hàm trong đúng 1 file.
