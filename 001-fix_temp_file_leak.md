# TICKET 001-FIX — Sửa rò rỉ file tạm trong `_recognizeTextOnDevice()`

**Loại:** Bug fix (phát sinh từ TICKET 001)
**Độ ưu tiên:** Cao (trước khi đóng ticket 001)
**File bị ảnh hưởng:** `lib/services/ai_service.dart`

---

## 1. Context (Bối cảnh)

TICKET 001 đã tích hợp Google ML Kit Text Recognition vào `AiService._recognizeTextOnDevice()`. Sau khi review code thật, phát hiện lỗi rò rỉ file tạm khi ML Kit xử lý thất bại.

Code hiện tại:
```dart
Future<String?> _recognizeTextOnDevice(Uint8List imageBytes) async {
  if (kIsWeb) {
    debugPrint('🔧 ML Kit không hỗ trợ trên Flutter Web, bỏ qua bước OCR on-device');
    return null;
  }

  final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/receipt_ocr_temp.jpg');
    await tempFile.writeAsBytes(imageBytes);

    final inputImage = InputImage.fromFilePath(tempFile.path);
    final recognizedText = await textRecognizer.processImage(inputImage);

    // Dọn file tạm — CHỈ chạy nếu processImage() thành công
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    debugPrint('🔧 ML Kit nhận diện được ${recognizedText.blocks.length} block(s), '
        'tổng ${recognizedText.text.length} ký tự');

    return recognizedText.text.isEmpty ? null : recognizedText.text;
  } catch (e) {
    debugPrint('⚠️ ML Kit TextRecognizer lỗi, sẽ fallback sang gửi ảnh cho Gemini: $e');
    return null;
  } finally {
    textRecognizer.close();
  }
}
```

## 2. Root Cause (Nguyên nhân gốc)

Lệnh dọn file tạm (`tempFile.delete()`) nằm **bên trong khối `try`, ngay sau** `textRecognizer.processImage()`. Nếu `processImage()` throw exception (ảnh hỏng, plugin lỗi, thiết bị không hỗ trợ...), luồng thực thi nhảy thẳng vào `catch` — dòng dọn file **không bao giờ được chạy tới**. `finally` hiện tại chỉ `close()` recognizer, không dọn file.

Hệ quả: mỗi lần ML Kit xử lý thất bại, một file `.jpg` bị bỏ lại vĩnh viễn trong thư mục temp của thiết bị — vi phạm yêu cầu "không rò rỉ tài nguyên" đã đặt ra trong TICKET 001 (mục 3.5 và Acceptance Criteria).

Ngoài ra, tên file tạm cố định (`receipt_ocr_temp.jpg`) có rủi ro (dù thấp) bị xung đột/ghi đè nếu hàm được gọi liên tiếp nhanh (VD người dùng bấm chụp ảnh 2 lần gần nhau trước khi lần gọi đầu xử lý xong).

## 3. Fix Requirements (Yêu cầu sửa)

Sửa `_recognizeTextOnDevice()` trong `lib/services/ai_service.dart` theo đúng cấu trúc sau:

1. Khai báo biến `File? tempFile` (nullable) **ở ngoài khối `try`**, để khối `finally` truy cập được dù exception xảy ra ở bất kỳ dòng nào bên trong `try` (kể cả trước khi file được tạo).
2. Đổi tên file tạm sang có timestamp để tránh xung đột khi gọi liên tiếp:
   ```dart
   tempFile = File('${tempDir.path}/receipt_ocr_${DateTime.now().millisecondsSinceEpoch}.jpg');
   ```
3. **Xóa bỏ hoàn toàn** đoạn dọn file cũ nằm trong `try` (sau `processImage()`).
4. Chuyển toàn bộ việc dọn dẹp vào khối `finally` duy nhất, chạy **cả 2 việc** (dọn file + đóng recognizer) theo thứ tự:
   ```dart
   finally {
     if (tempFile != null && await tempFile.exists()) {
       await tempFile.delete();
     }
     textRecognizer.close();
   }
   ```
5. Giữ nguyên toàn bộ phần còn lại: guard `kIsWeb`, log debugPrint, logic trả `null` khi text rỗng, catch-log-return null khi lỗi.

### Code tham khảo đầy đủ sau khi sửa:

```dart
Future<String?> _recognizeTextOnDevice(Uint8List imageBytes) async {
  if (kIsWeb) {
    debugPrint('🔧 ML Kit không hỗ trợ trên Flutter Web, bỏ qua bước OCR on-device');
    return null;
  }

  final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  File? tempFile;

  try {
    final tempDir = await getTemporaryDirectory();
    tempFile = File('${tempDir.path}/receipt_ocr_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await tempFile.writeAsBytes(imageBytes);

    final inputImage = InputImage.fromFilePath(tempFile.path);
    final recognizedText = await textRecognizer.processImage(inputImage);

    debugPrint('🔧 ML Kit nhận diện được ${recognizedText.blocks.length} block(s), '
        'tổng ${recognizedText.text.length} ký tự');

    return recognizedText.text.isEmpty ? null : recognizedText.text;
  } catch (e) {
    debugPrint('⚠️ ML Kit TextRecognizer lỗi, sẽ fallback sang gửi ảnh cho Gemini: $e');
    return null;
  } finally {
    if (tempFile != null && await tempFile.exists()) {
      await tempFile.delete();
    }
    textRecognizer.close();
  }
}
```

## 4. Không đổi (Out of scope)

- Không đổi signature hàm, không đổi contract `extractReceiptInfo()`.
- Không đổi bất kỳ file nào khác ngoài `ai_service.dart`.
- Không đổi prompt gửi Gemini, không đổi logic fallback ảnh-thẳng-cho-Gemini.

## 5. Acceptance Criteria (Tiêu chí hoàn thành)

- [ ] `flutter analyze` chạy sạch, không phát sinh warning/error mới liên quan đến `ai_service.dart`.
- [ ] Test giả lập lỗi: tạm thời truyền `Uint8List` rỗng hoặc file ảnh hỏng vào `_recognizeTextOnDevice()` để `processImage()` throw exception → kiểm tra thư mục temp của thiết bị **không còn file `receipt_ocr_*.jpg` nào sót lại** sau khi hàm return.
- [ ] Test bình thường: chụp ảnh hóa đơn rõ nét → OCR vẫn hoạt động đúng như trước khi sửa (không regression), file tạm bị xóa sau khi xử lý xong (thành công hay thất bại đều không còn sót file).
- [ ] Gọi liên tiếp 2 lần (chụp ảnh 2 lần nhanh) → không có lỗi ghi đè/xung đột file tạm.

---

**Lưu ý cho agent thực thi:** Đây là fix nhỏ, phạm vi giới hạn trong đúng 1 method của 1 file — không refactor thêm gì khác ngoài yêu cầu trên.
