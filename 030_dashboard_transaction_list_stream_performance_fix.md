# TICKET 030 — Mở rộng fix hiệu năng Stream (Ticket 029) sang Dashboard & Danh sách giao dịch

**Loại:** Bug fix (hiệu năng — cùng root cause với Ticket 029, khác file)
**Độ ưu tiên:** Cao
**File bị ảnh hưởng:** `lib/screens/home/home_dashboard_screen.dart`, `lib/screens/home/transaction_list_screen.dart`

---

## 1. Context (Bối cảnh)

Ticket 029 đã sửa lỗi "màn Thêm/Sửa giao dịch tự mở lại kết nối Firestore mỗi lần rebuild" — nhưng đây là lỗi có tính hệ thống (`ARCHITECTURE.md` mục 4 đã cảnh báo trước), không chỉ ở 1 file. Rà lại 2 màn có **cùng chính xác pattern lỗi**, với trigger cụ thể người dùng chắc chắn gặp phải:

- **`HomeDashboardScreen`**: bấm vào 1 cột bất kỳ trong biểu đồ 6 tháng (chỉ để đổi tháng hiển thị ở Donut chart bên dưới, không cần dữ liệu mới) → `setState()` → `build()` chạy lại → `final firestoreService = FirestoreService();` bị tạo mới, kéo theo **toàn bộ 4 stream lồng nhau** (User, Ví, Danh mục, Giao dịch 6 tháng) bị hủy và mở lại từ đầu — dù việc bấm cột biểu đồ **không hề cần** dữ liệu mới nào cả (`_getSelectedMonthTx()` chỉ lọc lại từ `allTx` đã có sẵn trong bộ nhớ).
- **`TransactionListScreen`**: gõ vào ô tìm kiếm (`_searchController` → `onChanged` → `setState(() => _searchQuery = v)`) → `build()` chạy lại → `_buildStream(uid)` được gọi lại, tạo **1 stream giao dịch mới** — nghĩa là **mỗi ký tự gõ vào ô tìm kiếm là 1 lần Firestore bị mở kết nối lại**, dù tìm kiếm chỉ lọc client-side trên dữ liệu đã tải (`_searchQuery` không hề ảnh hưởng tới câu query Firestore).

## 2. Fix Requirements

### 2.1. `lib/screens/home/home_dashboard_screen.dart`

Chuyển toàn bộ việc tạo `FirestoreService` và các stream sang `initState()`, lưu vào field `State`. **Phân biệt rõ 2 loại stream:**
- **Stream cố định** (User, Ví, Danh mục, Giao dịch tháng hiện tại dùng cho nhánh không nằm trong bộ lọc) — tạo đúng 1 lần, không bao giờ đổi lại.
- **Stream phụ thuộc bộ lọc** (Giao dịch 6 tháng, phụ thuộc `_selectedYear`/`_selectedHalf`) — chỉ được tạo lại **đúng lúc** người dùng đổi năm/nửa năm, không được tạo lại khi bấm cột biểu đồ (`_selectedMonthIndex` đổi).

```dart
class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  int _selectedMonthIndex = 5;
  late int _selectedYear;
  late int _selectedHalf;

  // MỚI — field cấp State, khởi tạo đúng 1 lần trong initState
  late final String _uid;
  final _firestoreService = FirestoreService();
  late final Stream<AppUser?> _userStream;
  late final Stream<List<Wallet>> _walletsStream;
  late final Stream<List<Category>> _categoriesStream;
  late final Stream<List<AppTransaction>> _currentMonthTxStream; // cố định, dùng cho nhánh ngoài bộ lọc
  late Stream<List<AppTransaction>> _sixMonthTxStream;            // đổi khi filter năm/nửa năm đổi

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedHalf = now.month <= 6 ? 1 : 2;
    _selectedMonthIndex = _defaultMonthIndex();

    _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _userStream = _firestoreService.streamUserProfile(_uid);
    _walletsStream = _firestoreService.streamWallets(_uid);
    _categoriesStream = _firestoreService.streamCategories(_uid);
    _currentMonthTxStream = _firestoreService.streamTransactions(
      _uid,
      from: DateTime(now.year, now.month, 1),
    );
    _sixMonthTxStream = _firestoreService.streamTransactions(_uid, from: _filterFrom, to: _filterTo);
  }

  /// Chỉ gọi hàm này ở ĐÚNG nơi filter năm/nửa năm thay đổi — không gọi ở
  /// bất kỳ setState nào khác (VD bấm cột biểu đồ không được gọi hàm này).
  void _refreshSixMonthStream() {
    _sixMonthTxStream = _firestoreService.streamTransactions(_uid, from: _filterFrom, to: _filterTo);
  }
```

