# ARCHITECTURE — Finance AI App

## 1. Kiến trúc tổng thể (Top-Level)

```
┌─────────────────────────────────────────────────────────┐
│                      UI Layer (screens/)                  │
│   StatefulWidget/StatelessWidget + StreamBuilder           │
└───────────────────────────┬─────────────────────────────┘
                            │ gọi trực tiếp (no ViewModel/BLoC)
┌───────────────────────────▼─────────────────────────────┐
│                    Service Layer (services/)              │
│  AuthService · FirestoreService · StorageService ·         │
│  AiService · TemplateService                               │
└──────────┬────────────────┬─────────────────┬────────────┘
           │                │                 │
   ┌───────▼──────┐  ┌──────▼───────┐  ┌──────▼───────┐
   │ Firebase Auth │  │  Firestore    │  │  Gemini API   │
   │               │  │  + Storage    │  │ (google_gen…) │
   └───────────────┘  └──────────────┘  └───────────────┘
```

- **Không có lớp State Management tập trung** (Provider có trong `pubspec.yaml` nhưng chưa được dùng thực sự trong code hiện tại — toàn bộ state là `setState` cục bộ trong từng `StatefulWidget`). Đây là điểm cần lưu ý: nếu bổ sung Provider/Riverpod về sau, cần refactor có chủ đích, không trộn lẫn hai cách quản lý state.
- **Data binding thời gian thực:** UI lắng nghe trực tiếp `Stream<T>` từ `FirestoreService` qua `StreamBuilder` — không có cache layer trung gian, không có local database (SQLite/Hive). Mọi lần mở màn hình = một Firestore query mới.

## 2. Folder Structure (thực tế trong repo)

```
lib/
├── main.dart                     # Khởi tạo Firebase, MaterialApp, ThemeData
├── firebase_options.dart         # Sinh bởi `flutterfire configure`
├── config/
│   ├── api_keys.dart             # (gitignored) chứa geminiApiKey thật
│   └── api_keys.dart.example     # Template commit vào git
├── models/                       # Immutable data classes, khớp 1-1 với Firestore schema
│   ├── user_model.dart           (AppUser)
│   ├── wallet_model.dart         (Wallet)
│   ├── category_model.dart       (Category)
│   ├── transaction_model.dart    (AppTransaction)
│   ├── budget_model.dart         (Budget)
│   ├── saving_goal_model.dart    (SavingGoal)
│   ├── notification_model.dart   (AppNotification)
│   ├── quick_template.dart       (QuickTemplate — sub-collection users/{uid}/quickTemplates)
│   ├── trend_result.dart         (kết quả AI 2 - phân tích xu hướng)
│   ├── receipt_info.dart         (kết quả AI 7 - OCR hóa đơn)
│   └── financial_issue.dart      # MỚI — 1 "vấn đề tài chính" đã phát hiện (title, mức độ, số liệu, ngưỡng vi phạm)
├── services/
│   ├── auth_service.dart         # Firebase Auth: email/password, Google Sign-In, reset password
│   ├── firestore_service.dart    # CRUD toàn bộ 7 collection + logic nghiệp vụ (adjustWalletBalance, adjustBudgetSpent, reassign-and-delete...)
│   ├── storage_service.dart      # Lưu/xóa ảnh hóa đơn CỤC BỘ trên thiết bị (path_provider) — không dùng Firebase Cloud Storage
│   ├── ai_service.dart           # Gọi Gemini, có model fallback chain, quản lý chat session
│   ├── financial_analytics_service.dart  # MỚI — tính chỉ số + phát hiện vấn đề bằng ngưỡng (Dart thuần, KHÔNG gọi AI)
│   └── template_service.dart     # CRUD quick templates (sub-collection riêng theo user)
├── screens/
│   ├── auth/                     # Module 1: Splash, Onboarding, Login, Register, ForgotPassword
│   ├── setup/                    # Module 2: ProfileSetup, WalletSetup, CategorySetup (3-step onboarding)
│   ├── home/                     # Module 3: HomeDashboard, TransactionList, AddTransaction, TransactionDetail
│   ├── management/                # Module 4: Wallet/Category/Budget/SavingGoal management
│   ├── ai/                       # Module 5: AiChatScreen, AiInsightScreen, AiReportScreen
│   ├── notification_screen.dart  # Module 6
│   └── profile_screen.dart       # Module 6
├── widgets/                      # Component tái sử dụng: cards, charts, numpad, error widget, main nav
├── utils/
│   ├── constants.dart            # AppColors, AppStrings, default categories, enums
│   ├── formatters.dart           # Format tiền tệ/ngày (intl, locale vi_VN)
│   └── validation_utils.dart     # Kiểm tra vượt số dư ví / vượt ngân sách trước khi lưu giao dịch
└── routes/
    └── app_routes.dart           # Named routes tĩnh (không dùng go_router)
```

