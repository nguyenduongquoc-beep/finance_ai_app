# TICKET 016 — Redesign màn Danh sách giao dịch: thêm tìm kiếm, bộ lọc theo ngày/tháng, thay 3 nút lọc cũ bằng tag Tất cả/Chi tiêu/Thu nhập

**Loại:** UI/UX redesign + Cải tiến logic lọc (thay thế hoàn toàn cơ chế lọc cũ)
**Độ ưu tiên:** Trung bình
**File bị ảnh hưởng:** `lib/screens/home/transaction_list_screen.dart`

---

## 1. Context (Bối cảnh)

Màn `TransactionListScreen` hiện dùng cơ chế lọc theo khoảng thời gian tương đối: 3 chip "Hôm nay"/"7 ngày qua"/"Tháng này" (`_FilterRange` enum) + 1 icon riêng để bật/tắt "Xem toàn bộ lịch sử" (thêm ở `009_confirmed_directions_batch.md` phần B). Cơ chế này từng bị đánh giá "phi logic" ở `008_consolidated_feedback_round.md` vấn đề 4 (VD lọc "Tuần" có thể vô tình hiện dữ liệu tháng trước do tuần bắc cầu 2 tháng).

Theo thiết kế Figma mới, cơ chế lọc được đơn giản hóa và trực quan hơn:
- **Thay hoàn toàn** 3 chip cũ + icon lịch sử bằng: 1 thanh tìm kiếm (theo ghi chú/tên danh mục) + 1 nút chọn ngày/tháng cụ thể + 3 tag lọc theo loại giao dịch (**Tất cả / Chi tiêu / Thu nhập**).
- Đây là thay đổi **thay thế**, không phải thêm song song — bỏ hẳn `_FilterRange`, `_filterChip()`, `_showAllHistory` khỏi code.

## 2. Nguyên tắc thiết kế logic lọc mới

3 điều kiện lọc (**tìm kiếm** + **ngày/tháng** + **loại giao dịch**) hoạt động **độc lập, kết hợp AND với nhau** — người dùng có thể dùng riêng lẻ hoặc kết hợp cùng lúc.

**Mặc định khi mở màn (chưa chọn bộ lọc nào):** hiển thị **toàn bộ lịch sử giao dịch**, nhóm theo tháng (tái sử dụng đúng cách nhóm đã làm ở ticket 009 phần B khi bật "Xem toàn bộ lịch sử" trước đây), sắp xếp mới nhất lên đầu — không còn mặc định giới hạn "Tháng này" như cơ chế cũ.

## 3. Fix Requirements

### 3.1. State mới thay cho `_FilterRange`/`_showAllHistory`

```dart
String _searchQuery = '';
String _typeFilter = 'all'; // 'all' | 'expense' | 'income'
DateTime? _selectedDate;    // ngày cụ thể được chọn (null = không lọc theo ngày)
DateTime? _selectedMonth;   // tháng cụ thể được chọn (null = không lọc theo tháng)
```

`_selectedDate` và `_selectedMonth` **loại trừ lẫn nhau** (chỉ 1 trong 2 có giá trị tại 1 thời điểm — chọn cái này sẽ tự xóa cái kia).

### 3.2. Thanh tìm kiếm

Thêm `TextField` ở đầu danh sách (dưới AppBar), style theo Figma (bo góc, icon kính lúp). Lọc **client-side** trên danh sách đã stream về — không cần Firestore full-text search:

```dart
final matchesSearch = _searchQuery.isEmpty ||
    (tx.note?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
    (category?.name.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
```

### 3.3. Nút chọn ngày/tháng — thay cho icon "Xem toàn bộ lịch sử" cũ

Thêm 1 `IconButton` (icon lịch/calendar) trên AppBar. Bấm vào mở `showModalBottomSheet` với 2 lựa chọn:
- **"Chọn theo ngày cụ thể"** → mở `showDatePicker` chuẩn, gán vào `_selectedDate`, xóa `_selectedMonth`.
- **"Chọn theo tháng"** → mở 1 dialog đơn giản gồm `DropdownButton` chọn tháng (1-12) + năm (VD từ `DateTime.now().year - 4` tới hiện tại), gán kết quả vào `_selectedMonth` (lưu dạng `DateTime(year, month, 1)`), xóa `_selectedDate`.

Sau khi chọn, hiện 1 chip nhỏ ngay dưới thanh tìm kiếm ghi rõ đang lọc gì (VD `"📅 15/08/2026"` hoặc `"📅 Tháng 8/2026"`), kèm icon "x" để xóa bộ lọc ngày/tháng (quay về xem toàn bộ lịch sử).

### 3.4. Tag lọc loại giao dịch — thay 3 chip cũ

Thay `_filterChip()` hiện tại bằng 3 `ChoiceChip`/`FilterChip`: **"Tất cả"**, **"Chi tiêu"**, **"Thu nhập"** — style theo đúng thiết kế Figma (tag bo tròn, màu nổi bật khi active). Set `_typeFilter` tương ứng, lọc:

