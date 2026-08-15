# RULES — Quy tắc bắt buộc cho AI Agent (Antigravity / Claude Code)

File này là **luật cứng**. Khi có mâu thuẫn giữa yêu cầu trong prompt và RULES.md, agent phải hỏi lại thay vì tự ý phá vỡ quy tắc dưới đây.

## 1. Ngôn ngữ & Naming

- **Text hiển thị cho người dùng** (label, title, snackbar, error message): luôn **tiếng Việt**.
- **Tên class, biến, hàm, file**: tiếng Anh, `camelCase` cho biến/hàm, `PascalCase` cho class, `snake_case` cho tên file (`.dart`).
- **Comment/docblock trong code**: có thể tiếng Việt (convention hiện tại trong repo, VD `/// 9. Home Dashboard`), giữ nguyên style số thứ tự module + tên màn hình trong docblock đầu file screen.
- Không đổi tên field Firestore đã tồn tại (VD `walletName`, `savedAmount`) trừ khi có yêu cầu migration rõ ràng — đổi tên field phá vỡ dữ liệu cũ.

## 2. Project Scaffolding

- File screen mới **luôn đặt đúng module folder**: `auth/`, `setup/`, `home/`, `management/`, `ai/`, hoặc trực tiếp trong `screens/` nếu không thuộc module con (như `profile_screen.dart`, `notification_screen.dart`).
- Model mới → `lib/models/`, luôn có `fromMap(Map, String id)` + `toMap()`, field optional dùng `?` và default an toàn trong `fromMap` (`map['x'] ?? default`).
- Logic Firestore/Storage/AI mới → thêm method vào service tương ứng đã có (`FirestoreService`, `StorageService`, `AiService`), **không** tạo Firestore call trực tiếp trong widget/screen.
- Widget tái sử dụng ≥2 nơi → tách ra `lib/widgets/`, không copy-paste.
- Route mới → đăng ký trong `lib/routes/app_routes.dart`, không dùng `Navigator.push` với route string tự do không khai báo.

## 3. Coding Principles (Flutter)

- **Không** lồng `Container > Padding > SizedBox` không cần thiết — dùng property có sẵn (`padding` của `Container`, `margin`, v.v.) để giảm độ sâu widget tree.
- Tách named widget method (`Widget _buildXyz()`) hoặc `class` riêng cho phần UI lặp lại ≥2 lần trong cùng file, thay vì lặp code.
- Luôn dùng `const` constructor khi widget không nhận state động.
- Luôn tham chiếu màu qua `AppColors.*` — **cấm hardcode** `Color(0xFF...)` hoặc `Colors.red` trực tiếp trong widget mới (ngoại lệ: màu tạm thời rõ ràng ghi chú `// TODO` để chuẩn hóa sau).
- Thêm `Semantics` label cho icon-only button quan trọng khi tạo mới (nợ kỹ thuật hiện tại chưa đủ, nhưng code mới phải tuân thủ).
- HTML/SEO-style optimization (meta tag, alt text kiểu web) **không áp dụng** cho Flutter — bỏ qua nếu agent đề xuất nhầm.

## 4. Firestore Query Rules

- **Không** viết query kết hợp `where()` trên field A + `orderBy()` trên field B khác nhau mà chưa kiểm tra composite index tồn tại trong `firestore.indexes.json`. Nếu cần index mới:
  1. Thêm entry vào `firestore.indexes.json`
  2. Ghi rõ trong output của agent rằng **cần chạy `firebase deploy --only firestore:indexes` hoặc tạo thủ công trên Firebase Console** — agent không thể tự apply index lên Firebase thật.
- Nếu chỉ cần sort đơn giản trên tập dữ liệu nhỏ (VD danh sách category, budget theo user), có thể sort **client-side** sau khi lấy `snapshots()` thay vì thêm `orderBy()` — đây là pattern đã dùng trong `streamCategories`, `streamWallets`, `streamBudgets`.
- Mọi write ảnh hưởng tới `wallets.balance` hoặc `budgets.spent` phải đi qua các hàm side-effect có sẵn (`adjustWalletBalance`, `adjustBudgetSpent`) hoặc `runTransaction` như `updateTransactionSafely` — **không** set giá trị tuyệt đối trực tiếp, luôn dùng delta/increment để tránh race condition.

## 5. Bảo mật API Key & Secrets

- **Không bao giờ** dán API key thật (Gemini, Firebase server key, v.v.) trực tiếp vào chat, commit message, hay file sẽ commit vào git.
- Convention bắt buộc: `lib/config/api_keys.dart` (thật, đã có trong `.gitignore`) + `lib/config/api_keys.dart.example` (placeholder, commit vào git). Khi agent cần thêm key mới, phải sửa **cả hai file** theo pattern này.
- `google-services.json`, `GoogleService-Info.plist` không commit (đã có trong `.gitignore`).

