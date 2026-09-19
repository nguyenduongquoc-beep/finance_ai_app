# TICKET 033 — Thêm giao diện "Chuyển tiền giữa ví" (Transfer) vào Add Transaction Screen

**Loại:** Feature mới (hoàn thiện phần đã hoãn từ Ticket 026 Phần D)
**Độ ưu tiên:** Trung bình-Cao (Nhóm 2 — tăng giá trị demo, rủi ro thấp vì backend đã có sẵn)
**File bị ảnh hưởng:** `lib/screens/home/add_transaction_screen.dart`

---

## 1. Context (Bối cảnh)

Ticket 026 đã kiến trúc lại toàn bộ tầng dữ liệu để hỗ trợ loại giao dịch thứ 3 — `transfer` (chuyển tiền giữa 2 ví của cùng 1 người dùng, không phải thu/chi thật, không ảnh hưởng tới thống kê hay ngân sách):

- `AppTransaction` model đã có sẵn field `toWalletId` (chỉ dùng khi `type == 'transfer'`).
- `FirestoreService.createTransaction()`, `updateTransactionSafely()`, `deleteTransaction()` đã xử lý đầy đủ atomic cho cả 3 loại (`income`/`expense`/`transfer`) — trừ ví nguồn, cộng ví đích, hoàn tác đúng khi sửa/xóa.
- `TransactionCard` và `TransactionDetailScreen` đã hiển thị đúng cho giao dịch `transfer` (icon riêng, không dấu +/-, hiện "Từ ví"/"Đến ví").

**Phần duy nhất còn thiếu:** `add_transaction_screen.dart` — nơi **tạo mới** giao dịch — vẫn chỉ có 2 lựa chọn "Chi tiêu"/"Thu nhập", chưa có cách nào để người dùng thật sự tạo ra 1 giao dịch `transfer`. Ticket 026 đã chủ động **hoãn phần này** vì màn hình quá nhạy cảm (đã qua nhiều vòng sửa bug quan trọng — ticket 002, 004, 005, 007, 010, 027, 028), cần làm riêng để dễ kiểm soát rủi ro.

## 2. Nguyên tắc bắt buộc khi thực hiện

- **Không đổi tên, không xóa** bất kỳ biến state hay hàm xử lý hiện có (`_handleSave`, `_runValidation`, `_parseReceipt`, `_typeToggleButton`, v.v.) — chỉ **mở rộng** logic đã có để hỗ trợ thêm giá trị `_type == 'transfer'`.
- Toàn bộ logic backend (`createTransaction`, `updateTransactionSafely`, `deleteTransaction`) **đã đúng sẵn, không cần sửa `firestore_service.dart`** — chỉ cần UI gọi đúng tham số.
- Giữ nguyên 100% hành vi hiện có cho `expense`/`income` — không được gây regression cho 2 loại giao dịch đã ổn định.

## 3. Fix Requirements

### 3.1. Thêm state mới

```dart
String _type = 'expense'; // giữ nguyên, giờ có thể nhận thêm giá trị 'transfer'
String? _selectedToWalletId; // MỚI — chỉ dùng khi _type == 'transfer'
```

### 3.2. Đổi hàng toggle loại giao dịch từ 2 nút sang 3 nút

Thay `Row` hiện tại (2 `Expanded`) bằng 3 nút cùng hàng, thu nhỏ padding/font nếu cần để vừa 3 nút:
```dart
Row(
  children: [
    Expanded(child: _typeToggleButton('Chi tiêu', 'expense', AppColors.expense)),
    const SizedBox(width: 8),
    Expanded(child: _typeToggleButton('Thu nhập', 'income', AppColors.income)),
    const SizedBox(width: 8),
    Expanded(child: _typeToggleButton('Chuyển tiền', 'transfer', AppColors.textSecondary)),
  ],
),
```

### 3.3. Mở rộng `_typeToggleButton()` — áp dụng đúng logic reset đã có (Ticket 027), mở rộng cho `transfer`

Giữ nguyên cấu trúc rẽ nhánh Thêm mới / Sửa đã có, chỉ bổ sung reset `_selectedToWalletId`:
```dart
onPressed: () async {
  if (widget.transactionToEdit != null && _type == type) return;
  setState(() {
    if (widget.transactionToEdit == null) {
      _type = type;
      _selectedCategoryId = null;
      _selectedWalletId = null;
      _selectedToWalletId = null; // MỚI
      _amountController.clear();
      _noteController.clear();
      _locationController.clear();
      _receiptImageBytes = null;
      _existingImagePath = null;
      _walletBalanceExceeded = false;
      _budgetExceeded = false;
      _isSaving = false;
      _isParsing = false;
      _isValidating = false;
    } else {
      _type = type;
      _selectedCategoryId = null;
      _selectedToWalletId = null; // MỚI — đổi loại khi Sửa cũng cần reset ví đích cũ
    }
  });
  await _runValidation();
},
```

### 3.4. Ẩn/hiện các phần UI theo đúng loại giao dịch (`_type == 'transfer'`)

