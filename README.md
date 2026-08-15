# Finance AI App

Ứng dụng quản lý tài chính cá nhân thông minh tích hợp AI trên nền tảng Flutter và Firebase.

## Cấu trúc thư mục

```
lib/
├── main.dart                     # Điểm khởi động app
├── firebase_options.dart         # Cấu hình Firebase (cần chạy flutterfire configure)
├── models/                       # Các model dữ liệu (khớp với schema Firestore)
│   ├── user_model.dart
│   ├── wallet_model.dart
│   ├── category_model.dart
│   ├── transaction_model.dart
│   ├── budget_model.dart
│   ├── saving_goal_model.dart
│   └── notification_model.dart
├── services/                     # Lớp giao tiếp với Firebase & AI
│   ├── auth_service.dart         # Firebase Authentication
│   ├── firestore_service.dart    # CRUD Firestore
│   ├── storage_service.dart      # Upload ảnh (Firebase Storage)
│   └── ai_service.dart           # Gọi Gemini API (7 tính năng AI)
├── screens/
│   ├── auth/                     # Module 1: Splash, Onboarding, Login, Register, Forgot Password
│   ├── setup/                    # Module 2: Khởi tạo hồ sơ, Tạo ví, Chọn danh mục
│   ├── home/                     # Module 3: Dashboard, Danh sách/Thêm/Chi tiết giao dịch
│   ├── management/                # Module 4: Quản lý ví/danh mục/ngân sách/mục tiêu tiết kiệm
│   ├── ai/                       # Module 5: AI Chat, AI Insight, AI Report
│   ├── notification_screen.dart  # Module 6: Thông báo
│   └── profile_screen.dart       # Module 6: Hồ sơ cá nhân
├── widgets/                      # Các widget dùng chung (card, chart, bottom nav)
├── utils/                        # Constants, formatters
└── routes/                       # Định tuyến app_routes.dart
```

## Bước cài đặt

### 1. Cài Flutter packages

```bash
flutter pub get
```

### 2. Kết nối Firebase

Cài Firebase CLI và FlutterFire CLI (nếu chưa có):

```bash
npm install -g firebase-tools
dart pub global activate flutterfire_cli
```

Đăng nhập và cấu hình project:

```bash
firebase login
flutterfire configure
```

Lệnh `flutterfire configure` sẽ tự động ghi đè `lib/firebase_options.dart` với cấu hình thật
(chọn project Firebase, chọn nền tảng Android/iOS).

### 3. Bật các dịch vụ Firebase (trên Firebase Console)

- **Authentication**: Bật Email/Password và Google Sign-In
- **Cloud Firestore**: Tạo database (bắt đầu ở test mode, sau đó áp dụng `firestore.rules` mẫu)
- **Cloud Storage**: Bật để lưu ảnh hóa đơn, avatar
- **Cloud Messaging**: Bật để gửi nhắc nhở (tiền điện, nước, Internet...)

### 4. Cấu hình Gemini API cho tính năng AI

Mở `lib/services/ai_service.dart` và thay `YOUR_GEMINI_API_KEY` bằng API key thật
(lấy tại https://aistudio.google.com/apikey).

⚠️ **Lưu ý bảo mật**: Gọi Gemini trực tiếp từ client sẽ lộ API key trong app khi build release.
Khi lên bản chính thức, nên chuyển sang gọi qua **Cloud Functions** (proxy ẩn API key) thay vì
gọi trực tiếp như hiện tại — cách này phù hợp để phát triển & demo khóa luận trước.

### 5. Android Sign-In config (Google Sign-In)

Cần thêm SHA-1/SHA-256 fingerprint vào Firebase Console > Project Settings > Your apps,
nếu không Google Sign-In trên Android sẽ báo lỗi `ApiException: 10`.

```bash
cd android && ./gradlew signingReport
```

### 6. Chạy app

```bash
flutter run
```

## Trạng thái hiện tại (Scaffold)

✅ Đã tạo:
- Toàn bộ 7 models khớp với schema Firestore trong đề tài
- AuthService, FirestoreService, StorageService, AiService (đầy đủ CRUD + 6/7 tính năng AI)
- 21 màn hình theo đúng 6 module trong tài liệu đề tài
- Bottom Navigation 5 tab + nút "+" nổi để thêm giao dịch nhanh
- Biểu đồ cột (thu/chi theo tháng) và biểu đồ tròn (tỷ lệ chi tiêu) bằng fl_chart

⏳ Cần làm tiếp (xem PROGRESS.md):
- Chạy `flutterfire configure` để kết nối Firebase project thật
- Điền Gemini API key thật
- AI 2 (phân tích xu hướng tài chính) chưa triển khai
- Xuất báo cáo PDF (AI Report Screen) chưa triển khai
- Firebase Cloud Messaging cho nhắc nhở hóa đơn chưa tích hợp
- Dark Mode / đổi ngôn ngữ ở Profile Screen mới là placeholder
- Vai trò Quản trị viên (Web) chưa được xây dựng
