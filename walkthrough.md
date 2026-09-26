# Báo cáo Handover & Walkthrough: Bill Reminder / Local Notifications

Tài liệu này tổng hợp toàn bộ giải pháp thiết kế, kết quả kiểm thử đơn vị & tích hợp, cấu trúc mã nguồn và hướng dẫn thử nghiệm thực tế cho tính năng **Nhắc hạn hóa đơn & Giao dịch định kỳ bằng thông báo cục bộ (Local Notifications)** trên ứng dụng `finance_ai_app`.

---

## 1. Bảng Kiểm Tra Thực Tế Trên Android (Test Matrix)

| Kịch bản | Thao tác | Kết quả mong đợi | Kết quả thực tế |
|---|---|---|---|
| **Cấp quyền thông báo** | Mở màn hình Giao dịch định kỳ lần đầu trên Android 13+ | System dialog xin quyền `POST_NOTIFICATIONS` xuất hiện 1 lần duy nhất trong `initState` post-frame callback (kiểm tra `areNotificationsEnabled()` trước, không lặp lại khi widget rebuild). | Chưa kiểm thử thiết bị thực tế |
| **Từ chối quyền** | Nhấn "Don't allow" rồi tiếp tục dùng ứng dụng | Ứng dụng hoạt động bình thường, các thao tác tạo/sửa/xóa lịch lặp không bị crash, không spam popup xin quyền lại. | Chưa kiểm thử thiết bị thực tế |
| **Nhắc trước hạn** | Tạo/Sửa lịch có chọn nhắc trước 1/3/7 ngày | Notification lên lịch tự động vào lúc 09:00 AM local time của ngày tương ứng trước hạn (`nextDueDate - reminderDaysBefore`). | Chưa kiểm thử thiết bị thực tế (Đã PASS Unit Test #3 & #6) |
| **Đến hạn** | Đặt ngày đến hạn là hôm nay/ngày mai | Notification đúng ngày đến hạn được lên lịch lúc 09:00 AM local time. Nội dung rõ ràng: Số tiền, loại thu/chi, ví thực hiện. | Chưa kiểm thử thiết bị thực tế (Đã PASS Unit Test #3 & #6) |
| **Bấm notification** | Chạm vào notification từ thanh thông báo hệ thống | App mở/chuyển đến màn hình `RecurringTransactionScreen`, tự động focus/scroll đến `targetScheduleId` tương ứng. | Chưa kiểm thử thiết bị thực tế |
| **Sửa lịch** | Đổi ngày đến hạn hoặc thay đổi `reminderDaysBefore` | Hủy toàn bộ notification cũ của `scheduleId` đó và tạo lại danh sách notification mới chính xác. | Chưa kiểm thử thiết bị thực tế |
| **Tắt lịch** | Gạt Switch `isActive` sang Tắt (`false`) | Hủy toàn bộ notification đã chờ (pending) của `scheduleId` tương ứng. | Chưa kiểm thử thiết bị thực tế |
| **Xóa lịch** | Bấm nút Xóa lịch định kỳ trong Menu | Hủy toàn bộ notification liên quan đến `scheduleId` đó khỏi hệ thống notification Android/iOS. | Chưa kiểm thử thiết bị thực tế |
| **Mở app nhiều lần** | Mở lại màn hình nhiều lần hoặc đăng nhập lại | `syncAllReminders` chỉ hủy các notification lặp của Bill Reminder (dựa theo payload `scheduleId`) thay vì `cancelAll()`, tránh ảnh hưởng các notification khác của app. | Chưa kiểm thử thiết bị thực tế |
| **An toàn nghiệp vụ** | Nhận hoặc chạm vào notification | Chỉ đóng vai trò nhắc nhở hiển thị. **Không** tự tạo transaction, **không** tự trừ số dư ví, **không** thay đổi Firestore data chỉ từ hành vi notification. | Chưa kiểm thử thiết bị thực tế (Đã đảm bảo qua kiến trúc code) |

> **Ghi chú**: Các mục trên sẽ được cập nhật thành **PASS** sau khi thực hiện chạy trực tiếp ứng dụng trên máy thật/giả lập Android và quan sát kết quả thực tế.

---

## 2. Thông Tin Code, Commit & Diff Stat

- **Branch**: `main`
- **Commit mới nhất trên origin**: `54ad0cf3ce4727038b6a158ca57c321145cb3ba7`
- **Trạng thái Git working tree**: Đã tích hợp hoàn chỉnh các thay đổi cục bộ cho tính năng Local Notification.

### `git diff --stat`

```text
 firestore.rules                                    |   4 +-
 lib/main.dart                                      |   3 +
 lib/models/recurring_transaction_model.dart        |   8 ++
 lib/routes/app_routes.dart                         |   3 +
 .../management/recurring_transaction_screen.dart   | 129 ++++++++++++++++++++-
 lib/services/firestore_service.dart                |  44 ++++++-
 lib/services/local_notification_service.dart      | 376 ++++++++++++++++++++++ (New)
 lib/services/recurring_transaction_service.dart    |  33 ++++++
 macos/Flutter/GeneratedPluginRegistrant.swift      |   2 +
 pubspec.yaml                                       |   4 +
 test/local_notification_service_test.dart         | 175 ++++++++++++++++++++++ (New)
 test/recurring_transaction_service_test.dart       | 105 +++++++++++++++++
 12 files changed, 889 insertions(+), 12 deletions(-)
```

---

## 3. Kết Quả Kiểm Thử Động (Flutter Analyze & Flutter Test)

### 3.1. Static Analysis (`flutter analyze`)
- **Lỗi biên dịch (Errors)**: **0 errors**.
- Tất cả các tập tin liên quan đến tính năng notification (`local_notification_service.dart`, `recurring_transaction_screen.dart`, `recurring_transaction_model.dart`, `local_notification_service_test.dart`) đều biên dịch hoàn toàn sạch sẽ.

### 3.2. Automated Tests (`flutter test`)
- **Tổng số test suite**: **87 tests** (bao gồm 6 unit tests cho Notification Service).
- **Kết quả**: **PASS 100%** (87/87 passed).

```text
00:00 +0: LocalNotificationService Pure Logic Unit Tests 1. Inactive schedule yields 0 scheduled notifications
00:00 +1: LocalNotificationService Pure Logic Unit Tests 2. reminderDaysBefore == 0 yields 0 notifications
00:00 +2: LocalNotificationService Pure Logic Unit Tests 3. reminderDaysBefore == 3 generates both advance and due date notifications
00:00 +3: LocalNotificationService Pure Logic Unit Tests 4. Deterministic notification ID is generated reproducibly
00:00 +4: LocalNotificationService Pure Logic Unit Tests 5. Past notification dates before referenceDate are excluded
00:00 +5: LocalNotificationService Pure Logic Unit Tests 6. Scheduled notification times are explicitly configured for 09:00 AM local time
...
00:05 +87: All tests passed!
```

---

## 4. Trạng Thái Firestore Security Rules

Rule `transactions` đã được chỉnh ở ticket sửa permission-denied trước đó (`allow read: if request.auth != null && (resource == null || request.auth.uid == resource.data.userId);`). **Tính năng Local Notifications không tạo thay đổi Rules mới.**

---

## 5. Các Điểm Tối Ưu Quản Lý Notification & Timezone

1. **Không hủy nhầm notification khác (`syncAllReminders`)**:
   - `syncAllReminders()` duyệt danh sách pending notifications via `_plugin!.pendingNotificationRequests()` và chỉ hủy các thông báo có payload chứa `scheduleId` (các thông báo thuộc Bill Reminder).
   - Không gọi `cancelAll()` toàn bộ để tránh xóa các notification khác của app (như cảnh báo ngân sách).

2. **Chính xác 09:00 AM theo Local Timezone di động**:
   - Thời gian thông báo được khởi tạo `DateTime(year, month, day, 9, 0)` theo múi giờ thiết bị và chuyển sang Timezone bằng `tz.TZDateTime.from(date, tz.local)`.
   - Đã được kiểm tra qua Unit Test #6 (`tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'))`).

3. **Kiểm tra trạng thái quyền tránh spam popup (`requestPermission`)**:
   - Trước khi gọi dialog xin quyền Android, `requestPermission()` kiểm tra `areNotificationsEnabled()`.
   - Nếu quyền đã được cấp, hàm trả về `true` ngay lập tức mà không hiển thị lại popup xin quyền.

4. **Giới hạn 90 ngày & tối đa 50 notifications**:
   - Cửa sổ thời gian quét tối đa 90 ngày (`maxDaysAhead = 90`).
   - Tối đa 50 thông báo lặp cùng lúc (`maxTotalNotifications = 50`) để tránh làm quá tải hệ thống Android.

---

## 6. Các File Chính & Thư Viện Đã Sử Dụng

### Packages (`pubspec.yaml`)
- `flutter_local_notifications: ^18.0.1`
- `timezone: ^0.9.4`

### Các File Đã Thêm / Chỉnh Sửa

1. **`lib/services/local_notification_service.dart` (Tạo mới)**:
   - Core logic khởi tạo, lên lịch, băm ID deterministic, hủy có lọc payload và điều hướng tap notification.
2. **`lib/models/recurring_transaction_model.dart` (Chỉnh sửa)**:
   - Thêm thuộc tính `reminderDaysBefore` (0, 1, 3, 7).
3. **`lib/screens/management/recurring_transaction_screen.dart` (Chỉnh sửa)**:
   - Thêm Dropdown "Nhắc nhở trước hạn" vào Bottom Sheet form.
   - Thêm hiển thị dòng `Nhắc trước N ngày` kèm icon chuông.
   - Tích hợp gọi `scheduleRemindersForSchedule` và `cancelRemindersForSchedule` tại các sự kiện Save, Delete, và Switch.
4. **`lib/routes/app_routes.dart` & `lib/main.dart` (Chỉnh sửa)**:
   - Khởi tạo `navigatorKey` phục vụ chuyển màn hình khi bấm notification.
5. **`test/local_notification_service_test.dart` (Tạo mới)**:
   - 6 unit tests kiểm thử logic tính toán notification & timezone 09:00 AM.

---

## 7. Hướng Dẫn Thử Nghiệm Trên Thiết Bị Android Thực Tế / Giả Lập

1. **Khởi chạy ứng dụng**:
   ```bash
   flutter run -d <android-device-id>
   ```

2. **Tạo lịch định kỳ thử nghiệm**:
   - Vào **Giao dịch định kỳ & Hóa đơn**.
   - Bấm **+** để thêm lịch mới:
     - Số tiền: `100,000` VNĐ
     - Ngày bắt đầu / Kỳ đầu tiên: Chọn **Ngày mai** (VD: 27/09/2026).
     - Tần suất: **Hàng tháng**.
     - Nhắc nhở trước hạn: Chọn **Trước 1 ngày**.
   - Bấm **Lưu lịch định kỳ**.

3. **Quan sát Alarm/Notification trên Android**:
   - Sử dụng lệnh ADB để kiểm tra danh sách alarm đã đăng ký:
     ```bash
     adb shell dumpsys alarm | grep "finance_ai_app"
     ```
   - Chỉnh giờ hệ thống thiết bị đến **08:59 AM** của ngày nhắc nhở để quan sát thông báo hiển thị lúc **09:00 AM**.

4. **Kiểm tra tương tác chạm (Tap)**:
   - Chạm vào thông báo trên thanh trạng thái Android -> Xác nhận ứng dụng chuyển đến màn hình **Giao dịch định kỳ**.

---

> **Trạng thái nghiệm thu**: Đã hoàn tất logic code, kiểm thử đơn vị (87/87 PASS) và cập nhật báo cáo theo đúng yêu cầu. Cần thực hiện thử nghiệm trên máy thật theo Mục 7 để điền kết quả thực tế vào Bảng Android Test Matrix.