Trong `_buildHalfYearFilter()`, tại 2 nơi đang đổi `_selectedYear`/`_selectedHalf` (dropdown năm và `SegmentedButton` nửa năm), thêm gọi `_refreshSixMonthStream()` **bên trong cùng khối `setState`**:

```dart
onChanged: (y) {
  if (y == null) return;
  setState(() {
    _selectedYear = y;
    _selectedMonthIndex = _defaultMonthIndex();
    _refreshSixMonthStream(); // MỚI
  });
},
...
onSelectionChanged: (selection) {
  setState(() {
    _selectedHalf = selection.first;
    _selectedMonthIndex = _defaultMonthIndex();
    _refreshSixMonthStream(); // MỚI
  });
},
```

Trong `build()`: xóa dòng `final firestoreService = FirestoreService();`, thay mọi `firestoreService.streamXxx(uid, ...)` gọi trực tiếp bằng field tương ứng (`_userStream`, `_walletsStream`, `_categoriesStream`, `_sixMonthTxStream`, `_currentMonthTxStream`). Với nhánh `else` (`!currentMonthInFilter`) đang gọi `firestoreService.streamTransactions(uid, from: currentMonthStart)` inline — thay bằng `_currentMonthTxStream` đã cache sẵn.

**Đánh đổi đã biết (chấp nhận được):** `_currentMonthTxStream` được tính mốc "tháng hiện tại" tại thời điểm mở màn (`initState`) — nếu người dùng mở app đúng lúc giao thời nửa đêm cuối tháng và giữ màn hình mở xuyên qua thời điểm đó, mốc này sẽ không tự cập nhật sang tháng mới cho tới khi mở lại màn. Đây là edge case cực hiếm, không cần xử lý thêm trong ticket này.

### 2.2. `lib/screens/home/transaction_list_screen.dart`

Cache stream giao dịch + stream danh mục, chỉ tạo lại khi bộ lọc ngày/tháng thực sự đổi (không phải khi gõ tìm kiếm hay đổi tag loại giao dịch):

```dart
class _TransactionListScreenState extends State<TransactionListScreen> {
  final _firestoreService = FirestoreService();
  final _searchController = TextEditingController();

  String _searchQuery = '';
  String _typeFilter = 'all';
  DateTime? _selectedDate;
  DateTime? _selectedMonth;

  // MỚI
  late final String _uid;
  late Stream<List<AppTransaction>> _transactionsStream;
  late final Stream<List<Category>> _categoriesStream;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _categoriesStream = _firestoreService.streamCategories(_uid);
    _transactionsStream = _buildStream(_uid); // tính lần đầu theo state mặc định
  }

  /// Chỉ gọi ở ĐÚNG nơi _selectedDate/_selectedMonth thay đổi — KHÔNG gọi khi
  /// gõ tìm kiếm hoặc đổi tag Tất cả/Thu nhập/Chi tiêu (2 việc đó lọc
  /// client-side, không cần Firestore trả dữ liệu khác).
  void _refreshTransactionsStream() {
    _transactionsStream = _buildStream(_uid);
  }

  Stream<List<AppTransaction>> _buildStream(String uid) {
    // Giữ nguyên 100% nội dung hàm này, không đổi logic bên trong
    ...
  }
```

