# TICKET 021 — Sửa Dark Mode chưa đồng bộ: rebuild trễ, màu hardcode chưa đổi theo, loại trừ nhóm màn Auth

**Loại:** Bug fix (phát sinh từ ticket 018 — chưa đủ triệt để)
**Độ ưu tiên:** Cao
**File bị ảnh hưởng:** `lib/utils/constants.dart`, `lib/screens/home/home_dashboard_screen.dart`, `lib/screens/home/add_transaction_screen.dart`, `lib/screens/home/transaction_detail_screen.dart`, `lib/screens/home/transaction_list_screen.dart`, `lib/screens/ai/ai_chat_screen.dart`, `lib/screens/ai/ai_insight_screen.dart`, `lib/screens/about_app_screen.dart`, `lib/screens/personal_info_screen.dart`, `lib/widgets/weekly_heatmap_card.dart`, `lib/screens/auth/login_screen.dart`, `lib/screens/auth/register_screen.dart`, `lib/screens/auth/forgot_password_screen.dart`, `lib/screens/auth/splash_screen.dart`, `lib/screens/auth/onboarding_screen.dart`

---

## 1. Context (Bối cảnh)

Sau khi triển khai ticket 018 (Dark Mode thật), phát hiện qua test thực tế 5 vấn đề:

1. **Dashboard không đổi màu ngay** khi bấm công tắc Dark Mode — chỉ đổi đúng sau khi tương tác thêm (VD bấm bộ lọc Th1-Th6/Th7-Th12).
2. **Màn Thêm giao dịch**: nhiều icon, label, ô nhập (Ví thanh toán, Danh mục, Ghi chú, Địa điểm...) vẫn hiện màu sáng/mờ, không đổi theo dark mode, khó đọc.
3. **Màn Sửa giao dịch**: tương tự — icon, label danh mục/ví, vùng text ghi chú vẫn sai màu trong dark mode.
4. **Màn Danh sách giao dịch, AI Chat, Thông tin ứng dụng, AI Insight**: bấm Dark Mode chỉ đổi 1 phần (thường chỉ nền toàn màn), còn **card/nội dung bên trong** vẫn giữ nền sáng — không đồng bộ.
5. **Yêu cầu mới**: 3 màn Đăng nhập, Đăng ký, Quên mật khẩu **không chịu ảnh hưởng của Dark Mode** — luôn giữ giao diện sáng mặc định, bất kể trạng thái Dark Mode toàn app.

## 2. Root Cause

**Nguyên nhân A — Rebuild trễ (mục 1):** Ticket 018 chỉ bọc `ValueListenableBuilder<ThemeMode>` quanh `MaterialApp` ở gốc `main.dart`. Khi `ThemeController.mode` đổi, `MaterialApp` được rebuild, nhưng vì `routes` là 1 `Map` cố định (tham chiếu không đổi), Flutter's Navigator **giữ nguyên các trang đã push trong stack**, không ép các trang đó tự gọi lại `build()`. Những widget dùng trực tiếp `AppColors.xxx` (không qua `Theme.of(context)`, không có cơ chế lắng nghe thay đổi) vẫn hiển thị đúng màu **đã tính từ lần build trước** cho tới khi có 1 lý do nội bộ khác (VD `setState` do đổi bộ lọc) kích hoạt build lại.

**Nguyên nhân B — Hardcode màu cố định (mục 2, 3, 4):** Nhiều màn hình định nghĩa màu **trực tiếp bằng hằng số** (`Colors.white`, `Colors.grey.shade50`, `Colors.grey.shade400`...) thay vì dùng `AppColors.card`/`AppColors.textPrimary`/`AppColors.textSecondary` (đã được ticket 018 biến thành động) — đây là vi phạm `RULES.md` mục 3 tồn tại **từ trước** ticket Dark Mode, chỉ bị lộ ra khi có dark mode thật. Ví dụ cụ thể đã xác nhận: `personal_info_screen.dart` có `fillColor: Colors.grey.shade50` cứng trong `_inputDecoration()`; `weekly_heatmap_card.dart` có `color: Colors.white` cứng cho `Container` chính.

## 3. Fix Requirements

