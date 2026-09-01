# TICKET 012 — Chỉnh bố cục màn Khởi tạo hồ sơ, đổi đơn vị tiền tệ toàn app sang VNĐ, thêm chọn ảnh đại diện + sửa bug hiển thị avatar

**Loại:** UI/UX improvement + Bug fix (2 phần độc lập, gộp chung 1 ticket theo yêu cầu)
**Độ ưu tiên:** Trung bình
**File bị ảnh hưởng:** `lib/screens/setup/profile_setup_screen.dart`, `lib/screens/setup/wallet_setup_screen.dart`, `lib/utils/formatters.dart`, `lib/screens/profile_screen.dart`, `context/SCHEMA.md`

---

## 1. Context (Bối cảnh)

Đang tinh chỉnh lại UI theo thiết kế Figma mới cho màn "Khởi tạo hồ sơ" (`ProfileSetupScreen`). Phát hiện 3 vấn đề cần xử lý cùng lúc:

1. **Bố cục lệch:** màn hiện dùng `Spacer()` để đẩy nút "Tiếp tục" xuống đáy màn hình, tạo khoảng trống lớn bất hợp lý ở phía trên khi số lượng field ít hơn chiều cao màn hình. Cần tinh chỉnh lại bố cục cho hợp lý, khớp thiết kế Figma.
2. **Đơn vị tiền tệ viết tắt "đ"** đang dùng ở khắp nơi trong app qua `AppFormatters.currency()` (dùng chung cho Dashboard, danh sách giao dịch, ngân sách, mục tiêu tiết kiệm, và 2 màn Setup) — cần đổi đồng loạt thành "VNĐ" cho rõ nghĩa hơn.
3. **Chưa có chức năng chọn ảnh đại diện** ở bước Khởi tạo hồ sơ, dù hạ tầng đã có sẵn gần đủ: model `AppUser` đã có field `avatar` (String?), `StorageService.uploadAvatar(userId, imageFile)` đã tồn tại nhưng **chưa từng được gọi ở bất kỳ đâu trong code**.

Trong lúc rà lại luồng avatar, phát hiện thêm 1 **bug độc lập nhưng liên quan chặt**: `ProfileScreen` (màn Hồ sơ, khác với `ProfileSetupScreen`) đang hiển thị avatar bằng `NetworkImage`, nhưng theo kiến trúc lưu ảnh hiện tại của dự án (xem `context/SCHEMA.md`, `context/ARCHITECTURE.md`), mọi ảnh — kể cả avatar — đều lưu **cục bộ trên thiết bị** (`path_provider`), không phải URL cloud. `NetworkImage` không đọc được file local, nên nếu tính năng chọn avatar được thêm mà không sửa chỗ này, ảnh sẽ **không bao giờ hiển thị được** ở màn Hồ sơ. Đây là lỗi cùng loại đã từng được sửa cho ảnh hóa đơn giao dịch ở ticket 011 (`Image.network` → `Image.file`), nhưng avatar thì bị bỏ sót, chưa sửa.

Ngoài ra, `context/SCHEMA.md` hiện đang mô tả sai field `avatar` là "URL Firebase Storage" — tài liệu chưa được cập nhật theo đúng thực tế code sau khi đổi kiến trúc lưu ảnh sang local.

## 2. Root Cause

- **Bố cục:** dùng `Spacer()` trong `Column` không cuộn được (không bọc `SingleChildScrollView`), khiến layout cứng nhắc, không linh hoạt theo nội dung thực tế.
- **Đơn vị tiền tệ:** hardcode chuỗi `' đ'` trong `AppFormatters.currency()` — đổi 1 chỗ duy nhất sẽ tự động áp dụng cho toàn app vì mọi nơi hiển thị tiền đều gọi qua hàm này (đúng nguyên tắc DRY đã áp dụng sẵn trong dự án).
- **Bug avatar:** `ProfileScreen` dùng sai widget hiển thị ảnh (`NetworkImage` thay vì `FileImage`/`Image.file`) do khi viết code ban đầu, kiến trúc lưu ảnh còn dự kiến dùng Firebase Cloud Storage (URL), nhưng sau đó đã đổi sang lưu local mà chỗ này chưa được cập nhật theo.

