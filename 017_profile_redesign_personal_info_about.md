# TICKET 017 — Redesign màn Profile theo Figma: thống kê tổng quan, phân nhóm chức năng, thêm màn Thông tin cá nhân (đổi mật khẩu) + màn Giới thiệu ứng dụng

**Loại:** UI/UX redesign + Feature mới (đổi mật khẩu, màn giới thiệu)
**Độ ưu tiên:** Cao
**File bị ảnh hưởng:** `lib/screens/profile_screen.dart`, `lib/services/auth_service.dart`
**File mới:** `lib/screens/personal_info_screen.dart`, `lib/screens/about_app_screen.dart`

---

## 1. Context (Bối cảnh)

Redesign toàn bộ màn Cá nhân (`ProfileScreen`) theo thiết kế Figma mới: đổi phần thống kê đầu trang, phân nhóm lại các mục chức năng theo 5 luồng (Tài khoản / Quản lý tài chính / Phân tích & Thông báo / Tùy chỉnh / Khác), thêm 2 màn hình mới (Thông tin cá nhân — có đổi mật khẩu; Giới thiệu ứng dụng).

**Lưu ý phạm vi quan trọng:** 3 mục trong nhóm "Tùy chỉnh" (Ngôn ngữ hiển thị, Tiền tệ mặc định, Chế độ tối) có logic thật sự **thuộc về các ticket riêng** (Dark Mode, Đa ngôn ngữ, Đổi tiền tệ) — ticket này **chỉ dựng đúng layout/vị trí 3 mục đó theo Figma**, chưa nối logic thật, tránh trùng lặp công việc với các ticket sẽ làm sau.

## 2. Fix Requirements

### 2.1. `lib/screens/profile_screen.dart` — Redesign toàn bộ

**a) Phần đầu trang (Header):**
- Giữ nguyên avatar, tên hiển thị, email — chỉ đổi style theo Figma.
- **Xóa** dòng "Thu nhập: X/tháng" hiện tại.
- **Thêm 3 số liệu thống kê** ngang hàng: **Tổng ví / Tổng danh mục / Tổng giao dịch**, style số lớn màu `AppColors.income` (xanh), label nhỏ bên dưới — đúng theo Figma. Lấy dữ liệu qua 3 `StreamBuilder` lồng nhau (tái sử dụng `streamWallets`, `streamCategories`, `streamTransactions` đã có sẵn trong `FirestoreService`, không thêm hàm mới):

```dart
StreamBuilder<List<Wallet>>(
  stream: firestoreService.streamWallets(uid),
  builder: (context, walletSnap) {
    final walletCount = walletSnap.data?.length ?? 0;
    return StreamBuilder<List<Category>>(
      stream: firestoreService.streamCategories(uid),
      builder: (context, catSnap) {
        final categoryCount = catSnap.data?.length ?? 0;
        return StreamBuilder<List<AppTransaction>>(
          stream: firestoreService.streamTransactions(uid), // toàn bộ lịch sử
          builder: (context, txSnap) {
            final transactionCount = txSnap.data?.length ?? 0;
            // build 3 số liệu ở đây
          },
        );
      },
    );
  },
)
```

**b) Nhóm "TÀI KHOẢN":**
- Mục **"Thông tin cá nhân"** (icon người dùng) → điều hướng tới `PersonalInfoScreen` (màn mới, mục 2.2).

**c) Nhóm "QUẢN LÝ TÀI CHÍNH"** — giữ nguyên 4 mục đã liên kết sẵn, chỉ đổi style theo Figma:
- Quản lý ví → `WalletManagementScreen`
- Quản lý danh mục → `CategoryManagementScreen`
- Ngân sách & hạn mức → `BudgetManagementScreen`
- Mục tiêu tiết kiệm → `SavingGoalScreen`

**d) Nhóm "PHÂN TÍCH & THÔNG BÁO":**
- Báo cáo AI → `AiReportScreen` (đã liên kết sẵn, chỉ đổi style/vị trí).
- Thông báo → `NotificationScreen` (đã liên kết sẵn, chỉ đổi style/vị trí).