Gọi `_refreshTransactionsStream()` bên trong `setState` ở **đúng 3 nơi** đang thay đổi `_selectedDate`/`_selectedMonth`:
1. `_selectSpecificDate()` — sau khi `picked != null`.
2. `_selectSpecificMonth()` — sau khi `confirmed == true`.
3. `onDeleted` của `Chip` bộ lọc ngày/tháng (nơi đang set cả 2 biến về `null`).

**Không** gọi `_refreshTransactionsStream()` ở: `onChanged` của ô tìm kiếm, `onTap`/`onSelected` của 3 tag loại giao dịch (`_buildTypeTag`) — 2 nơi này chỉ lọc lại danh sách đã tải, không cần dữ liệu Firestore mới.

Trong `build()`: đổi `stream: _buildStream(uid)` → `stream: _transactionsStream`, đổi `stream: _firestoreService.streamCategories(uid)` → `stream: _categoriesStream`.

## 3. Không đổi (Out of scope)

- Không đổi logic bên trong `_buildStream()`, `_defaultMonthIndex()`, `_build6MonthData()`, `_getSelectedMonthTx()` hay bất kỳ hàm tính toán/lọc dữ liệu nào khác — ticket này **chỉ đổi thời điểm tạo Stream**, không đổi cách dữ liệu được tính.
- Không sửa `WalletManagementScreen`, `ProfileScreen`, `CategoryManagementScreen`, `BudgetManagementScreen` trong ticket này — các màn này hiện là `StatelessWidget` hoặc ít gọi `setState()` trực tiếp trên chính State của màn (khác biệt về mức độ rủi ro so với 2 màn ở ticket này), cần audit riêng nếu sau này phát hiện triệu chứng giật/chậm tương tự — không tự ý mở rộng khi chưa có bằng chứng cụ thể.
- Không đổi `FirestoreService` (các hàm `streamXxx` giữ nguyên, vấn đề chỉ ở cách gọi).

## 4. Acceptance Criteria

**Dashboard:**
- [ ] Bấm liên tiếp 3-4 cột khác nhau trong biểu đồ 6 tháng → Donut chart đổi tháng hiển thị ngay lập tức, **không** có hiện tượng nháy loading ở phần Thông tin đầu trang (avatar/tên/tổng số dư) hay danh sách "Giao dịch gần đây".
- [ ] Đổi năm hoặc nửa năm ở bộ lọc → biểu đồ 6 tháng tải lại đúng dữ liệu mới (hành vi này **vẫn phải** tải lại — đây là trường hợp hợp lệ cần dữ liệu mới, không bị fix này chặn nhầm).
- [ ] Test kỹ chuỗi thao tác: đổi năm → bấm cột biểu đồ vài lần → đổi nửa năm → bấm cột biểu đồ tiếp — xác nhận dữ liệu luôn đúng, không bị lẫn dữ liệu của filter cũ.

**Danh sách giao dịch:**
- [ ] Gõ liên tục vào ô tìm kiếm (nhiều ký tự nhanh) → danh sách lọc ngay theo từng ký tự, **không** có hiện tượng nháy loading hay giật giữa chừng.
- [ ] Bấm đổi tag Tất cả/Thu nhập/Chi tiêu nhiều lần liên tiếp → lọc tức thời, không giật.
- [ ] Chọn lọc theo ngày cụ thể → chọn lọc theo tháng cụ thể → bấm "x" xóa bộ lọc → mỗi bước đều tải đúng dữ liệu tương ứng (đây là 3 trường hợp **hợp lệ cần** tải lại, phải hoạt động đúng, không bị chặn nhầm bởi fix này).
- [ ] Kết hợp: đang lọc theo 1 tháng cụ thể + gõ tìm kiếm liên tục → danh sách lọc đúng theo cả 2 điều kiện, gõ tìm kiếm không làm mất/tải lại bộ lọc tháng đang chọn.

**Chung:**
- [ ] `flutter analyze` không phát sinh lỗi/warning mới.
- [ ] Không có regression ở bất kỳ acceptance criteria nào của các ticket liên quan trước đó tới 2 file này (ticket 006 phần A — donut tương tác, ticket 009 phần B/016 — bộ lọc lịch sử giao dịch).
