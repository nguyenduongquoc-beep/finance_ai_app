# TICKET 031 — Sửa lỗi crash `LocaleDataException` ở màn Ngân sách (thiếu khởi tạo locale cho `intl`)

**Loại:** Bug fix (crash — chặn hoàn toàn màn hình)
**Độ ưu tiên:** Cao nhất (màn hình không dùng được)
**File bị ảnh hưởng:** `lib/screens/management/budget_management_screen.dart`, `lib/screens/management/budget_setup_screen.dart` (nếu có dùng), `lib/main.dart`

---

## 1. Context (Bối cảnh)

Mở màn Ngân sách (sau khi triển khai Ticket 025) → app crash ngay, hiện màn đỏ:
```
LocaleDataException: Locale data has not been initialized, call initializeDateFormatting(<locale>).
See also: https://docs.flutter.dev/testing/errors
```

## 2. Root Cause (Nguyên nhân gốc)

Đây là lỗi runtime kinh điển của package `intl`: khi dùng `DateFormat` **kèm tham số locale cụ thể** (VD `DateFormat('MMMM yyyy', 'vi_VN')` hoặc `DateFormat.yMMMM('vi_VN')`) để lấy tên tháng bằng tiếng Việt (khớp đúng cách hiển thị `"Tháng 8, 2026"` trong mockup), package `intl` **bắt buộc phải gọi `initializeDateFormatting('vi_VN')` trước** ở đâu đó trong vòng đời app — nếu chưa gọi, mọi lần build tới `DateFormat(..., 'vi_VN').format(...)` sẽ throw `LocaleDataException` ngay lập tức.

**Toàn bộ dự án trước Ticket 025 chưa từng dùng `DateFormat` kèm locale** — mọi nơi cần hiện "Tháng X, YYYY" (VD `transaction_list_screen._formatMonthHeader()`) đều **tự ghép chuỗi thủ công**:
```dart
String _formatMonthHeader(String monthStr) {
  final parts = monthStr.split('/');
  final month = int.tryParse(parts[0]) ?? 0;
  final year = parts[1];
  return 'Tháng $month, $year'; // ghép tay, KHÔNG dùng DateFormat locale
}
```
Đây là lý do bug này **chưa từng xảy ra trước Ticket 025** — phần "Thời gian áp dụng: Tháng 8, 2026" mới thêm ở màn Ngân sách/Thiết lập ngân sách nhiều khả năng đã dùng `DateFormat` kèm `'vi_VN'` để lấy tên tháng, thay vì ghép chuỗi tay theo đúng convention cũ.

`main.dart` **chưa từng gọi `initializeDateFormatting()`** — vì trước giờ không cần, code chỉ dùng `DateFormat('dd/MM/yyyy')`/`DateFormat('MM/yyyy')` (không kèm locale, dùng định dạng số thuần túy, không cần load dữ liệu tên tháng/thứ theo ngôn ngữ nào).

## 3. Fix Requirements (làm cả 2 bước — không chỉ chọn 1)

### 3.1. Bước bắt buộc — tìm và sửa đúng chỗ gây crash

Chạy `grep -rn "DateFormat(" lib/screens/management/budget_management_screen.dart lib/screens/management/budget_setup_screen.dart` để xác định chính xác dòng đang dùng `DateFormat` kèm `'vi_VN'` (hoặc bất kỳ locale nào khác) cho phần hiển thị tháng đang chọn ("Thời gian áp dụng").

**Đổi sang ghép chuỗi thủ công**, đúng convention đã có sẵn trong dự án (không phụ thuộc `intl` locale, không rủi ro lặp lại lỗi này ở bất kỳ đâu khác):
```dart
// Thay vì: DateFormat('MMMM yyyy', 'vi_VN').format(_selectedMonth)
// hoặc:    DateFormat.yMMMM('vi_VN').format(_selectedMonth)
// Dùng:
'Tháng ${_selectedMonth.month}, ${_selectedMonth.year}'
```
Áp dụng đúng vị trí đang hiển thị "Thời gian áp dụng" ở `budget_management_screen.dart`, và bất kỳ chỗ nào tương tự ở `budget_setup_screen.dart` (VD dòng hiện tháng đang thiết lập, dialog chọn tháng nếu có tự thêm phần hiển thị tên tháng riêng ngoài dialog dùng lại từ `transaction_list_screen`).

### 3.2. Bước phòng ngừa — khởi tạo locale đúng cách trong `main.dart` (dù đã sửa 3.1, vẫn nên làm để tránh tái diễn ở bất kỳ tính năng tương lai nào lỡ dùng `DateFormat` kèm locale)

Thêm import và khởi tạo trong `main()`, **trước** `runApp()`:
```dart
import 'package:intl/date_symbol_data_local.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await initializeDateFormatting('vi_VN', null); // MỚI — nạp dữ liệu locale tiếng Việt cho intl
  await ThemeController.loadSavedTheme();
  runApp(const FinanceAiApp());
}
```

Không cần thêm package mới — `date_symbol_data_local.dart` đã có sẵn trong package `intl` (đã là dependency của dự án qua `pubspec.yaml`).

## 4. Không đổi (Out of scope)

- Không đổi cách các nơi khác trong app hiển thị ngày/tháng (`AppFormatters.date()`, `AppFormatters.month()`, `_formatMonthHeader()` ở `transaction_list_screen.dart`) — các hàm này vốn không dùng locale, không bị ảnh hưởng bởi bug này, không cần sửa.
- Không đổi logic tính toán `Budget`/`spentAmount` đã làm ở Ticket 025 — đây thuần túy là lỗi hiển thị chuỗi tháng, không liên quan tới phần tính toán ngân sách.
- Không thêm hỗ trợ đa locale (chỉ khởi tạo `'vi_VN'`, đúng phạm vi ngôn ngữ hiện tại của app — nếu sau này Ticket 019 mở rộng đa ngôn ngữ sang các module khác, cần bổ sung khởi tạo locale tương ứng lúc đó, không phải ở ticket này).

## 5. Acceptance Criteria

- [ ] Mở màn Ngân sách → **không còn crash**, hiện đúng "Thời gian áp dụng: Tháng 8, 2026" (hoặc tháng đang chọn thực tế).
- [ ] Mở màn Thiết lập ngân sách (nếu có phần hiển thị tháng tương tự) → không crash, hiện đúng tên tháng.
- [ ] Đổi tháng ở bộ lọc "Thời gian áp dụng" → tên tháng hiển thị cập nhật đúng, không crash.
- [ ] Test lại toàn bộ luồng đã test ở Ticket 025 (tạo/sửa/xóa giao dịch ảnh hưởng Budget, thông báo vượt 80%...) để xác nhận fix này không ảnh hưởng gì tới logic tính toán đã làm trước đó — chỉ sửa đúng phần hiển thị chuỗi tháng.
- [ ] `flutter analyze` không phát sinh lỗi mới.
- [ ] Chạy `grep -rn "DateFormat(.*,.*'" lib/` (tìm mọi `DateFormat` có tham số thứ 2 — dấu hiệu có kèm locale) để xác nhận không còn chỗ nào khác trong toàn bộ `lib/` dùng `DateFormat` kèm locale mà chưa được `initializeDateFormatting()` bảo vệ.
