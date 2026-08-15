# TICKET 005 — Sửa lỗi lưu giao dịch thất bại âm thầm (silent save failure)

**Loại:** Bug fix (nghiêm trọng — mất dữ liệu người dùng tưởng đã lưu)
**Độ ưu tiên:** Cao nhất trong các ticket hiện tại
**File bị ảnh hưởng:** `lib/screens/home/add_transaction_screen.dart`

---

## 1. Context (Bối cảnh)

Test trên thiết bị thật: chụp ảnh hóa đơn → OCR trích xuất thành công → điền đủ ví/danh mục → bấm "Lưu giao dịch" → app hiện thông báo **"Không thể lưu ảnh hóa đơn (lỗi kết nối), giao dịch vẫn được lưu."** — nhưng thực tế: **giao dịch không xuất hiện trong lịch sử, số dư ví không bị trừ**. Log thiết bị cho thấy sau thông báo trên, có thêm 1 `StorageException` khác ("The operation was cancelled") rồi mất kết nối debug.

## 2. Root Cause (Nguyên nhân gốc)

```dart
setState(() => _isSaving = true);
try {
  String? imageUrl;
  if (_receiptImageBytes != null) {
    try {
      imageUrl = await _storageService.uploadReceiptImage(uid, _receiptImageBytes!);
    } catch (e) {
      debugPrint('⚠️ Upload ảnh hóa đơn thất bại, vẫn tiếp tục lưu giao dịch không kèm ảnh: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể lưu ảnh hóa đơn (lỗi kết nối), giao dịch vẫn được lưu.')),
        );
      }
    }
  }
  final tx = AppTransaction(...);
  await _firestoreService.createTransaction(tx); // ❌ KHÔNG có catch riêng cho dòng này
  if (!mounted) return;
  Navigator.of(context).pop();
} finally {
  if (mounted) setState(() => _isSaving = false);
}
```

Khối `try` ngoài cùng **chỉ có `finally`, không có `catch`**. Nếu `_firestoreService.createTransaction(tx)` ném exception (do cùng sự cố mạng vừa khiến upload ảnh thất bại, hoặc bất kỳ lỗi Firestore nào khác), exception này **không được bắt ở bất kỳ đâu**, bay thẳng ra khỏi `_handleSave()`. Flutter chỉ in exception ra console (không hiện UI), khiến người dùng:
- Thấy thông báo lỗi ảnh (từ catch bên trong) → tưởng phần còn lại đã ổn.
- Không thấy màn hình tự đóng (`Navigator.pop()` không chạy vì exception xảy ra trước đó) — nhưng vì không có thông báo lỗi rõ ràng, người dùng dễ nhầm là app bị treo/lag chứ không hiểu là giao dịch đã thất bại.

## 3. Fix Requirements (Yêu cầu sửa)

Thêm `catch` cho khối `try` ngoài cùng, bọc toàn bộ phần tạo và lưu giao dịch (không chỉ phần upload ảnh):

```dart
Future<void> _handleSave() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  final amount = AppFormatters.parseCurrencyInput(_amountController.text);

  if (uid == null || amount <= 0 || _selectedWalletId == null || _selectedCategoryId == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập đầy đủ số tiền, ví và danh mục')));
    return;
  }
  if (_walletBalanceExceeded) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Số tiền vượt quá số dư ví')));
    return;
  }
  if (_budgetExceeded) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Giao dịch sẽ vượt quá ngân sách danh mục')));
    return;
  }

  setState(() => _isSaving = true);
  try {
    String? imageUrl;
    if (_receiptImageBytes != null) {
      try {
        imageUrl = await _storageService.uploadReceiptImage(uid, _receiptImageBytes!);
      } catch (e) {
        debugPrint('⚠️ Upload ảnh hóa đơn thất bại, vẫn tiếp tục lưu giao dịch không kèm ảnh: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể lưu ảnh hóa đơn (lỗi kết nối), đang tiếp tục lưu giao dịch...')),
          );
        }
      }
    }

    final tx = AppTransaction(
      transactionId: '',
      userId: uid,
      walletId: _selectedWalletId!,
      categoryId: _selectedCategoryId!,
      amount: amount,
      type: _type,
      note: _noteController.text.trim(),
      image: imageUrl,
      location: _locationController.text.trim(),
      date: _selectedDate,
    );
    await _firestoreService.createTransaction(tx);
    if (!mounted) return;
    Navigator.of(context).pop();
  } catch (e) {
    debugPrint('❌ Lỗi khi lưu giao dịch: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể lưu giao dịch. Vui lòng kiểm tra kết nối mạng và thử lại.')),
      );
    }
  } finally {
    if (mounted) setState(() => _isSaving = false);
  }
}
```

**Thay đổi cụ thể:**
1. Thêm `catch (e)` cho khối `try` ngoài cùng, đặt **sau** phần try/catch upload ảnh lồng bên trong (giữ nguyên try/catch lồng đó — không gộp 2 catch làm một, vì lỗi upload ảnh và lỗi lưu giao dịch cần 2 thông báo khác nhau).
2. Đổi nội dung snackbar báo lỗi ảnh từ "...giao dịch vẫn được lưu" thành "...đang tiếp tục lưu giao dịch..." — tránh khẳng định chắc chắn đã lưu trong khi bước lưu thật sự vẫn chưa xảy ra (bước đó nằm ở dòng `createTransaction()` ngay sau).
3. Khi `createTransaction()` thất bại → hiện snackbar lỗi rõ ràng, **không gọi `Navigator.pop()`** (đã đúng vì nằm sau dòng lỗi, không cần sửa thêm) — người dùng ở lại màn hình Thêm giao dịch, biết cần thử lại, dữ liệu đã nhập không bị mất.
4. `finally` giữ nguyên, đảm bảo `_isSaving` luôn reset bất kể thành công hay lỗi.

## 4. Không đổi (Out of scope)

- Không đổi `StorageService.uploadReceiptImage()`, `FirestoreService.createTransaction()`.
- Không đổi validate đầu hàm (số tiền/ví/danh mục/vượt ngân sách).
- Không xử lý retry tự động — chỉ đảm bảo người dùng **biết** để tự bấm Lưu lại.

## 5. Acceptance Criteria (Tiêu chí hoàn thành)

- [ ] Giả lập lỗi mạng ngay trước khi lưu (tắt wifi/data đúng lúc bấm Lưu) → app hiện thông báo lỗi rõ ràng, **không** tự đóng màn hình, dữ liệu đã nhập vẫn còn nguyên trên form.
- [ ] Sau khi có mạng lại, bấm Lưu lại → giao dịch lưu thành công, xuất hiện đúng trong lịch sử, số dư ví bị trừ/cộng đúng.
- [ ] Trường hợp bình thường (mạng ổn định) → lưu giao dịch (có và không có ảnh hóa đơn) vẫn hoạt động như cũ, không bị ảnh hưởng bởi thay đổi này.
- [ ] Trường hợp upload ảnh thất bại nhưng lưu giao dịch thành công → chỉ thấy 1 thông báo (báo ảnh lỗi), giao dịch thực sự xuất hiện trong lịch sử ngay sau đó (xác nhận bằng cách kiểm tra Firestore Console hoặc màn hình danh sách giao dịch).
- [ ] Test tối thiểu 3 lần để loại trừ yếu tố ngẫu nhiên của lỗi mạng.