## 3. Data Flow chính

### 3.1. Luồng đọc dữ liệu (Read)
```
Screen (StatefulWidget)
  → FirestoreService.streamX(uid, ...)
  → Firestore .snapshots() (real-time listener)
  → .map() convert sang List<Model> qua Model.fromMap()
  → StreamBuilder rebuild UI khi có thay đổi
```
Lưu ý quan trọng: các query kết hợp `where()` + `orderBy()` trên **khác field** (VD `transactions`: `where('userId')` + `orderBy('date')`) **yêu cầu composite index** trong Firestore Console — xem `firestore.indexes.json`. Nếu thiếu index, query fail âm thầm/exception runtime chứ không phải lỗi biên dịch.

### 3.2. Luồng ghi giao dịch (Write) — quan trọng nhất, đã atomic hóa (ticket 010)
```
AddTransactionScreen._handleSave()
  → (optional) StorageService.uploadReceiptImage() — lưu ảnh CỤC BỘ trên thiết bị,
     hiếm khi fail (không phụ thuộc mạng); nếu fail vẫn tiếp tục lưu giao dịch
     KHÔNG kèm ảnh (đã có try/catch fallback)
  → FirestoreService.createTransaction(tx) — chạy trong 1 _db.runTransaction() DUY NHẤT:
      1. Ghi document vào collection `transactions`
      2. Cập nhật số dư ví (đọc balance hiện tại trong transaction, cộng/trừ, ghi lại)
      3. Nếu type == 'expense' → cập nhật spent của budget tương ứng (nếu có)
      → Cả 3 bước ATOMIC: tất cả cùng thành công hoặc tất cả rollback, không còn
        trạng thái ghi dở dang (đã sửa ở ticket 010, trước đó 3 bước là 3 lệnh
        Firestore độc lập, có thể ghi dở nếu mất mạng giữa chừng)
      4. Sau khi transaction commit, đọc lại budget để kiểm tra cảnh báo vượt 90%
         → nếu có, tạo AppNotification (nằm NGOÀI transaction, không cần atomic)
```
Sửa/xóa giao dịch (`updateTransactionSafely`, `deleteTransaction`) phải hoàn tác đúng các side-effect này để tránh lệch số liệu ví/ngân sách.

**Transfer (chuyển tiền giữa 2 ví)** — xử lý trong cùng `runTransaction()`:
- `createTransaction`: trừ `amount` khỏi ví nguồn (`walletId`), cộng `amount` vào ví đích (`toWalletId`), dùng `FieldValue.increment()` cho cả hai. **Không** cập nhật budget (transfer không phải income/expense).
- `updateTransactionSafely`: bước 1 hoàn tác transfer cũ (cộng lại ví nguồn, trừ lại ví đích), bước 2 áp dụng transfer mới — tất cả atomic trong 1 `runTransaction`.
- `deleteTransaction`: hoàn tác đúng số dư cả 2 ví (cộng lại ví nguồn, trừ lại ví đích).
- Validate: ví nguồn ≠ ví đích, `toWalletId` không được null/empty.

### 3.3. Luồng AI
```
Screen → AiService.<method>()
  → _generateWithFallback(content): thử lần lượt các model trong _modelFallbackChain
      cho đến khi có model trả lời thành công hoặc hết danh sách → throw
  → GenerativeModel(model, apiKey).generateContent(content).timeout(15s)
```
- `AiChatScreen` giữ `_chatHistory` (List<Content>) trong bộ nhớ instance của `AiService` — **mất khi thoát app** (không lưu Firestore), chỉ tồn tại trong 1 phiên chat.
- `AiInsightScreen` chạy 3 tác vụ AI song song bằng `Future.wait` (spending habits, month-end prediction, trend analysis), mỗi tác vụ có `.timeout(30s)` + `.catchError` riêng để 1 tác vụ lỗi không làm hỏng cả màn hình.

### 3.4. Luồng Financial Analytics Layer — MỚI (định hướng sau phản biện hội đồng, xem PRD.md mục 2.1)

