# TICKET 011 — Đổi lưu ảnh hóa đơn sang Local Storage & khắc phục hiển thị giao dịch

**Loại:** Refactor kiến trúc (thay Firebase Cloud Storage bằng local storage)
**Độ ưu tiên:** Cao
**File bị ảnh hưởng:** `lib/services/storage_service.dart`, `lib/screens/home/transaction_detail_screen.dart`, `lib/services/firestore_service.dart`

---

## 1. Context (Bối cảnh)

Firebase Cloud Storage yêu cầu gói Blaze (trả phí) theo chính sách mới của Google. Project đang ở gói Spark (miễn phí) → Storage bucket **chưa từng được khởi tạo thật sự**, khiến mọi lần upload ảnh hóa đơn đều thất bại (log xác nhận: `StorageException: Object does not exist at location`), bất kể chất lượng mạng. Quyết định: chuyển sang lưu ảnh **cục bộ trên thiết bị**, chấp nhận đánh đổi ảnh không đồng bộ qua cloud (xem `content/PRD.md` mục 7, `content/SCHEMA.md` mục 5 đã cập nhật).

## 2. Root Cause

Không phải bug code — là giới hạn hạ tầng (Firebase Storage cần gói trả phí). Giải pháp: thay hoàn toàn cơ chế lưu trữ ảnh, giữ nguyên contract gọi hàm (`uploadReceiptImage`) để không phải sửa `add_transaction_screen.dart`.

## 3. Fix Requirements

### 3.1. Viết lại `StorageService`

```dart
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// ============================================================
/// STORAGE SERVICE
/// Lưu ảnh hóa đơn giao dịch CỤC BỘ trên thiết bị (không dùng Firebase
/// Cloud Storage — xem content/SCHEMA.md mục 5 để biết lý do).
/// Đánh đổi: ảnh mất khi gỡ cài đặt app hoặc đổi thiết bị.
/// ============================================================
class StorageService {
  /// Lưu ảnh hóa đơn vào bộ nhớ cục bộ của app.
  /// Trả về đường dẫn file (String) — lưu trực tiếp vào field `image`
  /// của AppTransaction, dùng để đọc lại bằng Image.file().
  Future<String> uploadReceiptImage(String userId, Uint8List imageBytes) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final receiptsDir = Directory('${docsDir.path}/receipts');
    if (!await receiptsDir.exists()) {
      await receiptsDir.create(recursive: true);
    }
    final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final file = File('${receiptsDir.path}/$fileName');
    await file.writeAsBytes(imageBytes);
    return file.path;
  }

  /// Upload avatar người dùng — giữ nguyên cơ chế local tương tự.
  Future<String> uploadAvatar(String userId, File imageFile) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final avatarsDir = Directory('${docsDir.path}/avatars');
    if (!await avatarsDir.exists()) {
      await avatarsDir.create(recursive: true);
    }
    final destFile = File('${avatarsDir.path}/$userId.jpg');
    await imageFile.copy(destFile.path);
    return destFile.path;
  }

  /// Xóa ảnh theo đường dẫn local. Không throw nếu file không tồn tại
  /// (VD ảnh đã bị xóa trước đó, hoặc field image trống).
  Future<void> deleteImageByUrl(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Không throw — xóa ảnh thất bại không nên chặn các thao tác khác
    }
  }
}
```

**Lưu ý quan trọng:** dùng `getApplicationDocumentsDirectory()` (bền vững), **không** dùng `getTemporaryDirectory()` (hệ điều hành có thể tự xóa bất cứ lúc nào — chỉ phù hợp cho file tạm OCR ở `ai_service.dart`, không phù hợp cho ảnh cần giữ lâu dài).

### 3.2. Sửa `transaction_detail_screen.dart` — đổi cách hiển thị ảnh

```dart
// Thay thế:
Image.network(transaction.image!, height: 200, fit: BoxFit.cover),

// Bằng:
Image.file(File(transaction.image!), height: 200, fit: BoxFit.cover),
```
Cần thêm `import 'dart:io';` ở đầu file nếu chưa có.

**Xử lý trường hợp file không còn tồn tại** (VD dữ liệu cũ trỏ tới URL Firebase Storage cũ, hoặc file local đã bị xóa ngoài ý muốn) — bọc bằng `errorBuilder` để tránh crash:
```dart
Image.file(
  File(transaction.image!),
  height: 200,
  fit: BoxFit.cover,
  errorBuilder: (context, error, stackTrace) => Container(
    height: 200,
    color: Colors.grey.shade200,
    child: const Center(
      child: Icon(Icons.broken_image_outlined, color: Colors.grey, size: 40),
    ),
  ),
),
```

### 3.3. Sửa `FirestoreService.deleteTransaction()` — dọn file ảnh local khi xóa giao dịch

Thêm gọi `StorageService().deleteImageByUrl()` khi xóa giao dịch có ảnh, tránh rác tích tụ trong bộ nhớ máy:
```dart
Future<void> deleteTransaction(AppTransaction tx) async {
  await _db.collection('transactions').doc(tx.transactionId).delete();

  final delta = tx.type == 'income' ? -tx.amount : tx.amount;
  await adjustWalletBalance(tx.walletId, delta);

  if (tx.type == 'expense') {
    final monthStr = DateFormat('MM/yyyy').format(tx.date);
    await adjustBudgetSpent(tx.categoryId, monthStr, -tx.amount);
  }

  // Dọn file ảnh local nếu có (không chặn luồng chính nếu lỗi)
  if (tx.image != null && tx.image!.isNotEmpty) {
    try {
      final file = File(tx.image!);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Bỏ qua lỗi xóa file — không quan trọng bằng việc đã xóa transaction
    }
  }
}
```
Cần thêm `import 'dart:io';` vào `firestore_service.dart` nếu chưa có.

## 4. Không đổi (Out of scope)

- Không đổi `add_transaction_screen.dart` — hàm `_storageService.uploadReceiptImage(uid, bytes)` giữ nguyên cách gọi, chỉ đổi implementation bên trong `StorageService`.
- Không đổi schema Firestore (field `image` vẫn kiểu `String?`, chỉ đổi ý nghĩa nội dung).
- Không cần thêm permission mới trong `AndroidManifest.xml`.
- Không xóa `firebase_storage` khỏi `pubspec.yaml` trong ticket này (để tránh phá vỡ import còn sót nếu có chỗ khác dùng — dọn dẹp sau nếu xác nhận không còn chỗ nào cần).

## 5. Acceptance Criteria

- [ ] Chụp/chọn ảnh hóa đơn → lưu giao dịch → **không còn** thông báo "Không thể lưu ảnh hóa đơn (lỗi kết nối)" nữa (vì không còn phụ thuộc mạng cho bước này).
- [ ] Vào "Chi tiết giao dịch" của giao dịch vừa tạo → ảnh hóa đơn hiển thị đúng, rõ nét.
- [ ] Xóa giao dịch có ảnh → kiểm tra thư mục `receipts/` trong bộ nhớ app (qua file explorer/adb nếu cần) → file ảnh tương ứng đã bị xóa.
- [ ] Test với giao dịch **không có ảnh** (nhập tay, không chụp hóa đơn) → không lỗi, không crash, field `image` là `null` bình thường.
- [ ] Gỡ cài đặt app rồi cài lại → xác nhận đúng như dự kiến: dữ liệu giao dịch (Firestore) vẫn còn nguyên, nhưng ảnh hóa đơn cũ không còn xem lại được (đánh đổi đã biết, không phải bug).
