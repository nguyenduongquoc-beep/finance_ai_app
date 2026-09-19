# TICKET 036 — Tối ưu tốc độ tải: song song hóa (parallelize) các lượt đọc Firestore đang chạy tuần tự không cần thiết

**Loại:** Cải tiến hiệu năng (không đổi logic nghiệp vụ, không đổi kết quả trả về)
**Độ ưu tiên:** Cao — ảnh hưởng trực tiếp tới cảm giác "mượt/trơn tru" của các tính năng cốt lõi (xem giao dịch, AI Insight, AI Report, AI Chat)
**File bị ảnh hưởng:** `lib/screens/home/transaction_detail_screen.dart`, `lib/screens/ai/ai_insight_screen.dart`, `lib/screens/ai/ai_report_screen.dart`, `lib/screens/ai/ai_chat_screen.dart`

---

## 1. Context (Bối cảnh)

Rà soát code phát hiện 4 nơi đang đọc dữ liệu Firestore theo kiểu **tuần tự (sequential `await`)** dù các lượt đọc đó **hoàn toàn độc lập với nhau** (không lượt nào cần kết quả của lượt trước để chạy) — đây là nguyên nhân trực tiếp khiến các màn hình này cảm giác tải chậm, đặc biệt rõ khi mạng có độ trễ (latency) cao:

- **`transaction_detail_screen.dart` → `_loadDetails()`:** đọc `wallets` rồi mới đọc `categories` rồi mới đọc `toWallet` (nếu là transfer) — 3 lượt đọc độc lập chạy nối tiếp.
- **`ai_insight_screen.dart` → `_loadInsights()`:** 6 lượt đọc độc lập chạy nối tiếp (giao dịch 30 ngày, danh mục, giao dịch tháng này, giao dịch tháng trước, hồ sơ người dùng, giao dịch 6 tháng cho trend chart).
- **`ai_report_screen.dart` → `_loadReportData()`:** 6 lượt đọc độc lập chạy nối tiếp (giao dịch tháng này/tháng trước/2 tháng trước, danh mục, ngân sách, mục tiêu tiết kiệm).
- **`ai_chat_screen.dart` → `_buildFinancialContext()`:** 3 lượt đọc độc lập chạy nối tiếp (giao dịch, ví, ngân sách) — chạy **mỗi lần gửi 1 tin nhắn**, nên độ trễ này lặp lại liên tục trong suốt phiên chat.

**Nguyên lý:** khi gọi `await A(); await B();` với A và B độc lập, tổng thời gian chờ = thời gian(A) + thời gian(B). Khi gọi `await Future.wait([A(), B()])`, cả 2 lượt đọc được gửi đi **đồng thời**, tổng thời gian chờ chỉ còn = max(thời gian(A), thời gian(B)) — nhanh hơn đáng kể, đặc biệt rõ khi có từ 3 lượt đọc độc lập trở lên hoặc khi mạng có độ trễ cao (dùng 4G, mạng yếu).

**Lưu ý — nơi KHÔNG cần sửa:** Home Dashboard Screen và Budget Management Screen dùng `StreamBuilder` lồng nhau (không phải chuỗi `await` tuần tự) — các Stream này được khởi tạo và bắt đầu lắng nghe **song song ngay khi được tạo** (không đợi nhau), nên **không có vấn đề hiệu năng tương tự** ở 2 màn này, không cần sửa.

## 2. Nguyên tắc thực hiện

- **Không đổi kết quả trả về hay logic tính toán phía sau** — chỉ đổi cách các lượt đọc dữ liệu được gửi đi (song song thay vì tuần tự). Toàn bộ code xử lý dữ liệu sau khi đọc xong giữ nguyên 100%.
- `Future.wait([...])` không ràng buộc kiểu dữ liệu giống nhau giữa các phần tử nếu không khai báo generic type — dùng `Future.wait<dynamic>([...])` rồi ép kiểu (`as`) lại từng phần tử theo đúng thứ tự đã khai báo trong danh sách.