```dart
final matchesType = _typeFilter == 'all' || tx.type == _typeFilter;
```

### 3.5. Query Firestore theo bộ lọc ngày/tháng

Không cần thêm composite index mới (vẫn dùng đúng cấu trúc `where('userId')` + `orderBy('date')` + range `date` đã có sẵn trong `firestore.indexes.json`):

```dart
Stream<List<AppTransaction>> _buildStream(String uid) {
  if (_selectedDate != null) {
    final start = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
    final end = start.add(const Duration(days: 1)).subtract(const Duration(seconds: 1));
    return _firestoreService.streamTransactions(uid, from: start, to: end);
  }
  if (_selectedMonth != null) {
    final start = DateTime(_selectedMonth!.year, _selectedMonth!.month, 1);
    final end = DateTime(_selectedMonth!.year, _selectedMonth!.month + 1, 1)
        .subtract(const Duration(seconds: 1));
    return _firestoreService.streamTransactions(uid, from: start, to: end);
  }
  return _firestoreService.streamTransactions(uid); // mặc định: toàn bộ lịch sử
}
```

### 3.6. Cách nhóm hiển thị danh sách

- **Khi không chọn ngày/tháng cụ thể** (mặc định hoặc chỉ lọc theo tìm kiếm/loại giao dịch): nhóm theo **tháng** (dùng `AppFormatters.month(tx.date)` làm key), tái sử dụng đúng logic nhóm-theo-tháng đã có từ ticket 009 phần B.
- **Khi chọn tháng cụ thể** (`_selectedMonth != null`): nhóm theo **ngày** trong đúng tháng đó (dùng lại `_groupByDay()` hiện có).
- **Khi chọn ngày cụ thể** (`_selectedDate != null`): chỉ có 1 nhóm duy nhất (đúng ngày đó), không cần tiêu đề nhóm, hiển thị danh sách phẳng.
- Áp dụng `_searchQuery`/`_typeFilter` lên danh sách **sau khi** đã nhận từ Firestore stream, trước khi nhóm hiển thị.

### 3.7. Áp dụng UI theo Figma

Đổi màu sắc/spacing/style toàn bộ AppBar, thanh tìm kiếm, tag lọc, tiêu đề nhóm, `TransactionCard` theo đúng thiết kế.

## 4. Không đổi (Out of scope)

- Không đổi `FirestoreService.streamTransactions()` — signature đã hỗ trợ sẵn `from`/`to`, dùng lại nguyên vẹn.
- Không đổi `TransactionCard` widget (trừ style) — vẫn nhận đúng `transaction`, `category`, `onTap` như cũ.
- Không đổi `firestore.indexes.json` — không cần thêm index mới.
- Không thêm sắp xếp/lọc nâng cao khác (theo số tiền, theo ví...) ngoài phạm vi đã nêu.
- Không cho chọn khoảng ngày tự do (date range, VD "từ ngày X đến ngày Y") — chỉ 2 kiểu: 1 ngày cụ thể hoặc 1 tháng cụ thể.

## 5. Acceptance Criteria

- [ ] Mở màn Danh sách giao dịch lần đầu → hiện toàn bộ lịch sử, nhóm theo tháng, mới nhất lên đầu (không giới hạn "Tháng này" như trước).
- [ ] Gõ vào thanh tìm kiếm (VD tên món ăn trong ghi chú, hoặc tên danh mục) → danh sách lọc đúng ngay, không cần bấm nút tìm kiếm riêng.
- [ ] Bấm nút lịch → chọn "Theo ngày cụ thể" → chọn 1 ngày → danh sách chỉ hiện đúng giao dịch ngày đó, chip lọc hiện rõ ngày đang chọn.
- [ ] Bấm nút lịch → chọn "Theo tháng" → chọn tháng/năm → danh sách hiện đúng giao dịch tháng đó, nhóm theo ngày, chip lọc hiện rõ tháng đang chọn.
- [ ] Bấm "x" trên chip lọc ngày/tháng → quay về xem toàn bộ lịch sử (nhóm theo tháng).
- [ ] Bấm tag "Chi tiêu" → chỉ hiện giao dịch chi tiêu (kết hợp đúng với bộ lọc ngày/tháng và tìm kiếm đang có, nếu có).
- [ ] Kết hợp đồng thời: chọn tháng cụ thể + tag "Thu nhập" + gõ tìm kiếm → danh sách lọc đúng cả 3 điều kiện cùng lúc (AND).
- [ ] Không có giao dịch nào khớp bộ lọc hiện tại → hiện thông báo rõ ràng "Không tìm thấy giao dịch phù hợp" thay vì màn trắng khó hiểu.
- [ ] `flutter analyze` không phát sinh lỗi/warning mới.
- [ ] Test tối thiểu: 1 lần xem toàn bộ, 1 lần lọc theo ngày, 1 lần lọc theo tháng, 1 lần kết hợp cả 3 điều kiện lọc cùng lúc.
