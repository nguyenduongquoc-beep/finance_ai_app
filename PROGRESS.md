# PROGRESS - Finance AI App

## Đã hoàn thành

- [x] Scaffold cấu trúc thư mục Flutter chuẩn (models / services / screens / widgets / utils / routes)
- [x] 7 models: User, Wallet, Category, Transaction, Budget, SavingGoal, Notification
- [x] AuthService (Email/Password + Google Sign-In + Quên mật khẩu)
- [x] FirestoreService (CRUD đầy đủ cho tất cả collections)
- [x] StorageService (upload ảnh hóa đơn + avatar)
- [x] AiService (Gemini API) — AI 1, 2, 3, 4, 5, 6, 7 đã có (AI 7: ML Kit on-device OCR + Gemini structured extraction)
- [x] 21 màn hình theo 6 module trong tài liệu đề tài
- [x] Bottom Navigation 5 tab + nút "+" nổi
- [x] Biểu đồ cột + tròn (fl_chart) cho Dashboard
- [x] firestore.rules mẫu (bảo mật theo userId)

## Đang làm / Cần làm tiếp

- [ ] Chạy `flutterfire configure` để kết nối Firebase project thật (project ID, package name)
- [ ] Điền Gemini API key thật vào `ai_service.dart` (hoặc chuyển sang Cloud Functions proxy)
- [ ] Cấu hình Google Sign-In: thêm SHA-1/SHA-256 vào Firebase Console
- [ ] AI 2: Phân tích xu hướng tài chính (biểu đồ xu hướng qua nhiều tháng)
- [x] AI 7: OCR hóa đơn — đã tích hợp Google ML Kit Text Recognition (on-device) kết hợp Gemini (structured extraction). Fallback gửi ảnh thẳng cho Gemini nếu ML Kit không nhận diện được text.
- [ ] Xuất báo cáo PDF ở AI Report Screen (package `pdf` + `printing`)
- [ ] Firebase Cloud Messaging: nhắc nhở hóa đơn định kỳ (điện, nước, Internet, thuê nhà)
- [x] Dark Mode thật (ThemeController + ValueNotifier + shared_preferences) — đã hoàn thành ở Ticket 018.
- [ ] Đổi ngôn ngữ (đa ngôn ngữ) — hiện tại là placeholder
- [ ] Đổi mật khẩu trong Profile Screen — hiện tại là placeholder
- [ ] (Mở rộng) Vai trò Quản trị viên (Web - Firebase Hosting/Flutter Web)
- [ ] Testing: unit test cho models, widget test cho các màn hình chính
- [ ] Icon mapping: hiện `Category.icon` lưu tên string ('restaurant', 'shopping_bag'...)
      nhưng UI đang tạm dùng `Icons.category` cho tất cả — cần viết hàm map string -> IconData

## Ghi chú kỹ thuật

- Số dư ví được cập nhật tự động (increment/decrement) mỗi khi tạo/xóa giao dịch,
  xem `FirestoreService.adjustWalletBalance()`.
- `Budget.spent` hiện được lưu trực tiếp trong document — cần có Cloud Function
  (trigger onCreate/onDelete transaction) để tự động cộng dồn `spent`, tránh tính toán
  thủ công ở client dẫn đến sai lệch khi nhiều thiết bị cùng sửa.
- AI đang gọi Gemini trực tiếp từ client bằng package `google_generative_ai`
  → lộ API key khi build release. Cân nhắc chuyển sang Cloud Functions như kiến trúc
  đã dùng ở các dự án AI khác (Emulator Suite nếu chưa lên gói Blaze).
