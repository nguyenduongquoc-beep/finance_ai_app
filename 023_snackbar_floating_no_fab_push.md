# TICKET 023 — Chuẩn hóa SnackBar toàn app sang kiểu "floating", không đẩy FAB/tab bar khi hiện thông báo

**Loại:** UI/UX fix
**Độ ưu tiên:** Trung bình
**File mới:** `lib/widgets/app_snackbar.dart`
**File bị ảnh hưởng:** Toàn bộ file trong app đang gọi `ScaffoldMessenger.of(context).showSnackBar(...)` (liệt kê ở mục 3)

---

## 1. Context (Bối cảnh)

Khi hiện thông báo dạng SnackBar (VD "Tính năng đang được phát triển" ở Profile, hay các thông báo lỗi/thành công khắp app), Flutter mặc định dùng `SnackBarBehavior.fixed` — hành vi mặc định này **tự động đẩy nút "+" (FloatingActionButton) nổi ở giữa tab bar lên cao hơn** để chừa chỗ cho SnackBar, gây giật hình, mất thẩm mỹ, đặc biệt rõ với layout `BottomAppBar` + FAB notch đang dùng.

## 2. Root Cause

Đây không phải bug logic, mà là hành vi **mặc định** của `SnackBar` khi `behavior` không được chỉ định (mặc định `SnackBarBehavior.fixed`) trong 1 `Scaffold` có khai báo `floatingActionButton`. Cách khắc phục chuẩn: đổi sang `SnackBarBehavior.floating` — SnackBar khi đó hiển thị như 1 thẻ nổi độc lập, có `margin` riêng, **không** kích hoạt cơ chế đẩy FAB.

## 3. Fix Requirements

### 3.1. Tạo `lib/widgets/app_snackbar.dart` (MỚI) — helper dùng chung

```dart
import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// ============================================================
/// APP SNACKBAR
/// Helper hiển thị SnackBar thống nhất toàn app — dùng kiểu "floating"
/// để KHÔNG đẩy FloatingActionButton (+) lên khi hiện thông báo.
/// ============================================================
class AppSnackbar {
  static void show(BuildContext context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: isError ? Colors.white : AppColors.textPrimary),
        ),
        backgroundColor: isError ? AppColors.expense : AppColors.card,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
```

**Giải thích các giá trị:**
- `behavior: SnackBarBehavior.floating` — điểm mấu chốt, ngăn hành vi đẩy FAB.
- `margin: EdgeInsets.fromLTRB(16, 0, 16, 90)` — margin đáy 90px đủ để SnackBar nổi lên **trên** `BottomAppBar` + nút "+" thay vì đè lên, có khoảng cách đẹp.
- `ScaffoldMessenger.of(context).hideCurrentSnackBar()` gọi trước khi show — tránh chồng nhiều SnackBar lên nhau nếu người dùng bấm liên tục nhiều hành động gây lỗi liên tiếp.
- Tham số `isError` — dùng nền đỏ (`AppColors.expense`) cho thông báo lỗi, nền `AppColors.card` (đổi đúng theo Dark Mode) cho thông báo thường.

### 3.2. Áp dụng thay thế trên toàn app

Rà soát **toàn bộ** các nơi đang gọi trực tiếp:
```dart
ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(content: Text('...')),
);
```
→ đổi thành:
```dart
AppSnackbar.show(context, '...');
```
hoặc với thông báo lỗi:
```dart
AppSnackbar.show(context, '...', isError: true);
```

**Danh sách file cần rà soát (không giới hạn, audit toàn bộ project):**
- `lib/screens/profile_screen.dart` (placeholder "Tính năng đang phát triển" ở Ngôn ngữ/Tiền tệ)
- `lib/screens/home/add_transaction_screen.dart`
- `lib/screens/home/transaction_detail_screen.dart` (nếu có)
- `lib/screens/management/wallet_management_screen.dart`
- `lib/screens/management/category_management_screen.dart`
- `lib/screens/management/budget_management_screen.dart`
- `lib/screens/management/saving_goal_screen.dart`
- `lib/screens/personal_info_screen.dart`
- `lib/screens/language_selection_screen.dart`, `lib/screens/currency_selection_screen.dart` (nếu đã tạo)
- Bất kỳ file nào khác có gọi `ScaffoldMessenger.of(context).showSnackBar` — dùng tìm kiếm toàn project (`grep`/tìm kiếm "showSnackBar") để đảm bảo không sót.

Thêm `import '../widgets/app_snackbar.dart';` (đường dẫn tương đối tùy vị trí file) vào mỗi file được sửa.

## 4. Không đổi (Out of scope)

- Không đổi nội dung/text của bất kỳ thông báo nào — chỉ đổi cách gọi hiển thị.
- Không đổi các thông báo lỗi hiển thị dạng text tĩnh trong form (VD dòng `_errorMessage` màu đỏ ở Login/Register/Forgot Password) — đó không phải SnackBar, không thuộc phạm vi ticket này.
- Không tinh chỉnh riêng margin cho từng màn hình cụ thể (VD màn không có bottom nav bar hiển thị như Add Transaction sẽ có khoảng trống dư ở đáy SnackBar — chấp nhận đánh đổi nhỏ này để đồng nhất toàn app, không tối ưu riêng lẻ).

## 5. Acceptance Criteria

- [ ] Bấm vào mục "Ngôn ngữ hiển thị"/"Tiền tệ mặc định" (placeholder) ở Profile → SnackBar hiện nổi phía trên tab bar, **không** còn hiện tượng nút "+" bị đẩy lên.
- [ ] Test tương tự với ít nhất 3 thông báo khác trong app (VD báo lỗi lưu giao dịch thất bại, báo lỗi mạng khi xóa ví, báo thành công khi lưu thông tin cá nhân) — toàn bộ đều hiện dạng nổi, không đẩy FAB.
- [ ] Thông báo lỗi (`isError: true`) hiện nền đỏ chữ trắng rõ ràng; thông báo thường hiện đúng theo Dark Mode (nền/chữ đổi màu đúng khi bật/tắt Dark Mode).
- [ ] Bấm liên tiếp nhiều hành động gây thông báo nhanh (VD bấm nhiều mục placeholder liên tục) → không bị chồng nhiều SnackBar lên nhau.
- [ ] `flutter analyze` không phát sinh lỗi mới.
