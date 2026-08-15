# PRD — Finance AI App

## 1. Tổng quan dự án

**Tên dự án:** Finance AI App
**Loại:** Đồ án tốt nghiệp (khóa luận) — ứng dụng di động
**Nền tảng:** Flutter (Android / iOS / Web) + Firebase
**Bối cảnh:** Ứng dụng quản lý tài chính cá nhân tích hợp AI (Gemini API), tên đề tài khóa luận nhấn mạnh yếu tố "tích hợp AI".

## 2. Mục tiêu

- Giúp người dùng theo dõi thu/chi, quản lý nhiều ví tiền, đặt ngân sách và mục tiêu tiết kiệm trong một ứng dụng duy nhất.
- Tích hợp AI (Gemini) để tạo giá trị khác biệt so với app quản lý tài chính thông thường: phân tích thói quen chi tiêu, dự đoán cuối tháng, chatbot tài chính, OCR hóa đơn.
- Đáp ứng yêu cầu bảo vệ khóa luận: sản phẩm chạy được, demo được đầy đủ luồng chính, có tài liệu kỹ thuật rõ ràng.

## 2.1. Định hướng AI sau phản biện hội đồng (chốt hướng phát triển cuối)

Sau buổi báo cáo, hội đồng góp ý 2 điểm cốt lõi cần cải thiện:
- **Thầy 1:** cần thể hiện rõ phần "tự viết" chứ không chỉ nhúng thẳng Gemini API.
- **Thầy 2:** các phép so sánh/phân tích thông thường (so hôm nay với hôm qua...) người dùng tự làm được; AI phải **tìm ra vấn đề** và **hướng cải thiện cụ thể**, không chỉ tường thuật số liệu.

**Hướng chốt:** chuyển từ mô hình "gọi Gemini phân tích trực tiếp dữ liệu thô" sang kiến trúc phân tầng:

```
Dữ liệu giao dịch (Firestore)
        ↓
Financial Analytics Layer (Dart thuần — KHÔNG gọi AI)
  → tính tỷ lệ chi tiêu/thu nhập theo danh mục
  → tính % thay đổi theo tháng cho từng danh mục
  → phát hiện vấn đề theo NGƯỠNG cụ thể (VD danh mục tăng >30%,
    chiếm >25% thu nhập, tỷ lệ tiết kiệm <20%)
  → tính Điểm sức khỏe tài chính (0-100)
        ↓
Gemini AI (chỉ nhận vấn đề ĐÃ PHÁT HIỆN sẵn, không tự mò từ số thô)
  → giải thích nguyên nhân
  → đề xuất phương án cải thiện có số liệu cụ thể
        ↓
Hiển thị: Điểm sức khỏe + Danh sách vấn đề + Đề xuất từ AI
```

Đây là câu trả lời trực tiếp cho thầy 1 (*"Hệ thống tự tính toán các chỉ số, phát hiện vấn đề bằng logic Dart trước; Gemini chỉ dùng ở bước giải thích nguyên nhân và đề xuất — không quyết định toàn bộ kết quả"*) và thầy 2 (*"vấn đề" không phải do AI tự nói suông, mà do hệ thống phát hiện qua ngưỡng cụ thể, có căn cứ số liệu*).

**Phạm vi triển khai đợt này** (thu hẹp từ đề xuất đầy đủ để vừa thời gian còn lại):
1. ✅ Financial Analytics Layer (tính chỉ số + phát hiện vấn đề theo ngưỡng)
2. ✅ Điểm sức khỏe tài chính (0-100)
3. ✅ Mở rộng `AiInsightScreen` hiển thị đủ 3 phần trên

**Không triển khai đợt này** (ghi vào "Trên horizon" — hướng phát triển tương lai):
- Màn "AI Financial Coach" riêng biệt (dùng chung `AiInsightScreen` mở rộng thay vì tạo màn mới)
- Vòng lặp theo dõi kết quả dài hạn (đề xuất → thực hiện → đo lại sau 1 tháng) — cần thêm collection lưu lịch sử đề xuất + logic so sánh theo thời gian, tốn nhiều thời gian hơn mức còn lại của khóa luận.

## 3. Đối tượng người dùng

- Người dùng cá nhân (không phải doanh nghiệp/nhóm) muốn quản lý thu chi hàng ngày.
- Không có vai trò multi-user chia sẻ ví/ngân sách trong phạm vi MVP (tính năng chia tiền nhóm / Hụi-Họ đã được cân nhắc và **loại bỏ** khỏi phạm vi để tập trung vào tài chính cá nhân).

## 4. Phạm vi (Scope)