- **Ẩn hoàn toàn** dropdown "Danh mục" và card cảnh báo vượt ngân sách (`_budgetExceeded`) — không áp dụng cho transfer.
- **Ẩn** toàn bộ khu vực "Ảnh hóa đơn" (chụp/chọn ảnh + OCR) — về mặt nghiệp vụ, chuyển tiền giữa ví của chính mình không có hóa đơn để quét, tránh gây nhầm lẫn cho người dùng.
- **Thêm mới** dropdown thứ 2 **"Chuyển đến ví"** ngay dưới dropdown "Ví thanh toán" hiện có (lúc này đổi label dropdown Ví thanh toán hiện tại thành **"Từ ví"** để rõ nghĩa hơn khi ở chế độ transfer — chỉ đổi label khi `_type == 'transfer'`, giữ nguyên "Ví thanh toán" cho `expense`/`income`).
- Dropdown "Chuyển đến ví" dùng cùng nguồn dữ liệu `StreamBuilder<List<Wallet>>` đã có (không tạo thêm Stream mới), nhưng **loại trừ** ví đã chọn ở "Từ ví" khỏi danh sách `items` để tránh chọn trùng:
  ```dart
  items: wallets
      .where((w) => w.walletId != _selectedWalletId)
      .map((w) => DropdownMenuItem(value: w.walletId, child: Text(w.walletName)))
      .toList(),
  onChanged: (v) async {
    setState(() => _selectedToWalletId = v);
    await _runValidation();
  },
  ```
- Ghi chú, Địa điểm, Ngày giao dịch: **giữ nguyên hiển thị bình thường** cho cả 3 loại (VD ghi chú lý do chuyển tiền vẫn hữu ích).

### 3.5. Cập nhật `_runValidation()` — xử lý riêng cho `transfer`

```dart
Future<void> _runValidation() async {
  setState(() => _isValidating = true);
  try {
    final amount = AppFormatters.parseCurrencyInput(_amountController.text);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    if (_type == 'income') {
      setState(() {
        _walletBalanceExceeded = false;
        _budgetExceeded = false;
      });
      return;
    }

    if (_type == 'transfer') {
      // Transfer chỉ kiểm tra số dư ví NGUỒN, KHÔNG kiểm tra ngân sách
      setState(() => _budgetExceeded = false);
      if (_selectedWalletId != null) {
        final exceed = await ValidationUtils.exceedsWalletBalance(
          walletId: _selectedWalletId!,
          amount: amount,
          firestoreService: _firestoreService,
        );
        setState(() => _walletBalanceExceeded = exceed);
      }
      return;
    }

    // Nhánh 'expense' giữ nguyên như cũ
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
        userId: uid,
        categoryId: _selectedCategoryId!,
        amount: amount,
        firestoreService: _firestoreService,
      );
      setState(() => _budgetExceeded = exceed);
    }
  } catch (e) {
    debugPrint('⚠️ Lỗi khi kiểm tra vượt số dư ví/ngân sách: $e');
    setState(() {
      _walletBalanceExceeded = false;
      _budgetExceeded = false;
    });
  } finally {
    if (mounted) setState(() => _isValidating = false);
  }
}
```

### 3.6. Cập nhật `_handleSave()` — validate riêng + build đúng `AppTransaction` cho transfer