### 3.1. Sửa nguyên nhân A — Đảm bảo mọi màn hình rebuild đúng lúc khi đổi Dark Mode

Bọc **nội dung `build()` của từng màn hình** (không phải chỉ ở gốc `main.dart`) bằng `ValueListenableBuilder<ThemeMode>` cục bộ — đảm bảo màn đó luôn tự rebuild ngay khi `ThemeController.mode` đổi, không phụ thuộc rebuild từ `MaterialApp`. Áp dụng cho **tất cả** màn hình sau (trừ nhóm loại trừ ở mục 3.3):

- `home_dashboard_screen.dart`
- `add_transaction_screen.dart`
- `transaction_detail_screen.dart`
- `transaction_list_screen.dart`
- `ai_chat_screen.dart`
- `ai_insight_screen.dart`
- `about_app_screen.dart`
- `personal_info_screen.dart`
- (và các màn Management/Setup/Notification khác nếu chưa có — audit toàn bộ ~21 màn, áp dụng nhất quán, không chỉ 8 màn bị báo lỗi)

**Cách bọc — ví dụ áp dụng cho `HomeDashboardScreen`:**
```dart
@override
Widget build(BuildContext context) {
  return ValueListenableBuilder<ThemeMode>(
    valueListenable: ThemeController.mode,
    builder: (context, _, __) {
      // Toàn bộ nội dung Scaffold hiện tại đặt ở đây, không đổi logic bên trong
      return Scaffold(
        backgroundColor: AppColors.background,
        ...
      );
    },
  );
}
```
Thêm `import '../../services/theme_controller.dart';` (đường dẫn tương đối tùy vị trí file) vào mỗi màn được sửa.

**Lưu ý quan trọng:** cách này **không** làm mất trạng thái điều hướng hay dữ liệu đang nhập (khác với cách "ép rebuild toàn bộ cây" bằng đổi `key` ở `MaterialApp`, vốn sẽ reset cả Navigator — **KHÔNG được làm theo hướng đó**). Đây chỉ là rebuild cục bộ đúng widget đang hiển thị, giữ nguyên `State` hiện có.

### 3.2. Sửa nguyên nhân B — Audit và thay hardcode màu bằng `AppColors` động

Rà soát **từng file** đã liệt kê, tìm mọi chỗ dùng `Colors.white`, `Colors.grey.shadeXXX`, `Colors.black87` (hoặc tương tự) cho mục đích nền card/surface hoặc chữ chính/phụ → thay bằng đúng token tương ứng:
- Nền card/surface/input field → `AppColors.card`
- Chữ chính (tiêu đề, nội dung quan trọng) → `AppColors.textPrimary`
- Chữ phụ (hint, label mờ, caption) → `AppColors.textSecondary`

**Ví dụ cụ thể cần sửa (đã xác nhận từ code):**

`personal_info_screen.dart` — hàm `_inputDecoration()`:
```dart
// Trước:
fillColor: Colors.grey.shade50,
hintStyle: GoogleFonts.inter(color: Colors.grey.shade400),
prefixIcon: Icon(icon, color: Colors.grey),

// Sau:
fillColor: AppColors.card,
hintStyle: GoogleFonts.inter(color: AppColors.textSecondary),
prefixIcon: Icon(icon, color: AppColors.textSecondary),
```

`weekly_heatmap_card.dart`:
```dart
// Trước:
decoration: BoxDecoration(
  color: Colors.white,
  ...

// Sau:
decoration: BoxDecoration(
  color: AppColors.card,
  ...
```

Áp dụng đúng nguyên tắc tương tự cho **toàn bộ** các chỗ còn lại trong `add_transaction_screen.dart`, `transaction_detail_screen.dart`, `transaction_list_screen.dart`, `ai_chat_screen.dart`, `ai_insight_screen.dart`, `about_app_screen.dart` — rà soát kỹ từng `Container`/`Card`/`TextField`/`Text` có màu hardcode, không bỏ sót.

**Ngoại lệ không cần sửa:** các màu **ngữ nghĩa cố định có chủ đích** theo thiết kế (VD nút "Th1-Th6"/"Th7-Th12" ở Dashboard dùng nền đen cố định theo đúng Figma gốc, các màu `AppColors.income`/`expense`/`warning`/`primary`/`aiAccent` vốn đã cố định theo cả 2 chế độ từ ticket 018) — giữ nguyên, không đổi.