```
AiInsightScreen mở màn
  → FinancialAnalyticsService (Dart thuần, KHÔNG gọi Gemini):
      1. Tính tổng thu/chi/từng danh mục tháng này VÀ tháng trước (để so sánh %)
      2. Với mỗi danh mục: nếu % thay đổi vượt ngưỡng (VD >30%) → tạo FinancialIssue
      3. Nếu 1 danh mục chiếm > ngưỡng % thu nhập (VD >25%) → tạo FinancialIssue
      4. Tính tỷ lệ tiết kiệm = (thu - chi) / thu; nếu < ngưỡng (VD <20%) → tạo FinancialIssue
      5. Tính Điểm sức khỏe tài chính (0-100) từ tổ hợp các chỉ số trên
      → Trả về: List<FinancialIssue> + điểm số (int) — HOÀN TOÀN không gọi AI ở bước này
  → Nếu List<FinancialIssue> không rỗng:
      AiService gửi CHÍNH XÁC danh sách vấn đề đã phát hiện (kèm số liệu) cho Gemini,
      yêu cầu giải thích nguyên nhân + đề xuất phương án có số liệu cụ thể
      (KHÁC với AI 1/AI 3 cũ: không đưa data thô, chỉ đưa vấn đề đã lọc sẵn)
  → Hiển thị: Điểm sức khỏe (đầu trang) + Danh sách vấn đề (badge màu theo mức độ)
      + Đề xuất từ Gemini cho từng vấn đề
```

**Nguyên tắc cốt lõi** (xem thêm RULES.md): mọi phép tính số học (%, so sánh, ngưỡng) đều làm bằng Dart **trước**, Gemini chỉ nhận kết quả đã tính sẵn để diễn giải bằng ngôn ngữ tự nhiên — không giao phó việc tính toán cho Gemini. Đây là điểm khác biệt kiến trúc dùng để trả lời câu hỏi "AI nhúng hay tự viết" của hội đồng.

**Không thuộc phạm vi đợt này** (xem PRD.md mục 2.1): không lưu lịch sử `FinancialIssue`/điểm số qua Firestore — tính lại from scratch mỗi lần mở màn hình (không có vòng lặp theo dõi tiến độ dài hạn).

## 4. Design Methodologies & Patterns đang áp dụng

| Pattern | Áp dụng ở đâu | Ghi chú |
|---|---|---|
| Service Layer (không phải Repository interface) | `services/*.dart` | Class cụ thể, không có abstract interface — chấp nhận được ở quy mô khóa luận |
| Tách tầng tính toán khỏi tầng AI | `FinancialAnalyticsService` → `AiService` | MỚI — mọi phép tính (%, ngưỡng, điểm số) làm bằng Dart trước, Gemini chỉ diễn giải kết quả đã có sẵn, không tự tính toán số học |
| Model với `fromMap`/`toMap` | tất cả `models/*.dart` | Convention nhất quán, dễ mock/test |
| Stream-based reactive UI | mọi `StreamBuilder` trong `screens/` | Không cache — mỗi lần build lại widget tree sẽ tạo listener mới nếu không cẩn thận (rủi ro hiệu năng nếu lồng StreamBuilder sâu) |
| Atomic write qua `runTransaction` | `createTransaction()`, `updateTransactionSafely()` trong `FirestoreService` | Cả 2 hàm ghi giao dịch quan trọng nhất đều atomic (sửa ở ticket 010) — không còn rủi ro ghi dở dang giữa doc transaction / số dư ví / budget spent |
| Fallback chain | `AiService._generateWithFallback` | Che giấu lỗi model deprecated/quota=0 khỏi người dùng cuối |
| Named-route tĩnh | `app_routes.dart` | Đơn giản, phù hợp app không cần deep-link phức tạp |

## 5. Nợ kiến trúc đã biết (Known Technical Debt)

1. **Provider trong dependencies nhưng không dùng** → dọn dẹp hoặc áp dụng thật khi refactor state management.
2. **Gemini gọi trực tiếp từ client** → lộ API key trong build release; giải pháp đúng là Cloud Functions proxy (ghi rõ trong README, chấp nhận tạm thời cho khóa luận).
3. **Ảnh hóa đơn lưu cục bộ trên thiết bị, không đồng bộ qua cloud** (quyết định kỹ thuật, xem PRD.md mục 7 để biết lý do) → mất ảnh nếu gỡ cài đặt/đổi thiết bị; dữ liệu giao dịch (số liệu) vẫn đồng bộ đầy đủ qua Firestore, không bị ảnh hưởng.
4. **Không có lớp cache/offline-first** → mọi màn hình phụ thuộc kết nối mạng ổn định tới Firestore (riêng thao tác lưu ảnh hóa đơn từ ticket này trở đi KHÔNG còn phụ thuộc mạng nữa, vì lưu local).
5. **Icon mapping cho `Category.icon` (String) chưa triển khai** → toàn bộ UI tạm dùng icon mặc định.