**e) Nhóm "TÙY CHỈNH"** (layout only, logic thuộc ticket khác):
- **Ngôn ngữ hiển thị** — hiện label bên phải `'Tiếng Việt'` (giá trị mặc định tĩnh). Bấm vào → tạm thời hiện `SnackBar('Tính năng đang được phát triển')` (KHÔNG điều hướng đi đâu — màn chọn ngôn ngữ thuộc ticket riêng). Thêm comment `// TODO: nối màn chọn ngôn ngữ ở ticket đa ngôn ngữ`.
- **Tiền tệ mặc định** — hiện label `'VNĐ'` tĩnh. Tương tự, bấm vào hiện `SnackBar` tạm, comment `// TODO: nối màn chọn tiền tệ`.
- **Chế độ tối** — giữ đúng `SwitchListTile` hiện có (`value: false`, `onChanged` rỗng), comment `// TODO: nối logic đổi ThemeMode ở ticket Dark Mode`. Icon đổi theo Figma nhưng **chưa** đổi động theo trạng thái (vì logic thật chưa có).

**f) Nhóm "KHÁC":**
- **Thông tin về ứng dụng** → điều hướng tới `AboutAppScreen` (màn mới, mục 2.3).

**g) Nút đăng xuất + text phiên bản:** giữ đúng style hiện có (`"Phiên bản hiện tại: v1.0.0"` — dùng chuỗi tĩnh, **không** cần thêm package đọc version động, đúng yêu cầu giữ đơn giản).

### 2.2. `lib/screens/personal_info_screen.dart` (MỚI) — Thông tin cá nhân + Đổi mật khẩu

**a) Phần thông tin cá nhân (có thể chỉnh sửa):**
- Avatar (bấm để đổi — tái sử dụng đúng pattern chọn ảnh từ thư viện + `StorageService.uploadAvatar()` đã có).
- Tên hiển thị (`TextField`, lưu qua `updateUserProfile(uid, {'name': ...})`).
- Email — hiển thị dạng **chỉ đọc** (không cho sửa trực tiếp tại đây, đổi email Firebase Auth cần luồng riêng phức tạp hơn, ngoài phạm vi ticket này).
- Thu nhập hàng tháng, Nghề nghiệp, Mục tiêu tiết kiệm (mô tả) — các field optional có sẵn trong `AppUser`, cho chỉnh sửa tương tự màn Setup.
- Nút "Lưu thay đổi" → gọi `updateUserProfile()` với các field đã sửa.

**b) Phần đổi mật khẩu (chỉ hiện nếu tài khoản đăng nhập bằng Email/Password):**

Kiểm tra provider đăng nhập trước khi hiện phần này:
```dart
final isEmailProvider = FirebaseAuth.instance.currentUser?.providerData
    .any((p) => p.providerId == 'password') ?? false;
```
- Nếu `isEmailProvider == false` (tài khoản đăng nhập Google) → hiện thông báo tĩnh: *"Tài khoản đang đăng nhập bằng Google, không thể đổi mật khẩu tại đây."*, ẩn hoàn toàn form đổi mật khẩu.
- Nếu `true` → hiện 3 field: **Mật khẩu hiện tại**, **Mật khẩu mới**, **Xác nhận mật khẩu mới** (đều `obscureText`, có validate: mật khẩu mới ≥6 ký tự, xác nhận phải khớp mật khẩu mới).
- Nút **"Cập nhật mật khẩu"** → gọi hàm mới `AuthService.changePassword()` (mục 2.4). Xử lý lỗi rõ ràng: sai mật khẩu hiện tại → báo `"Mật khẩu hiện tại không đúng"`; lỗi khác → báo chung `"Không thể đổi mật khẩu, vui lòng thử lại"`.
- Bên dưới form, thêm link **"Quên mật khẩu hiện tại?"** → gọi lại `AuthService.sendPasswordResetEmail(user.email)` (hàm đã có sẵn, dùng lại nguyên vẹn), hiện `SnackBar` xác nhận đã gửi email.

### 2.3. `lib/screens/about_app_screen.dart` (MỚI) — Giới thiệu ứng dụng