### 3.3. Loại trừ nhóm màn Auth khỏi Dark Mode

**Phạm vi loại trừ:** `login_screen.dart`, `register_screen.dart`, `forgot_password_screen.dart` (theo đúng yêu cầu). Đồng thời áp dụng luôn cho `splash_screen.dart` và `onboarding_screen.dart` (cùng thuộc luồng trước đăng nhập, tránh trường hợp Splash/Onboarding tối nhưng Login lại sáng ngay sau đó, gây giật hình khi chuyển màn) — **nếu đây không đúng ý định, cần điều chỉnh lại phạm vi trước khi thực hiện.**

Thêm 4 hằng số **cố định, không đổi theo Dark Mode** vào `AppColors`:
```dart
// Dùng riêng cho nhóm màn Auth — LUÔN sáng, không phụ thuộc ThemeController
static const Color fixedLightBackground = Color(0xFFF7F8FA);
static const Color fixedLightCard = Colors.white;
static const Color fixedLightTextPrimary = Color(0xFF1A1A1A);
static const Color fixedLightTextSecondary = Color(0xFF757575);
```

Trong 5 file thuộc nhóm loại trừ, thay mọi chỗ đang dùng `AppColors.background`/`.card`/`.textPrimary`/`.textSecondary` (động) bằng đúng bản `fixedLight...` tương ứng. **Không** bọc 5 màn này bằng `ValueListenableBuilder<ThemeMode>` (không cần, vì chúng không đổi màu).

## 4. Không đổi (Out of scope)

- Không đổi cách `ThemeController`/`main.dart` hoạt động ở tầng gốc — vẫn giữ cấu trúc `ValueListenableBuilder` bọc `MaterialApp` như ticket 018, chỉ bổ sung thêm lớp bọc cục bộ ở từng màn.
- Không đổi giá trị các token `AppColors.primary/secondary/income/expense/warning/aiAccent` — giữ nguyên cố định như ticket 018.
- Không đổi màu nút bộ lọc Th1-Th6/Th7-Th12 ở Dashboard (thiết kế cố định theo Figma, không phải bug).
- Không thêm chế độ thứ 3 nào khác ngoài Sáng/Tối.

## 5. Acceptance Criteria

- [ ] Ở bất kỳ màn hình nào (Dashboard, Thêm/Sửa giao dịch, Danh sách giao dịch, AI Chat, AI Insight, Thông tin ứng dụng, Thông tin cá nhân...), bấm công tắc Dark Mode ở Profile → **toàn bộ nội dung màn đang mở đổi màu ngay lập tức**, không cần tương tác thêm gì khác.
- [ ] Màn Thêm giao dịch và Sửa giao dịch: mọi icon, label, ô nhập, vùng ghi chú đều đọc rõ, tương phản tốt ở cả 2 chế độ.
- [ ] Màn AI Insight: các card "Vấn đề & Cơ hội", heatmap, điểm sức khỏe đều đổi nền đúng theo dark mode, không còn card trắng/mờ.
- [ ] Màn Danh sách giao dịch, AI Chat, Thông tin ứng dụng: toàn bộ card/nội dung bên trong đổi màu đồng bộ với nền, không chỉ riêng phần khung ngoài.
- [ ] 3 màn Đăng nhập, Đăng ký, Quên mật khẩu **luôn hiển thị sáng**, không đổi dù Dark Mode đang bật hay tắt — kiểm tra bằng cách bật Dark Mode, đăng xuất, xác nhận màn Login vẫn sáng.
- [ ] Chuyển đổi Sáng ⇄ Tối nhiều lần trong khi đang ở giữa 1 form đang nhập dở (VD đang gõ ghi chú giao dịch) → **không mất dữ liệu đã nhập**, không bị đẩy về màn khác (xác nhận không có hiện tượng reset Navigator).
- [ ] `flutter analyze` không phát sinh lỗi mới.
- [ ] Test tối thiểu: bật/tắt Dark Mode từ 5 màn hình khác nhau (không chỉ từ Profile rồi quay lại Dashboard) để xác nhận rebuild đúng ở mọi điểm vào.