### Trong phạm vi (In-scope) — 6 module, 21 màn hình
1. **Auth**: Splash, Onboarding, Login, Register, Forgot Password
2. **Setup**: Khởi tạo hồ sơ, Tạo ví đầu tiên, Chọn danh mục mặc định
3. **Home**: Dashboard (biểu đồ 6 tháng, top danh mục, giao dịch gần đây), Danh sách giao dịch (filter ngày/tuần/tháng), Thêm giao dịch, Chi tiết giao dịch
4. **Management**: Quản lý ví, danh mục, ngân sách, mục tiêu tiết kiệm
5. **AI** (7 tính năng dựa trên Gemini):
   - AI 1: Phân tích thói quen chi tiêu 30 ngày
   - AI 2: Phân tích xu hướng tài chính 6 tháng (biểu đồ trend)
   - AI 3: Dự đoán chi tiêu cuối tháng
   - AI 4: Lập kế hoạch tiết kiệm theo mục tiêu
   - AI 5: Chatbot tài chính (dựa trên dữ liệu Firestore thật của người dùng)
   - AI 6: Gợi ý cắt giảm chi tiêu theo danh mục
   - AI 7: OCR hóa đơn (ML Kit + Gemini) → tự động điền số tiền/merchant/ngày
6. **Notification & Profile**: Thông báo (vượt ngân sách, AI insight), Hồ sơ cá nhân + truy cập nhanh các màn quản lý

### Ngoài phạm vi (Out-of-scope, xem thêm PROGRESS.md)
- Chia sẻ chi tiêu nhóm / Hụi-Họ (đã cân nhắc, quyết định không làm)
- Vai trò Quản trị viên (Web/Admin dashboard)
- Đa ngôn ngữ, Dark Mode thật (hiện là placeholder UI)
- Xuất báo cáo PDF
- Đổi mật khẩu trong Profile (placeholder)
- Cloud Functions proxy cho Gemini API key (dự kiến giai đoạn sau khóa luận)

## 5. Yêu cầu kỹ thuật

| Hạng mục | Công nghệ |
|---|---|
| Framework | Flutter (Dart ≥3.3.0) |
| Backend | Firebase: Authentication, Firestore, Cloud Messaging |
| Lưu trữ ảnh hóa đơn | **Local storage trên thiết bị** (`path_provider`, `getApplicationDocumentsDirectory()`) — xem lý do đổi hướng ở mục 7 |
| AI | Gemini API qua package `google_generative_ai` (gọi trực tiếp từ client trong giai đoạn khóa luận) |
| Biểu đồ | `fl_chart` |
| OCR | `google_mlkit_text_recognition` (on-device) kết hợp Gemini để trích xuất có cấu trúc |
| Ảnh | `image_picker` |
| Font | `google_fonts` |
| Progress bar | `percent_indicator` |
| Firebase Project ID | `finance-ai-app-6df28` |
| Repo | github.com/nguyenduongquoc-beep/finance_ai_app |

## 6. Chỉ số đo lường thành công (Success Metrics)

Với tính chất là sản phẩm khóa luận (không phải sản phẩm thương mại), success metrics tập trung vào **tính hoàn chỉnh và khả năng demo**, không phải growth/retention:

- [ ] Toàn bộ 21 màn hình build và chạy được không crash trên ít nhất 1 nền tảng thật (Android/Web)
- [ ] Luồng chính end-to-end chạy được: Đăng ký → Setup hồ sơ/ví/danh mục → Thêm giao dịch → Xem Dashboard cập nhật đúng số liệu
- [ ] 7/7 tính năng AI trả về kết quả hợp lệ (không lỗi model/timeout) trong bản demo
- [ ] Không còn lỗi hiển thị sai (VD: label tháng sai, biểu đồ lặp nhãn trục X)
- [ ] Giao dịch lưu thành công kèm ảnh hóa đơn trên môi trường build thật (không chỉ localhost/debug)
- [ ] Firestore rules đảm bảo user chỉ truy cập dữ liệu của chính mình (đã có `firestore.rules` mẫu)
- [ ] README/PROGRESS phản ánh đúng trạng thái thật của source code tại thời điểm bảo vệ

## 7. Rủi ro đã biết (theo PROGRESS.md)

- **Ảnh hóa đơn lưu local, không đồng bộ qua cloud** (quyết định kỹ thuật, không phải bug): Firebase Cloud Storage yêu cầu gói Blaze (trả phí) kể từ chính sách mới của Google, project đang ở gói Spark (miễn phí). Sau khi cân nhắc các hướng thay thế (nâng Blaze, Cloudflare R2, lưu base64 trong Firestore), nhóm chọn lưu ảnh cục bộ trên thiết bị vì đơn giản nhất, không cần thẻ thanh toán, không phát sinh dịch vụ bên thứ 3. **Đánh đổi:** ảnh sẽ mất nếu gỡ cài đặt app hoặc đổi thiết bị — chỉ dữ liệu giao dịch (số tiền, ngày, danh mục...) vẫn đồng bộ đầy đủ qua Firestore như bình thường. Đây là hướng phát triển trong tương lai nếu triển khai thực tế (nâng cấp Blaze, khôi phục kiến trúc Cloud Storage đúng như đề cương ban đầu).
- Gemini API key lộ trong client build release → cần Cloud Functions proxy trước khi phát hành thật (không bắt buộc cho khóa luận).
- `Budget.spent` tính bằng `FieldValue.increment` ở client → có thể lệch nếu nhiều thiết bị sửa cùng lúc; giải pháp triệt để là Cloud Function trigger, nằm ngoài phạm vi khóa luận nhưng nên ghi chú trong báo cáo.