Màn tĩnh, không cần Firestore/state phức tạp, gồm:
- Logo/icon ứng dụng + tên **"Finance AI"** + dòng phiên bản (dùng lại chuỗi tĩnh `AppStrings.appName` từ `constants.dart`).
- Đoạn mô tả ngắn về ứng dụng (2-3 câu, mục đích: quản lý tài chính cá nhân tích hợp AI).
- Danh sách tính năng nổi bật (bullet, VD: "Quản lý đa ví", "Ngân sách thông minh", "Trợ lý AI phân tích chi tiêu"...).
- Dòng credit công nghệ sử dụng (Flutter, Firebase, Gemini AI).
- Thông tin liên hệ/email hỗ trợ (placeholder, có thể để trống hoặc email mẫu).
- Dòng bản quyền cuối trang (VD `"© 2026 Finance AI. All rights reserved."`).

### 2.4. `lib/services/auth_service.dart` — thêm hàm đổi mật khẩu

```dart
/// Đổi mật khẩu — yêu cầu xác thực lại (re-authenticate) trước khi đổi,
/// theo đúng yêu cầu bảo mật của Firebase Auth.
Future<void> changePassword({
  required String currentPassword,
  required String newPassword,
}) async {
  final user = _auth.currentUser;
  if (user == null || user.email == null) {
    throw Exception('Người dùng chưa đăng nhập hoặc không có email');
  }
  final credential = EmailAuthProvider.credential(
    email: user.email!,
    password: currentPassword,
  );
  await user.reauthenticateWithCredential(credential);
  await user.updatePassword(newPassword);
}
```

## 3. Không đổi (Out of scope)

- Không triển khai logic thật cho đổi ngôn ngữ, đổi tiền tệ, dark mode — chỉ dựng UI/vị trí đúng Figma, để dành cho các ticket riêng.
- Không cho sửa email trực tiếp trong `PersonalInfoScreen`.
- Không thêm package đọc version động (`package_info_plus`) — dùng chuỗi tĩnh.
- Không đổi `WalletManagementScreen`, `CategoryManagementScreen`, `BudgetManagementScreen`, `SavingGoalScreen`, `AiReportScreen`, `NotificationScreen` — chỉ liên kết, không sửa nội dung bên trong các màn đó.
- Không thêm route tĩnh mới vào `app_routes.dart` cho 2 màn mới — dùng `Navigator.push(MaterialPageRoute(...))` trực tiếp, đúng pattern hiện có của `ProfileScreen`.

## 4. Acceptance Criteria

- [ ] Màn Profile hiện đúng 3 số liệu (Tổng ví/Danh mục/Giao dịch), cập nhật đúng ngay khi thêm/xóa ví, danh mục, hoặc giao dịch.
- [ ] 5 nhóm mục hiển thị đúng thứ tự và đúng các mục con như thiết kế Figma.
- [ ] Bấm từng mục trong "Quản lý tài chính" và "Phân tích & Thông báo" → điều hướng đúng màn hình tương ứng, không lỗi.
- [ ] Bấm "Thông tin cá nhân" → vào đúng màn mới, sửa tên/thu nhập/nghề nghiệp → lưu thành công, quay lại Profile thấy tên cập nhật đúng.
- [ ] Đổi ảnh đại diện ở màn Thông tin cá nhân → ảnh cập nhật đúng, hiển thị lại đúng ở cả Profile lẫn Personal Info.
- [ ] Tài khoản đăng nhập Email/Password → hiện đầy đủ form đổi mật khẩu; nhập sai mật khẩu hiện tại → báo lỗi rõ ràng, không crash.
- [ ] Đổi mật khẩu đúng (mật khẩu hiện tại đúng, mật khẩu mới hợp lệ và khớp xác nhận) → thành công, đăng xuất và đăng nhập lại bằng mật khẩu mới hoạt động đúng.
- [ ] Bấm "Quên mật khẩu hiện tại?" → nhận được email đặt lại mật khẩu.
- [ ] Tài khoản đăng nhập Google → **không** hiện form đổi mật khẩu, hiện đúng thông báo giải thích lý do.
- [ ] Bấm "Thông tin về ứng dụng" → vào đúng màn giới thiệu, nội dung hiển thị đầy đủ, không lỗi.
- [ ] Bấm 3 mục trong "Tùy chỉnh" (Ngôn ngữ/Tiền tệ/Chế độ tối) → không crash, hiện đúng thông báo tạm thời hoặc giữ nguyên trạng thái tĩnh như mô tả.
- [ ] `flutter analyze` không phát sinh lỗi/warning mới.