Thêm điều kiện validate trước khi build đối tượng giao dịch:
```dart
Future<void> _handleSave() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  final amount = AppFormatters.parseCurrencyInput(_amountController.text);

  if (uid == null || amount <= 0 || _selectedWalletId == null) {
    AppSnackbar.show(context, 'Vui lòng nhập đầy đủ số tiền và ví', isError: true);
    return;
  }

  if (_type == 'transfer') {
    if (_selectedToWalletId == null) {
      AppSnackbar.show(context, 'Vui lòng chọn ví nhận tiền', isError: true);
      return;
    }
    if (_selectedToWalletId == _selectedWalletId) {
      AppSnackbar.show(context, 'Ví nguồn và ví đích không được trùng nhau', isError: true);
      return;
    }
  } else if (_selectedCategoryId == null) {
    AppSnackbar.show(context, 'Vui lòng nhập đầy đủ số tiền, ví và danh mục', isError: true);
    return;
  }

  if (_walletBalanceExceeded) {
    AppSnackbar.show(context, 'Số tiền vượt quá số dư ví', isError: true);
    return;
  }
  if (_budgetExceeded) {
    AppSnackbar.show(context, 'Giao dịch sẽ vượt quá ngân sách danh mục', isError: true);
    return;
  }

  setState(() => _isSaving = true);
  try {
    // Với transfer: không có ảnh hóa đơn, categoryId để rỗng
    String? imageUrl;
    if (_type != 'transfer' && _receiptImageBytes != null) {
      try {
        imageUrl = await _storageService.uploadReceiptImage(uid, _receiptImageBytes!);
      } catch (e) {
        debugPrint('⚠️ Upload ảnh hóa đơn thất bại: $e');
        if (mounted) {
          AppSnackbar.show(context, 'Không thể lưu ảnh hóa đơn (lỗi kết nối), đang tiếp tục lưu giao dịch...', isError: true);
        }
      }
    }

    final categoryIdToSave = _type == 'transfer' ? '' : (_selectedCategoryId ?? '');
    final toWalletIdToSave = _type == 'transfer' ? _selectedToWalletId : null;

    if (widget.transactionToEdit != null) {
      final newTx = AppTransaction(
        transactionId: widget.transactionToEdit!.transactionId,
        userId: uid,
        walletId: _selectedWalletId!,
        categoryId: categoryIdToSave,
        amount: amount,
        type: _type,
        toWalletId: toWalletIdToSave,
        note: _noteController.text.trim(),
        image: imageUrl ?? _existingImagePath,
        location: _locationController.text.trim(),
        date: _selectedDate,
      );
      await _firestoreService.updateTransactionSafely(widget.transactionToEdit!, newTx);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } else {
      final tx = AppTransaction(
        transactionId: '',
        userId: uid,
        walletId: _selectedWalletId!,
        categoryId: categoryIdToSave,
        amount: amount,
        type: _type,
        toWalletId: toWalletIdToSave,
        note: _noteController.text.trim(),
        image: imageUrl,
        location: _locationController.text.trim(),
        date: _selectedDate,
      );
      await _firestoreService.createTransaction(tx);
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  } catch (e) {
    debugPrint('❌ Lỗi khi lưu giao dịch: $e');
    if (mounted) {
      AppSnackbar.show(context, 'Không thể lưu giao dịch. Vui lòng kiểm tra kết nối mạng và thử lại.', isError: true);
    }
  } finally {
    if (mounted) setState(() => _isSaving = false);
  }
}
```

### 3.7. Mẫu giao dịch nhanh (Quick Template)

Không thay đổi gì ở `QuickTemplateChip`/`TemplateService` — mẫu giao dịch nhanh **chỉ áp dụng cho `expense`/`income`** như hiện tại, không mở rộng cho `transfer` ở ticket này (ngoài phạm vi, tránh phình việc).

## 4. Không đổi (Out of scope)

- Không đổi `firestore_service.dart`, `transaction_model.dart` — backend đã đúng từ Ticket 026.
- Không thêm mẫu giao dịch nhanh cho loại `transfer`.
- Không đổi `TransactionCard`, `TransactionDetailScreen` — đã hiển thị đúng transfer từ trước.
- Không đổi `_typeFilter` ở `TransactionListScreen` (vẫn giữ 3 lựa chọn Tất cả/Thu nhập/Chi tiêu, giao dịch transfer vẫn hiện lẫn khi lọc "Tất cả" — đã ghi nhận là chấp nhận được ở Ticket 026 Phần F).

## 5. Acceptance Criteria

- [ ] Bấm nút "Chuyển tiền" → form đổi đúng: ẩn Danh mục, ẩn khu vực Ảnh hóa đơn, hiện dropdown "Từ ví" + "Chuyển đến ví".
- [ ] Chọn "Từ ví" và "Chuyển đến ví" trùng nhau → không cho lưu, báo lỗi rõ ràng.
- [ ] Tạo giao dịch chuyển 500.000đ từ Ví A sang Ví B → Ví A giảm đúng 500.000đ, Ví B tăng đúng 500.000đ, tổng tài sản không đổi.
- [ ] Giao dịch chuyển tiền vừa tạo → không xuất hiện trong bất kỳ tính toán Thu nhập/Chi tiêu nào ở Dashboard, không ảnh hưởng tới bất kỳ Ngân sách nào.
- [ ] Nhập số tiền vượt số dư ví nguồn → cảnh báo đúng như cơ chế `expense` hiện có, chặn lưu.
- [ ] Sửa 1 giao dịch chuyển tiền đã tạo (đổi số tiền hoặc đổi ví đích) → số dư cả ví cũ và mới đều được hoàn tác/áp dụng đúng.
- [ ] Xóa 1 giao dịch chuyển tiền → số dư cả 2 ví liên quan hoàn tác đúng.
- [ ] Xem lại giao dịch chuyển tiền ở Transaction Detail Screen → hiện đúng "Từ ví"/"Đến ví", không hiện "Danh mục".
- [ ] Đổi qua lại 3 loại giao dịch (Chi tiêu ⇄ Thu nhập ⇄ Chuyển tiền) nhiều lần ở chế độ Thêm mới → form luôn được dọn sạch đúng theo logic đã có (Ticket 007), không rò rỉ dữ liệu giữa các loại.
- [ ] Sửa 1 giao dịch Chi tiêu có sẵn, đổi sang loại Chuyển tiền → theo đúng logic Ticket 027 (màn Sửa không xóa sạch dữ liệu khi đổi loại) — Danh mục và Ví đích cũ được reset về trống, các trường khác (ghi chú, địa điểm) vẫn giữ nguyên.
- [ ] `flutter analyze` không phát sinh lỗi/warning mới.