## 3. Fix Requirements

### 3.1. `lib/screens/home/transaction_detail_screen.dart` — `_loadDetails()`

Thay toàn bộ hàm hiện tại bằng:
```dart
Future<Map<String, dynamic>> _loadDetails() async {
  final isTransfer = transaction.type == 'transfer' &&
      transaction.toWalletId != null &&
      transaction.toWalletId!.isNotEmpty;

  final results = await Future.wait([
    FirebaseFirestore.instance.collection('wallets').doc(transaction.walletId).get(),
    FirebaseFirestore.instance.collection('categories').doc(transaction.categoryId).get(),
    if (isTransfer)
      FirebaseFirestore.instance.collection('wallets').doc(transaction.toWalletId).get(),
  ]);

  final walletDoc = results[0];
  final categoryDoc = results[1];
  final toWalletDoc = isTransfer ? results[2] : null;

  return {
    'walletName': walletDoc.exists ? (walletDoc.data()?['walletName'] ?? 'Không rõ') : 'Không rõ',
    'categoryName': categoryDoc.exists ? (categoryDoc.data()?['name'] ?? 'Không rõ') : 'Không rõ',
    'categoryColor': categoryDoc.exists ? (categoryDoc.data()?['color'] as int?) : null,
    'categoryIcon': categoryDoc.exists ? (categoryDoc.data()?['icon'] as String?) : null,
    'toWalletName': toWalletDoc != null
        ? (toWalletDoc.exists ? (toWalletDoc.data()?['walletName'] ?? 'Không rõ') : 'Không rõ')
        : null,
  };
}
```
Danh sách truyền vào `Future.wait` ở đây đồng nhất kiểu `DocumentSnapshot<Map<String, dynamic>>` nên không cần ép kiểu `dynamic`.

### 3.2. `lib/screens/ai/ai_insight_screen.dart` — `_loadInsights()`

Chuyển `sixMonthsAgo` lên tính **trước** khối `try`, gộp toàn bộ 6 lượt đọc độc lập vào 1 `Future.wait` duy nhất. Thay đoạn đầu hàm (giữ nguyên toàn bộ phần tính toán phía sau — Financial Analytics Layer, top cuts, monthlySpending — không đổi gì thêm):