## 6. Flutter Web / Cross-platform Caveats

- `Image.file` **không hoạt động trên Flutter Web** — dùng `Image.memory`/`Image.network` tùy nguồn dữ liệu (đã áp dụng trong `add_transaction_screen.dart` qua `Uint8List`).
- **Ảnh hóa đơn lưu cục bộ trên thiết bị** (không dùng Firebase Cloud Storage — xem SCHEMA.md mục 5) — dùng `getApplicationDocumentsDirectory()`, KHÔNG dùng `getTemporaryDirectory()` cho ảnh cần giữ lâu dài. Hiển thị ảnh bằng `Image.file(File(path))`, không dùng `Image.network()`.
- JDK/Gradle version mismatch trên Windows → khai báo `org.gradle.java.home` trong `android/gradle.properties`, không sửa code Dart để "workaround" lỗi build native.

## 7. Gemini / AI Service Rules

- Mọi lời gọi Gemini phải đi qua `AiService._generateWithFallback()` — không gọi `GenerativeModel` trực tiếp trong screen.
- Khi cập nhật `_modelFallbackChain`, phải giữ **ít nhất 2 model dự phòng** (tên model deprecate thường xuyên); không hardcode chỉ 1 model.
- Timeout chuẩn cho 1 lần gọi model: `15s` (đơn lẻ) / `30s` (khi chạy song song trong `Future.wait` như ở `AiInsightScreen`).
- Chat session (`AiChatScreen`) lưu lịch sử **trong bộ nhớ (`_chatHistory`)**, không phải Firestore — không thêm logic lưu chat vào DB trừ khi có yêu cầu rõ ràng (tăng phạm vi ngoài MVP).
- OCR (`extractReceiptInfo`) luôn yêu cầu Gemini trả **JSON thuần túy, không markdown fence** — nếu model trả về kèm ```json, dùng `_stripMarkdownCodeFence()` có sẵn, không viết parser JSON mới trùng lặp.
- **[MỚI — quy tắc cốt lõi sau phản biện hội đồng]** Mọi phép tính số học phục vụ phân tích tài chính (tỷ lệ %, so sánh theo tháng, kiểm tra ngưỡng, tính điểm số) **PHẢI làm bằng Dart thuần trong `FinancialAnalyticsService`, KHÔNG được giao cho Gemini tự tính**. Gemini chỉ nhận kết quả đã tính sẵn (dạng số liệu cụ thể trong prompt) để **diễn giải bằng ngôn ngữ tự nhiên và đề xuất phương án** — không bao giờ dùng Gemini để tự suy ra "tăng bao nhiêu %" hay "có vượt ngưỡng không" từ dữ liệu thô. Đây là ranh giới kiến trúc bắt buộc, dùng để trả lời câu hỏi "AI nhúng hay tự viết" khi bảo vệ khóa luận (xem ARCHITECTURE.md mục 3.4).

## 8. Quy trình giao việc cho AI Coding Tool (Antigravity/Claude Code)

Khi Claude (trong chat này) tạo file `.md` để giao cho Antigravity/Claude Code thực thi, **luôn** theo format ticket sau, đặt ở project root, đặt tên rõ ràng theo bug/feature:

```
# [Tên bug/feature ngắn gọn]

## Context
[Mô tả hiện trạng, file liên quan]

## Root Cause
[Nguyên nhân gốc, không phải triệu chứng]

## Fix Requirements
[Yêu cầu cụ thể, đúng trọng tâm — "đúng trọng tâm, không lan man"]

## Acceptance Criteria
[Cách xác nhận đã fix đúng]
```

- Mỗi file prompt chỉ giải quyết **1 vấn đề** — không gộp nhiều bug không liên quan vào 1 ticket.
- Không tự ý mở rộng phạm vi (VD không tự thêm tính năng mới khi đang fix bug) trừ khi được yêu cầu.
- Sau khi Antigravity/Claude Code báo đã fix, cập nhật `PROGRESS.md` tương ứng nếu hạng mục đó có mặt trong danh sách "Cần làm tiếp".

## 9. Khi mâu thuẫn với tài liệu khác

Thứ tự ưu tiên khi có xung đột: **RULES.md > SCHEMA.md > ARCHITECTURE.md > DESIGN.md > PRD.md** cho các quyết định kỹ thuật cụ thể (vì RULES.md là ràng buộc cứng, còn PRD.md là định hướng sản phẩm ở mức cao). Nếu PRD.md yêu cầu điều gì đó vi phạm RULES.md (VD đổi kiến trúc lưu API key), phải dừng lại và hỏi người dùng thay vì tự quyết.
