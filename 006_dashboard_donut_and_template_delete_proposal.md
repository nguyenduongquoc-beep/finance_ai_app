# TICKET 006 — Đề xuất cải tiến: Donut chart tương tác theo tháng & Xóa mẫu giao dịch bằng long-press

**Loại:** Feature proposal (KHÔNG phải bug fix — cân nhắc độ ưu tiên theo tiến độ khóa luận)
**Độ ưu tiên:** Thấp hơn ticket 002/004/005 (đề xuất làm SAU khi các bug lưu giao dịch đã ổn định)
**File liên quan:** `lib/screens/home/home_dashboard_screen.dart`, `lib/widgets/dashboard_chart.dart`, `lib/screens/home/add_transaction_screen.dart`, `lib/widgets/quick_template_chip.dart`, `lib/services/template_service.dart`

---

## Phần A — Donut chart tương tác khi bấm vào cột biểu đồ 6 tháng

### Mô tả yêu cầu (theo mô tả của bạn)
Hiện tại biểu đồ cột "Thu/Chi 6 tháng gần đây" (`IncomeExpenseBarChart` trong `dashboard_chart.dart`) chỉ hiển thị tổng thu/chi mỗi tháng, không tương tác được. Yêu cầu: **bấm vào bất kỳ cột nào** (tháng bất kỳ trong 6 tháng, không chỉ tháng hiện tại) → hiện ra biểu đồ donut/pie phân tích **chi tiêu theo danh mục của đúng tháng đó**.

### Hướng tiếp cận đề xuất

1. **Thêm khả năng bắt sự kiện tap trên `BarChart`** (package `fl_chart` hỗ trợ sẵn qua `BarTouchData`):
   ```dart
   BarChartData(
     barTouchData: BarTouchData(
       touchCallback: (event, response) {
         if (event is FlTapUpEvent && response?.spot != null) {
           final monthIndex = response!.spot!.touchedBarGroupIndex;
           onMonthTap(monthIndex); // callback mới, truyền index tháng (0-5) ra ngoài
         }
       },
     ),
     ...
   )
   ```
   Cần thêm tham số `void Function(int monthIndex)? onMonthTap` vào constructor của `IncomeExpenseBarChart`.

2. **Ở `HomeDashboardScreen`**: khi nhận được `monthIndex` từ callback, tính lại `DateTime` của tháng đó (dùng cùng công thức đang có trong `_build6MonthLabels()`), sau đó **query lại giao dịch chi tiêu của đúng tháng đó, gom theo danh mục** — tái sử dụng logic đã có sẵn ở `_buildCategoryPie()` (hiện chỉ tính cho tháng hiện tại, cần tổng quát hóa để nhận tham số `monthStart`/`monthEnd` bất kỳ thay vì hardcode tháng hiện tại).

3. **Hiển thị kết quả:** dùng `showModalBottomSheet` (nhất quán với pattern đã có ở `CustomNumpad`) chứa `CategoryPieChart` (widget đã có sẵn, tái sử dụng nguyên bản) cho tháng được chọn, kèm tiêu đề "Chi tiêu tháng X/YYYY".

### Lưu ý kỹ thuật
- Dữ liệu 6 tháng (`allTx`) **đã được fetch sẵn** ở `HomeDashboardScreen` (biến `allTx` trong `StreamBuilder<List<AppTransaction>>`) — không cần thêm query Firestore mới, chỉ cần lọc lại `allTx` theo tháng được bấm (tính toán thuần client-side, không tốn thêm network call).
- Theo `DESIGN.md`: dùng `AppColors` nhất quán, bottom sheet nên có bo góc trên theo convention hiện có (radius 16-20).

---

## Phần B — Long-press xóa mẫu giao dịch (quick template)

### Mô tả yêu cầu
Hiện tại `QuickTemplateChip` chỉ hỗ trợ tap để áp dụng mẫu, không có cách xóa mẫu đã lưu (kể cả lưu sai/thừa). Yêu cầu: giữ (long-press) vào 1 tag mẫu → hỏi xác nhận → xóa mẫu đó.

### Hướng tiếp cận đề xuất