```dart
Future<void> _loadInsights() async {
  setState(() {
    _isLoading = true;
    _errorMessage = null;
  });

  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1);
  final last30Days = now.subtract(const Duration(days: 30));
  final lastMonthStart = DateTime(now.year, now.month - 1, 1);
  final lastMonthEnd = DateTime(now.year, now.month, 0, 23, 59, 59);
  final sixMonthsAgo = DateTime(now.year, now.month - 5, 1); // MỚI — chuyển lên trước try

  try {
    // MỚI — gộp toàn bộ 6 lượt đọc độc lập, gửi đi ĐỒNG THỜI thay vì tuần tự
    final results = await Future.wait<dynamic>([
      _firestoreService.streamTransactions(uid, from: last30Days).first,
      _firestoreService.streamCategories(uid).first,
      _firestoreService.streamTransactions(uid, from: monthStart).first,
      _firestoreService.streamTransactions(uid, from: lastMonthStart, to: lastMonthEnd).first,
      _firestoreService.getUserProfile(uid),
      _firestoreService.streamTransactions(uid, from: sixMonthsAgo).first,
    ]);

    final transactions = results[0] as List<AppTransaction>;
    final categories = results[1] as List<Category>;
    final monthTransactions = results[2] as List<AppTransaction>;
    final lastMonthTransactions = results[3] as List<AppTransaction>;
    final userProfile = results[4] as AppUser?;
    final trendTransactions = results[5] as List<AppTransaction>;
    final monthlyIncome = userProfile?.monthlyIncome ?? 0;

    // --- Financial Analytics Layer (Dart thuần, KHÔNG gọi AI) --- GIỮ NGUYÊN không đổi
    final issues = _analyticsService.detectIssues(
      currentMonthTx: monthTransactions,
      lastMonthTx: lastMonthTransactions,
      categories: categories,
      monthlyIncome: monthlyIncome,
    );
    final healthScore = _analyticsService.calculateHealthScore(issues);
    final heatmap = _analyticsService.computeWeeklyHeatmap(transactions, categories);

    // Top cuts (Cơ hội tiết kiệm) — GIỮ NGUYÊN không đổi
    final Map<String, double> totals = {};
    for (final tx in transactions.where((t) => t.type == 'expense')) {
      final cat = categories.where((c) => c.categoryId == tx.categoryId).firstOrNull;
      final name = cat?.name ?? 'Khác';
      totals[name] = (totals[name] ?? 0) + tx.amount;
    }
    final sortedCats = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topCuts = sortedCats.take(3).map((e) {
      final dailyAvg = e.value / 30;
      return _CategoryCut(
        categoryName: e.key,
        currentDailyAvg: dailyAvg,
        targetDailyAvg: dailyAvg * 0.75,
      );
    }).toList();

    // Dữ liệu 6 tháng cho Trend chart — dùng lại trendTransactions đã đọc song song ở trên,
    // KHÔNG gọi Firestore thêm ở đây nữa (trước đây gọi tuần tự riêng ở cuối hàm)
    final List<double> monthlySpending = [];
    for (int i = 5; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final monthEnd = DateTime(month.year, month.month + 1, 0);
      final monthTotal = trendTransactions
          .where((t) =>
              t.type == 'expense' &&
              t.date.isAfter(month.subtract(const Duration(days: 1))) &&
              t.date.isBefore(monthEnd.add(const Duration(days: 1))))
          .fold<double>(0, (a, t) => a + t.amount);
      monthlySpending.add(monthTotal);
    }

    if (!mounted) return;
    setState(() {
      _healthScore = healthScore;
      _issues = issues;
      _weeklyHeatmap = heatmap;
      _topCuts = topCuts;
      _monthlySpendingForTrend = monthlySpending;
      _isLoading = false;
    });
  } catch (e, stackTrace) {
    debugPrint('AI Insight Data Load error: $e');
    debugPrintStack(stackTrace: stackTrace);
    if (!mounted) return;
    setState(() {
      _errorMessage = 'Không thể tải phân tích tài chính lúc này. Vui lòng kiểm tra kết nối.';
      _isLoading = false;
    });
  }
}
```

### 3.3. `lib/screens/ai/ai_report_screen.dart` — `_loadReportData()`

Thay đoạn đọc dữ liệu (giữ nguyên toàn bộ phần tính toán phía sau — tổng thu/chi, % thay đổi, gộp theo danh mục, sinh insight):

```dart
try {
  // MỚI — gộp 6 lượt đọc độc lập, gửi đồng thời
  final results = await Future.wait<dynamic>([
    _firestoreService.streamTransactions(uid, from: monthStart).first,
    _firestoreService.streamTransactions(uid, from: lastMonthStart, to: lastMonthEnd).first,
    _firestoreService.streamTransactions(uid, from: twoMonthsAgoStart, to: twoMonthsAgoEnd).first,
    _firestoreService.streamCategories(uid).first,
    _firestoreService.streamBudgets(uid, month: AppFormatters.month(now)).first,
    _firestoreService.streamSavingGoals(uid).first,
  ]);

  final List<AppTransaction> currentTx = results[0] as List<AppTransaction>;
  final List<AppTransaction> lastMonthTx = results[1] as List<AppTransaction>;
  final List<AppTransaction> twoMonthsAgoTx = results[2] as List<AppTransaction>;
  final categories = results[3] as List<Category>;
  final budgets = results[4] as List<Budget>;
  final savingGoals = results[5] as List<SavingGoal>;

  // --- Toàn bộ phần tính toán phía dưới GIỮ NGUYÊN không đổi ---
  ...
```
(Phần code từ `// 1. Tính tổng thu/chi tháng này` trở về sau **giữ nguyên hoàn toàn**, chỉ thay đúng đoạn khai báo 6 biến ở trên.)

