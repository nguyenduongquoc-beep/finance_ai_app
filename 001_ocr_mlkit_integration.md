# TICKET 001 — Tích hợp Google ML Kit Text Recognition vào luồng OCR hóa đơn

**Loại:** Refactor / Kiến trúc (không phải bug chức năng)
**Độ ưu tiên:** Trung bình
**Module liên quan:** AI (module 5) — tính năng AI 7 (OCR hóa đơn)
**File chính bị ảnh hưởng:** `lib/services/ai_service.dart`, `lib/screens/home/add_transaction_screen.dart`

---

## 1. Context (Bối cảnh)

Theo `De_Cuong_Tot_Nghiep_CNTT.docx` (mục 4.1 — Nội dung nghiên cứu), kiến trúc OCR được mô tả là:

> "Nghiên cứu và ứng dụng công nghệ OCR (Google ML Kit Text Recognition) **kết hợp** AI để tự động nhận dạng và trích xuất thông tin từ hóa đơn."

Package `google_mlkit_text_recognition: ^0.16.0` đã có trong `pubspec.yaml` nhưng **hiện chưa được import/sử dụng ở bất kỳ đâu trong code**.

Luồng hiện tại (`AiService.extractReceiptInfo()` trong `lib/services/ai_service.dart`):
```dart
Future<ReceiptInfo?> extractReceiptInfo(Uint8List imageBytes) async {
  // ...
  final content = Content.multi([
    TextPart(prompt),
    DataPart('image/jpeg', imageBytes),
  ]);
  final response = await _generateWithFallback([content]);
  // ...
}
```
→ Ảnh hóa đơn được gửi **thẳng dạng ảnh (multimodal)** cho Gemini, Gemini tự đọc chữ trong ảnh và trả JSON — bỏ qua hoàn toàn bước ML Kit on-device.

Được gọi từ `add_transaction_screen.dart` qua hàm `_parseReceipt()`, chạy tự động ngay sau khi người dùng chụp/chọn ảnh hóa đơn (`_pickImage()`).

## 2. Root Cause (Nguyên nhân gốc)

Thiếu bước tiền xử lý OCR on-device bằng ML Kit trước khi gửi dữ liệu cho Gemini. Đây là **sai lệch giữa triển khai thực tế và kiến trúc đã cam kết trong đề cương khóa luận** — cần khắc phục để báo cáo và source code khớp nhau khi bảo vệ.

## 3. Fix Requirements (Yêu cầu sửa)

### 3.1. Thêm bước OCR on-device bằng ML Kit
Trong `lib/services/ai_service.dart`:
- Import `package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart`.
- Thêm method mới `Future<String?> _recognizeTextOnDevice(Uint8List imageBytes)`:
  - Convert `Uint8List` → `InputImage` (dùng `InputImage.fromBytes` hoặc lưu tạm file rồi `InputImage.fromFilePath`, tùy cách nào ổn định hơn trên cả Android/iOS — **ưu tiên cách không cần ghi file tạm nếu API cho phép**).
  - Dùng `TextRecognizer(script: TextRecognitionScript.latin)` để nhận diện.
  - Trả về `recognizedText.text` (raw string), hoặc `null` nếu không nhận diện được ký tự nào.
  - Nhớ gọi `textRecognizer.close()` sau khi dùng xong để giải phóng tài nguyên native.

### 3.2. Sửa `extractReceiptInfo()` để dùng kết quả ML Kit làm input chính
- Gọi `_recognizeTextOnDevice(imageBytes)` trước.
- **Nếu có raw text** (không null, không rỗng):
  - Đổi prompt gửi Gemini: thay vì gửi `DataPart(image)`, gửi **raw text đã nhận diện** kèm prompt yêu cầu Gemini parse thành JSON có cấu trúc (`merchant`, `total`, `date`) — dùng `Content.text(prompt)` thay vì `Content.multi([...DataPart])`.
  - Prompt mẫu:
    ```
    Dưới đây là văn bản được trích xuất từ ảnh hóa đơn bằng OCR (có thể còn nhiễu/sai sót):
    ---
    <raw_text>
    ---
    Hãy phân tích và trả về JSON gồm: merchant (tên cửa hàng), total (tổng tiền, số),
    date (ngày, ISO string hoặc null). Chỉ trả về JSON thuần túy, không markdown fence.
    ```
