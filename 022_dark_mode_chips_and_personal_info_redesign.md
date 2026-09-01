# TICKET 022 — Sửa nốt Dark Mode ở nhóm Chip + Redesign Thông tin cá nhân (bỏ Mục tiêu tiết kiệm, hiện dữ liệu hồ sơ ở Dashboard, cải tiến đổi mật khẩu)

**Loại:** Bug fix (Dark Mode) + UI/UX redesign
**Độ ưu tiên:** Cao
**File bị ảnh hưởng:** `lib/screens/ai/ai_chat_screen.dart`, `lib/screens/home/transaction_list_screen.dart`, `lib/screens/personal_info_screen.dart`, `lib/screens/home/home_dashboard_screen.dart`

---

## PHẦN A — Sửa nốt lỗi Dark Mode: nhóm Chip chữ vô hình trên nền sáng

### Context
Sau ticket 021, phát hiện thêm: các **Chip** (gợi ý câu hỏi ở AI Chat, tag lọc loại giao dịch ở Transaction List) khi ở trạng thái **chưa chọn** vẫn giữ nền sáng cố định, trong khi chữ dùng `AppColors.textPrimary` (đã là màu gần trắng trong dark mode) → chữ gần như vô hình trên nền sáng. Đây là lỗi cùng loại đã sửa cho Container/Card ở ticket 021, nhưng nhóm widget Chip ở 2 file này chưa được audit.

### Root Cause
`ActionChip`/`ChoiceChip` ở 2 file này có `backgroundColor` (trạng thái chưa chọn) đang hardcode sáng (hoặc dùng màu opacity nhạt cố định không đổi theo dark mode), trong khi `labelStyle`/màu chữ lại tham chiếu `AppColors.textPrimary` (động) — 2 giá trị không đồng bộ, gây ra tổ hợp sáng-trên-sáng hoặc sáng chữ-trên-sáng nền không tương phản.

### Fix Requirements

**`ai_chat_screen.dart` — `_buildSuggestions()`:**
```dart
ActionChip(
  label: Text(suggestions[i], style: TextStyle(fontSize: 12, color: AppColors.textPrimary)),
  backgroundColor: AppColors.card, // đổi từ màu cố định sang AppColors.card (động)
  side: BorderSide(color: AppColors.aiAccent.withOpacity(0.3)),
  onPressed: _isSending ? null : () => _sendMessage(suggestions[i]),
),
```

**`transaction_list_screen.dart` — hàm build tag "Tất cả/Thu nhập/Chi tiêu":**
```dart
ChoiceChip(
  label: Text(label),
  selected: selected,
  onSelected: (_) => setState(() => _typeFilter = value),
  selectedColor: AppColors.primary,
  backgroundColor: AppColors.card, // MỚI — đổi từ mặc định/hardcode sang AppColors.card
  labelStyle: TextStyle(
    color: selected ? Colors.white : AppColors.textPrimary,
  ),
),
```

**Nguyên tắc chung khi audit thêm:** với mọi `Chip`/`ActionChip`/`ChoiceChip`/`FilterChip` còn lại trong toàn app (nếu có), đảm bảo `backgroundColor` (trạng thái chưa chọn) luôn dùng `AppColors.card`, không hardcode `Colors.white` hay màu opacity cố định không đổi theo dark mode.

---

## PHẦN B — Redesign Thông tin cá nhân: bỏ Mục tiêu tiết kiệm, hiện dữ liệu hồ sơ ở Dashboard

### Context
Các field Tên hiển thị/Nghề nghiệp/Thu nhập hàng tháng ở `PersonalInfoScreen` sau khi lưu **chỉ nằm trong Firestore, không hiển thị lại ở đâu khác** trong app (trừ Tên đã hiện sẵn ở Dashboard/Profile) — khiến tính năng chỉnh sửa không có giá trị sử dụng thực tế. Field "Mục tiêu tiết kiệm" (mô tả tự do) bị đánh giá không cần thiết, nên bỏ khỏi form.

**Lưu ý quan trọng — không nhầm lẫn 2 khái niệm khác nhau:**
- **"Thu nhập (Tháng 8)"** ở Dashboard hiện tại = **tổng tiền từ giao dịch thu nhập thật đã nhập trong tháng** (tính động từ `AppTransaction`, đã có sẵn, không đổi).
- **"Thu nhập hàng tháng"** trong hồ sơ (`AppUser.monthlyIncome`) = **1 con số cố định người dùng tự khai báo** ở Personal Info, không tự động cập nhật theo giao dịch thật.

Hai số liệu này **độc lập, có thể khác nhau** — khi hiển thị thêm ở Dashboard, phải đặt nhãn rõ ràng để không gây hiểu nhầm là cùng 1 số.

### Fix Requirements

**1. `lib/screens/personal_info_screen.dart` — bỏ field "Mục tiêu tiết kiệm":**
- Xóa hoàn toàn `TextField` + label "Mục tiêu tiết kiệm" (`_goalController`) khỏi giao diện.
- Xóa `_goalController` khỏi state (không dùng nữa), xóa `'savingGoal': ...` khỏi payload gọi `updateUserProfile()` trong `_saveProfile()`.
- **Không đổi** `AppUser` model hay `SCHEMA.md` — field `savingGoal` vẫn tồn tại trong Firestore/model cho các user đã có dữ liệu cũ, chỉ không còn form nào cho sửa nữa (tránh phá vỡ dữ liệu cũ không cần thiết).
- **Không** đụng tới tính năng "Mục tiêu tiết kiệm" (`SavingGoalScreen`, `SavingGoal` model, collection `savingGoals`) ở mục Quản lý tài chính trong Profile — đây là **tính năng hoàn toàn khác** (mục tiêu tiết kiệm có số tiền/thời hạn cụ thể), không liên quan tới field mô tả tự do bị xóa ở đây.

