# TICKET 029 — Sửa lỗi thiếu `orderBy` gây `FAILED_PRECONDITION` khi tính chi tiêu theo danh mục

**Loại:** Bug fix
**Độ ưu tiên:** Cao nhất (chặn hoàn toàn luồng lưu giao dịch)
**File bị ảnh hưởng:** `lib/services/firestore_service.dart`

---

## 1. Context (Bối cảnh)

Sau khi ticket sửa màn Ngân sách (đổi kiến trúc `Budget`: bỏ field `spent` lưu sẵn, chuyển sang tính động từ `transactions` qua hàm mới `getCategorySpentThisMonth()`), việc **tạo hoặc sửa bất kỳ giao dịch chi tiêu nào cũng thất bại**, kèm log lỗi:

```
Status{code=FAILED_PRECONDITION, description=The query requires an index. You can create it here: https://console.firebase.google.com/...}
Query(transactions where userId==... and date>=2026-09-01T00:00:00.000 and date<=2026-09-30T23:59:59.000 order by date, __name__)
```

```
❌ Lỗi khi lưu giao dịch: [cloud_firestore/failed-precondition] The query requires an index...
```

## 2. Root Cause (Nguyên nhân gốc)

Hàm mới `getCategorySpentThisMonth()` trong `firestore_service.dart`:

```dart
Future<double> getCategorySpentThisMonth(
  String userId,
  String categoryId, {
  DateTime? month,
}) async {
  final target = month ?? DateTime.now();
  final monthStart = DateTime(target.year, target.month, 1);
  final monthEnd = DateTime(target.year, target.month + 1, 1).subtract(const Duration(seconds: 1));
  final txQuery = await _db
      .collection('transactions')
      .where('userId', isEqualTo: userId)
      .where('date', isGreaterThanOrEqualTo: monthStart.toIso8601String())
      .where('date', isLessThanOrEqualTo: monthEnd.toIso8601String())
      .get(); // <-- KHÔNG có .orderBy('date', descending: true)
  ...
}
```

thực hiện query với 2 điều kiện range trên field `date` (`isGreaterThanOrEqualTo` + `isLessThanOrEqualTo`) nhưng **không có `.orderBy('date', ...)` tường minh**.

Firestore SDK khi gặp trường hợp này sẽ **tự ngầm định sắp xếp `date` theo `ASCENDING`**, tạo ra tổ hợp composite index (`userId ASC, date ASC`) — khác với composite index đã khai báo sẵn trong `firestore.indexes.json`:

```json
{ "fieldPath": "userId", "order": "ASCENDING" },
{ "fieldPath": "date", "order": "DESCENDING" }
```

Do không khớp index đã có, Firestore từ chối toàn bộ query với `FAILED_PRECONDITION`.

Hàm `streamTransactions()` (đã có từ trước, không bị lỗi) luôn dùng `.orderBy('date', descending: true)` tường minh nên khớp đúng index hiện có — đây là bằng chứng cho thấy `getCategorySpentThisMonth()` là hàm mới chưa tuân theo đúng convention đã thiết lập trong file.

**Mức độ ảnh hưởng:** hàm này được gọi từ cả `createTransaction()` và `updateTransactionSafely()` (để kiểm tra cảnh báo vượt 80% ngân sách khi giao dịch là `expense`). Vì vậy lỗi này khiến **toàn bộ thao tác lưu/sửa giao dịch chi tiêu bị thất bại**, không chỉ riêng màn Ngân sách — đúng như log thực tế cho thấy lỗi xảy ra ngay tại `_runValidation()` và `_handleSave()` ở màn Thêm giao dịch.

## 3. Fix Requirements (Yêu cầu sửa)

Thêm `.orderBy('date', descending: true)` vào đúng vị trí trong `getCategorySpentThisMonth()`, ngay trước `.get()`, để khớp đúng composite index hiện có — **không cần tạo index mới trên Firebase Console**:

```dart
Future<double> getCategorySpentThisMonth(
  String userId,
  String categoryId, {
  DateTime? month,
}) async {
  final target = month ?? DateTime.now();
  final monthStart = DateTime(target.year, target.month, 1);
  final monthEnd = DateTime(target.year, target.month + 1, 1).subtract(const Duration(seconds: 1));
  final txQuery = await _db
      .collection('transactions')
      .where('userId', isEqualTo: userId)
      .where('date', isGreaterThanOrEqualTo: monthStart.toIso8601String())
      .where('date', isLessThanOrEqualTo: monthEnd.toIso8601String())
      .orderBy('date', descending: true) // ✅ THÊM DÒNG NÀY — khớp đúng index đã có
      .get();
  double total = 0;
  for (final doc in txQuery.docs) {
    final data = doc.data();
    if (data['type'] == 'expense' && data['categoryId'] == categoryId) {
      total += (data['amount'] as num).toDouble();
    }
  }
  return total;
}
```

Không ảnh hưởng logic — hàm chỉ dùng kết quả để cộng dồn `amount`, thứ tự sắp xếp của kết quả trả về không quan trọng với mục đích tính tổng này.

## 4. Không đổi (Out of scope)

- Không đổi logic tính tổng (`total += ...`), không đổi điều kiện lọc `type == 'expense' && categoryId == categoryId`.
- Không đổi chữ ký hàm `getCategorySpentThisMonth()`.
- Không đổi `firestore.indexes.json` — không cần thêm/deploy index mới.
- Không đổi bất kỳ hàm nào khác trong `firestore_service.dart` (`createTransaction`, `updateTransactionSafely`, `streamTransactions`...).
- Không đổi `budget_setup_screen.dart` hay bất kỳ file UI nào.

## 5. Acceptance Criteria (Tiêu chí hoàn thành)

- [ ] Tạo giao dịch chi tiêu mới (bất kỳ danh mục nào, có hoặc không có ngân sách thiết lập) → lưu thành công, không còn log lỗi `FAILED_PRECONDITION`.
- [ ] Sửa 1 giao dịch chi tiêu đã có (đổi số tiền hoặc danh mục) → cập nhật thành công, không lỗi.
- [ ] Cảnh báo vượt 80% ngân sách vẫn hoạt động đúng như thiết kế: test với 1 danh mục có ngân sách thiết lập, tạo giao dịch khiến tổng chi trong tháng vượt 80% hạn mức → nhận đúng thông báo cảnh báo.
- [ ] Màn "Thiết lập ngân sách" (`budget_setup_screen.dart`) hoạt động bình thường, không bị ảnh hưởng bởi thay đổi này.
- [ ] `flutter analyze` không phát sinh lỗi/warning mới.
- [ ] Test lại đúng kịch bản đã gây lỗi ban đầu: mở màn "Thêm giao dịch" tháng 9, tạo giao dịch chi tiêu bất kỳ → xác nhận lưu thành công.