## 3. Fix Requirements

### 3.1. `lib/utils/formatters.dart` — đổi đơn vị tiền tệ toàn app

```dart
/// Format số tiền: 1200000 -> "1.200.000 VNĐ"
static String currency(num amount) {
  return '${_currencyFormat.format(amount)} VNĐ';
}
```
Chỉ đổi đúng 1 dòng này (thay `' đ'` thành `' VNĐ'`). Hàm `number()` (không kèm đơn vị) giữ nguyên không đổi. Việc này sẽ tự động cập nhật hiển thị "VNĐ" ở **toàn bộ app**: Dashboard, danh sách giao dịch, chi tiết giao dịch, quản lý ngân sách, mục tiêu tiết kiệm, AI Report, AI Insight, v.v. — không cần sửa thủ công từng màn.

### 3.2. `lib/screens/setup/profile_setup_screen.dart`

**a) Sửa bố cục:**
- Bọc nội dung form trong `SingleChildScrollView` thay vì dùng `Spacer()` đẩy nút xuống đáy.
- Sắp xếp spacing đều đặn giữa các field (theo đúng khoảng cách trong thiết kế Figma), đặt nút "Tiếp tục" ngay sau field cuối cùng thay vì neo cứng ở đáy màn hình.

**b) Đổi label đơn vị tiền tệ:**
```dart
decoration: const InputDecoration(
  labelText: 'Thu nhập hàng tháng (VNĐ)',
  prefixIcon: Icon(Icons.attach_money),
  hintText: 'vd: 12000000',
),
```

**c) Thêm chức năng chọn ảnh đại diện từ thư viện:**
- Thêm `CircleAvatar` ở đầu form, hiển thị ảnh đã chọn (nếu có) hoặc icon người dùng mặc định (`Icons.person`).
- Thêm icon nhỏ hình camera đè lên góc dưới-phải của `CircleAvatar`, bấm vào để mở thư viện ảnh.
- Dùng `ImagePicker` (đã có sẵn trong `pubspec.yaml`), **chỉ dùng `ImageSource.gallery`** — không thêm tùy chọn chụp ảnh camera ở màn này. Theo đúng pattern đã dùng ở `add_transaction_screen.dart` (phần chọn ảnh hóa đơn từ thư viện):
```dart
final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
if (picked != null) {
  setState(() => _selectedAvatarFile = File(picked.path));
}
```
- Lưu `File?` đã chọn vào 1 biến state mới (VD `_selectedAvatarFile`), **chưa upload ngay** lúc chọn.
- Trong `_handleContinue()`, sau khi `createUserProfile()` thành công (cần lấy được `uid` trước): nếu `_selectedAvatarFile != null`, gọi `StorageService().uploadAvatar(uid, _selectedAvatarFile!)` để lưu ảnh local, lấy đường dẫn trả về, sau đó gọi `updateUserProfile(uid, {'avatar': path})` để cập nhật field `avatar` cho đúng user vừa tạo. Việc chọn ảnh là **tùy chọn (optional)** — không chọn ảnh vẫn tiếp tục bình thường, `avatar` giữ `null`.
- Bọc phần upload avatar trong try/catch riêng (không để lỗi upload ảnh chặn luôn việc hoàn tất Setup — theo đúng tinh thần xử lý lỗi không chặn luồng chính đã áp dụng ở `add_transaction_screen.dart`).

### 3.3. `lib/screens/setup/wallet_setup_screen.dart`

Đổi hint text field số dư:
```dart
decoration: const InputDecoration(
  hintText: 'Số dư hiện tại (VNĐ)',
  isDense: true,
),
```

### 3.4. `lib/screens/profile_screen.dart` — sửa bug hiển thị avatar