**2. `lib/screens/home/home_dashboard_screen.dart` — hiển thị Nghề nghiệp + Thu nhập khai báo:**

Dùng lại `StreamBuilder<AppUser?>` đã có sẵn trong Dashboard (đang lấy `user` để hiện tên) để lấy thêm `user.occupation` và `user.monthlyIncome`:

- **Nghề nghiệp**: thêm dòng chữ nhỏ, màu `Colors.white70`, ngay dưới dòng "Xin chào, [Tên]" trong phần header gradient — chỉ hiện nếu `user?.occupation` không rỗng, ẩn hoàn toàn nếu chưa khai báo (không hiện dòng trống).
```dart
if (user?.occupation != null && user!.occupation!.isNotEmpty)
  Text(user.occupation!, style: TextStyle(color: Colors.white70, fontSize: 12)),
```

- **Thu nhập khai báo**: thêm 1 dòng nhỏ riêng biệt, đặt tách biệt rõ ràng khỏi 2 chip "Thu nhập (Tháng X)/Chi tiêu (Tháng X)" hiện có — KHÔNG gộp chung hình thức hiển thị để tránh nhầm lẫn. Đề xuất đặt thành 1 dòng nhỏ ngay dưới 2 chip đó, dạng:
```dart
if (user?.monthlyIncome != null && user!.monthlyIncome > 0)
  Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      'Thu nhập khai báo trong hồ sơ: ${AppFormatters.currency(user.monthlyIncome)}/tháng',
      style: TextStyle(color: Colors.white60, fontSize: 11, fontStyle: FontStyle.italic),
    ),
  ),
```
Chữ "khai báo trong hồ sơ" và kiểu chữ *italic* nhạt hơn nhằm phân biệt rõ đây là số liệu tĩnh người dùng tự nhập, khác với số liệu động tính từ giao dịch thật ở 2 chip phía trên.

- Tên hiển thị: **giữ nguyên** cách hiện tại (đã có sẵn ở dòng "Xin chào, [Tên]"), không cần thêm gì.

---

## PHẦN C — Cải tiến UX phần Đổi mật khẩu

### Context
Yêu cầu "thiết kế lại một cách hợp lý" — đề xuất 2 cải tiến cụ thể, rủi ro thấp, giá trị UX rõ ràng:

### Fix Requirements

**1. Thêm nút ẩn/hiện mật khẩu (con mắt) cho cả 3 field** (Mật khẩu hiện tại, Mật khẩu mới, Xác nhận mật khẩu mới) — hiện tại cả 3 đều `obscureText: true` cố định, không có cách xem lại đã gõ đúng chưa:
```dart
bool _obscureCurrent = true; // + 2 biến tương tự cho new/confirm

TextField(
  controller: _currentPasswordController,
  obscureText: _obscureCurrent,
  decoration: _inputDecoration('Mật khẩu hiện tại', Icons.lock_outline).copyWith(
    suffixIcon: IconButton(
      icon: Icon(_obscureCurrent ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          color: AppColors.textSecondary),
      onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
    ),
  ),
),
```
Áp dụng tương tự cho 2 field còn lại với 2 biến state riêng.

**2. Bọc cả phần "Đổi mật khẩu" trong 1 `Container` có nền/bo góc/shadow**, đồng bộ style với các khối card khác trong app (theo đúng pattern `AppColors.card` + `borderRadius: 16` + `boxShadow` nhẹ đã dùng ở `about_app_screen.dart`) — thay vì hiện tại các field đang nằm trần trong `SingleChildScrollView`, tạo cảm giác rời rạc so với phần thông tin cá nhân phía trên.

## Không đổi (Out of scope)

- Không xóa field `savingGoal` khỏi `AppUser` model/`SCHEMA.md`.
- Không đụng tới `SavingGoalScreen`/`SavingGoal` model/collection `savingGoals`.
- Không thêm thước đo độ mạnh mật khẩu (password strength meter) — chỉ thêm nút ẩn/hiện.
- Không đổi logic `AuthService.changePassword()` hay validate hiện có — chỉ đổi UI.
- Không audit lại toàn bộ Chip trong các file khác ngoài 2 file đã nêu ở Phần A (nếu phát hiện thêm nơi khác, báo riêng).

## Acceptance Criteria

- [ ] AI Chat: 3 chip gợi ý câu hỏi đọc rõ chữ ở cả 2 chế độ sáng/tối.
- [ ] Transaction List: tag "Tất cả/Thu nhập/Chi tiêu" đọc rõ chữ ở cả 2 chế độ, kể cả khi chưa được chọn.
- [ ] Personal Info: không còn field "Mục tiêu tiết kiệm"; lưu thông tin vẫn hoạt động bình thường với các field còn lại.
- [ ] Dashboard: sau khi khai báo Nghề nghiệp + Thu nhập ở Personal Info, quay lại Dashboard thấy đúng 2 thông tin này hiện ra, tách biệt rõ với 2 chip Thu nhập/Chi tiêu (Tháng X) hiện có, không gây nhầm lẫn.
- [ ] Chưa khai báo Nghề nghiệp/Thu nhập (tài khoản mới) → Dashboard không hiện dòng trống/thừa, không lỗi.
- [ ] Cả 3 field mật khẩu có nút con mắt hoạt động đúng (bấm để hiện/ẩn), phần Đổi mật khẩu có khung card rõ ràng, đồng bộ style với phần trên.
- [ ] `flutter analyze` không phát sinh lỗi mới.
- [ ] Test cả 2 chế độ sáng/tối cho toàn bộ các thay đổi trên.