1. **`TemplateService`** — thêm method mới:
   ```dart
   Future<void> deleteTemplate(String templateId) async {
     final uid = FirebaseAuth.instance.currentUser?.uid;
     if (uid == null) throw Exception('User not authenticated');
     await _db
         .collection('users')
         .doc(uid)
         .collection('quickTemplates')
         .doc(templateId)
         .delete();
   }
   ```

2. **`QuickTemplateChip`** — thêm `onLongPress` callback (tương tự pattern `onLongPress` đã dùng ở `wallet_management_screen.dart`/`category_management_screen.dart` cho việc xóa ví/danh mục — giữ nhất quán UX toàn app):
   ```dart
   GestureDetector(
     onTap: () => onSelect(template),
     onLongPress: onLongPress, // callback mới, optional
     child: Container(...),
   )
   ```

3. **`AddTransactionScreen`** — nơi build `QuickTemplateChip`, thêm xử lý xác nhận xóa (theo đúng pattern dialog xác nhận đã có sẵn ở `transaction_detail_screen.dart`):
   ```dart
   onLongPress: () async {
     final confirm = await showDialog<bool>(
       context: context,
       builder: (ctx) => AlertDialog(
         title: const Text('Xóa mẫu giao dịch?'),
         content: Text('Bạn có chắc muốn xóa mẫu "${t.title}"?'),
         actions: [
           TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
           TextButton(
             onPressed: () => Navigator.pop(ctx, true),
             child: const Text('Xóa', style: TextStyle(color: AppColors.expense)),
           ),
         ],
       ),
     );
     if (confirm == true) {
       await _templateService.deleteTemplate(t.id);
     }
   },
   ```

---

## Phần C — Xác nhận: Ngày tháng khi áp dụng mẫu (không cần sửa)

Bạn có nêu lo ngại: áp dụng mẫu không nên copy luôn ngày cũ, mà phải luôn lấy ngày hiện tại. **Kiểm tra lại code hiện tại — điều này đã đúng sẵn**, không cần sửa gì:

```dart
onSelect: (tmpl) async {
  setState(() {
    _type = tmpl.type;
    _amountController.text = ...;
    _selectedWalletId = ...;
    _selectedCategoryId = ...;
    _noteController.text = tmpl.note;
    _locationController.text = tmpl.location;
    // Không có dòng nào gán _selectedDate = tmpl.date — _selectedDate giữ nguyên
    // giá trị hiện tại của form (mặc định DateTime.now() khi mở màn hình Thêm giao dịch)
  });
  await _runValidation();
},
```
`_selectedDate` **không** bị ghi đè bởi `tmpl.date` ở bất kỳ đâu trong luồng chọn mẫu — nghĩa là mẫu chỉ mang theo số tiền/ví/danh mục/ghi chú/địa điểm, còn ngày luôn là ngày bạn đang thao tác trên form (mặc định là hôm nay, hoặc ngày bạn đã tự đổi bằng "Đổi ngày" trước khi bấm mẫu). Đúng như bạn mong muốn — không cần thay đổi.

---

## Acceptance Criteria (khi triển khai Phần A & B)

**Phần A:**
- [ ] Bấm vào bất kỳ cột nào trong 6 cột tháng (kể cả tháng cũ, tháng hiện tại) → hiện đúng donut chart phân tích chi tiêu của tháng đó.
- [ ] Tháng không có dữ liệu chi tiêu → hiện thông báo "Chưa có dữ liệu" thay vì donut rỗng gây lỗi chia 0.

**Phần B:**
- [ ] Long-press vào 1 mẫu → hiện dialog xác nhận đúng tên mẫu.
- [ ] Xác nhận xóa → mẫu biến mất khỏi danh sách ngay (nhờ `StreamBuilder` tự cập nhật), không cần thoát vào lại màn hình.
- [ ] Hủy xác nhận → mẫu vẫn còn nguyên.

---

**Ghi chú cho bạn:** Đây là 2 tính năng mới, không phải bug — đề xuất **làm sau khi ticket 002, 004, 005 đã test xong và ổn định**, vì luồng "Thêm giao dịch" đang là luồng lõi cần chắc chắn trước, tránh vừa sửa bug vừa thêm tính năng cùng lúc gây khó truy vết nếu có lỗi mới phát sinh.