Thêm `import 'dart:io';` ở đầu file. Đổi:
```dart
backgroundImage:
    user?.avatar != null ? NetworkImage(user!.avatar!) : null,
```
thành:
```dart
backgroundImage:
    user?.avatar != null ? FileImage(File(user!.avatar!)) : null,
```
Vì `CircleAvatar.backgroundImage` không có sẵn `errorBuilder`, cần bọc bằng cách kiểm tra file tồn tại trước khi gán (tránh crash nếu file đã bị xóa/mất do gỡ cài đặt app trước đó — xem rủi ro đã ghi nhận ở `PRD.md` mục 7):
```dart
ImageProvider? _avatarImage(String? path) {
  if (path == null) return null;
  final file = File(path);
  return file.existsSync() ? FileImage(file) : null;
}
```
Rồi dùng `backgroundImage: _avatarImage(user?.avatar)`.

### 3.5. `context/SCHEMA.md` — cập nhật tài liệu cho đúng thực tế

Trong bảng mô tả collection `users/{uid}`, sửa dòng:
```
| avatar | string? | URL Firebase Storage |
```
thành:
```
| avatar | string? | Đường dẫn file cục bộ trên thiết bị (path_provider), đọc bằng Image.file/FileImage — không phải URL cloud, giống cơ chế lưu ảnh hóa đơn giao dịch (xem mục 5) |
```

## 4. Không đổi (Out of scope)

- Không đổi `AppUser` model, `StorageService`, `pubspec.yaml` — đã có sẵn đủ hạ tầng cần dùng, không cần thêm field/method mới.
- Không thêm tùy chọn chụp ảnh (camera) cho avatar ở bước Setup — chỉ chọn từ thư viện.
- Không đổi cấu trúc/logic tạo `AppUser`, không đổi validate các field khác (tên, nghề nghiệp, mục tiêu tiết kiệm) — chỉ thêm phần avatar và sửa label/bố cục.
- Không đổi `AppFormatters.number()` (hàm không kèm đơn vị) — chỉ đổi `currency()`.
- Không sửa các nơi khác trong `context/SCHEMA.md` ngoài dòng mô tả `avatar` đã nêu.

## 5. Acceptance Criteria

- [ ] Màn Khởi tạo hồ sơ có bố cục cân đối, không còn khoảng trống bất thường phía trên, khớp đúng bố cục trong Figma.
- [ ] Toàn bộ số tiền hiển thị trong app (Dashboard, danh sách giao dịch, chi tiết giao dịch, ngân sách, mục tiêu tiết kiệm, AI Report, AI Insight, 2 màn Setup) đều hiện đúng đơn vị "VNĐ" thay vì "đ", không sót màn nào.
- [ ] Ở màn Khởi tạo hồ sơ, bấm vào icon/avatar → mở thư viện ảnh, chọn xong hiện đúng ảnh preview trên `CircleAvatar`.
- [ ] Hoàn tất Setup (bấm "Tiếp tục") với ảnh đã chọn → vào màn Hồ sơ (`ProfileScreen`), avatar hiển thị đúng ảnh vừa chọn, không lỗi, không icon mặc định.
- [ ] Hoàn tất Setup **không** chọn ảnh → vẫn tiếp tục bình thường, không lỗi, không crash; màn Hồ sơ hiện icon người dùng mặc định như cũ.
- [ ] Giả lập file avatar bị xóa khỏi thiết bị (hoặc test trên user cũ có `avatar` trỏ URL cũ không còn hợp lệ) → màn Hồ sơ không crash, tự động hiện icon mặc định thay vì lỗi ảnh vỡ.
- [ ] Test lại toàn bộ luồng Đăng ký → Khởi tạo hồ sơ (có chọn ảnh) → Tạo ví → Chọn danh mục → vào Dashboard, xác nhận không có màn nào bị lỗi hiển thị số tiền hoặc avatar.
- [ ] Test tối thiểu 2 lần (1 lần có chọn avatar, 1 lần không chọn) để chắc chắn không phải ăn may.