### 3.4. `lib/screens/ai/ai_chat_screen.dart` — `_buildFinancialContext()`

```dart
Future<String> _buildFinancialContext(String uid) async {
  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1);

  // MỚI — gộp 3 lượt đọc độc lập, gửi đồng thời
  final results = await Future.wait<dynamic>([
    _firestoreService.streamTransactions(uid, from: monthStart).first,
    _firestoreService.streamWallets(uid).first,
    _firestoreService.streamBudgets(uid, month: AppFormatters.month(now)).first,
  ]);

  final transactions = results[0] as List<AppTransaction>;
  final wallets = results[1] as List<Wallet>;
  final budgets = results[2] as List<Budget>;

  // --- Toàn bộ phần tính toán phía dưới GIỮ NGUYÊN không đổi ---
  final income = transactions.where((t) => t.type == 'income').fold<double>(0, (a, t) => a + t.amount);
  ...
```
(Phần code còn lại của hàm giữ nguyên hoàn toàn.)

## 4. Không đổi (Out of scope)

- Không đổi `Home Dashboard Screen`, `Budget Management Screen` — đã dùng `StreamBuilder` lồng nhau (song song sẵn theo bản chất), không có vấn đề hiệu năng tương tự.
- Không đổi `FirestoreService` — chỉ đổi cách gọi ở tầng UI, không đổi bất kỳ hàm nào trong service layer.
- Không đổi logic tính toán, không đổi kết quả hiển thị — chỉ đổi **thời gian chờ** để có được dữ liệu.
- Không thêm cơ chế cache dữ liệu giữa các lần mở màn hình (ngoài phạm vi ticket này — có thể cân nhắc ở giai đoạn phát triển sau nếu cần tối ưu thêm).

## 5. Acceptance Criteria

- [ ] Mở Transaction Detail Screen của 1 giao dịch thường → thông tin hiện đầy đủ, đúng, thời gian tải cảm nhận nhanh hơn rõ rệt so với trước (đặc biệt trên mạng có độ trễ, VD 4G).
- [ ] Mở Transaction Detail Screen của 1 giao dịch `transfer` → vẫn hiện đúng "Từ ví"/"Đến ví" như trước, không thiếu dữ liệu.
- [ ] Mở AI Insight Screen → Điểm sức khỏe, danh sách vấn đề, heatmap hiện đúng y hệt kết quả trước khi sửa (đối chiếu số liệu để xác nhận logic không đổi), chỉ khác về tốc độ tải.
- [ ] Mở rộng "Xu hướng chi tiêu 6 tháng" ở AI Insight → biểu đồ hiện đúng dữ liệu (đã lấy sẵn từ `trendTransactions` trong lượt tải đầu, không gọi Firestore thêm lần nữa khi mở rộng card này).
- [ ] Mở AI Report Screen → toàn bộ 4 card (hero, cơ cấu chi tiêu, xu hướng 3 tháng, đánh giá AI) hiện đúng dữ liệu như trước, tải nhanh hơn.
- [ ] Gửi liên tiếp 3-4 tin nhắn trong AI Chat → mỗi lần gửi, thời gian chờ tổng hợp ngữ cảnh tài chính (trước khi Gemini bắt đầu trả lời) giảm rõ rệt so với trước.
- [ ] Test với tài khoản có **nhiều dữ liệu** (nhiều giao dịch/danh mục) để đảm bảo việc gộp `Future.wait` không gây tràn bộ nhớ hay lỗi khi tải đồng thời nhiều truy vấn lớn.
- [ ] `flutter analyze` không phát sinh lỗi/warning mới — đặc biệt kiểm tra kỹ các dòng ép kiểu `as List<...>`/`as AppUser?` không bị sai kiểu dữ liệu.