- **Nếu ML Kit không nhận diện được text nào** (null/rỗng — ảnh mờ, hóa đơn viết tay, v.v.): **fallback về cách cũ**, gửi thẳng ảnh (`DataPart`) cho Gemini như hiện tại, để không làm giảm độ chính xác/trải nghiệm người dùng.
- Giữ nguyên toàn bộ phần parse JSON phía sau (`_stripMarkdownCodeFence`, `ReceiptInfo.fromJson`) — **không đổi**.

### 3.3. Không đổi contract public
- Signature `Future<ReceiptInfo?> extractReceiptInfo(Uint8List imageBytes)` giữ nguyên.
- `add_transaction_screen.dart` (`_parseReceipt()`) **không cần sửa gì** — vẫn gọi `ai.extractReceiptInfo(_receiptImageBytes!)` như cũ.

### 3.4. Xử lý lỗi
- Nếu `TextRecognizer` throw exception (lỗi native plugin, thiết bị không hỗ trợ...), catch lại và coi như "không nhận diện được text" → fallback sang gửi ảnh thẳng cho Gemini (không để app crash hay OCR fail hoàn toàn).

### 3.5. Dọn dẹp tài nguyên
- Cân nhắc tạo `TextRecognizer` là instance dùng lại (field của `AiService`) thay vì tạo mới + `close()` mỗi lần gọi, để tránh overhead khởi tạo lặp lại — **nhưng ưu tiên đúng chức năng trước, tối ưu performance sau** nếu không kịp trong 1 lần sửa.

## 4. Ràng buộc kỹ thuật (theo RULES.md)

- Không gọi `GenerativeModel` trực tiếp ngoài `_generateWithFallback()` (RULES.md mục 7).
- Không thay đổi field/response contract của `ReceiptInfo` (SCHEMA.md không định nghĩa collection này vì đây là kết quả tạm thời, không lưu Firestore — nhưng model đã dùng nhiều nơi, giữ nguyên).
- Log bằng `debugPrint` (giữ style hiện có trong file, VD `debugPrint('🔧 ...')`) để dễ debug khi demo — không dùng `print()`.

## 5. Acceptance Criteria (Tiêu chí hoàn thành)

- [ ] Chụp/chọn ảnh hóa đơn rõ nét (chữ in) → console log thể hiện đã chạy qua ML Kit và có raw text trước khi gọi Gemini.
- [ ] Kết quả trích xuất (`merchant`, `total`, `date`) tương đương hoặc chính xác hơn so với trước khi sửa, trên ít nhất 3 ảnh hóa đơn test khác nhau.
- [ ] Với ảnh mờ/không có chữ rõ ràng → app không crash, tự động fallback gửi ảnh thẳng cho Gemini, vẫn cố gắng trả về `ReceiptInfo` hoặc `null` như cũ.
- [ ] `add_transaction_screen.dart` không cần sửa, luồng `_parseReceipt()` hoạt động y như trước từ góc nhìn UI.
- [ ] Không phát sinh warning/lỗi liên quan đến `TextRecognizer` không được `close()` (memory leak native resource).
- [ ] README.md / PROGRESS.md được cập nhật: bỏ dòng "AI 7 (OCR) chưa triển khai đầy đủ ML Kit" nếu có, ghi rõ đã tích hợp ML Kit + Gemini kết hợp.

---

**Lưu ý cho agent thực thi:** Đọc `content/RULES.md`, `content/ARCHITECTURE.md`, `content/SCHEMA.md` trước khi bắt đầu để đảm bảo code mới khớp convention hiện có của dự án (service layer pattern, không gọi Firestore/Gemini trực tiếp từ UI, giữ nguyên style comment tiếng Việt trong docblock).
