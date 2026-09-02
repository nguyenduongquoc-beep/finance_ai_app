# TICKET 025 — Đổi kiến trúc Ngân sách sang tính `spentAmount` trực tiếp từ Transaction (bỏ field cộng dồn) + Redesign màn Ngân sách theo mockup mới + màn Thiết lập ngân sách

**Loại:** Refactor kiến trúc (thay đổi cách tính toán cốt lõi) + UI/UX redesign + Feature mới (màn Thiết lập ngân sách)
**Độ ưu tiên:** Cao
**File bị ảnh hưởng:** `lib/models/budget_model.dart`, `lib/services/firestore_service.dart`, `lib/screens/management/budget_management_screen.dart`, `lib/widgets/budget_progress_card.dart`, `lib/utils/validation_utils.dart`, `lib/screens/ai/ai_chat_screen.dart`
**File mới:** `lib/screens/management/budget_setup_screen.dart`

> **⚠️ Lưu ý bắt buộc trước khi code:** ngoài 4 file chính sửa UI/model/service, có **2 nơi khác trong codebase đang đọc trực tiếp `budget.spent`** mà nếu bỏ sót sẽ gây lỗi biên dịch hoặc vỡ tính năng ngầm (không lỗi biên dịch nhưng sai kết quả) — xem mục 1.6 bắt buộc phải làm cùng lúc, không phải việc tùy chọn.

---

## 0. Bắt buộc đọc trước khi code (theo đúng yêu cầu phân tích kiến trúc)

Trước khi sửa bất kỳ dòng code nào, xác nhận lại đúng hiện trạng sau (đã rà trong codebase, agent thực thi **không cần tự dò lại từ đầu**, dùng đúng thông tin dưới đây làm nền):

- **`AppTransaction` model** (`lib/models/transaction_model.dart`): có sẵn `categoryId` (String, tham chiếu logic tới `categories/{id}`, **không** lưu tên category), `type` (`'income'`/`'expense'`), `amount` (double), `date` (lưu **String ISO8601** trong Firestore, parse bằng `DateTime.parse` khi đọc).
- **`Category` xác định bằng `categoryId`** (String), không phải theo tên — đúng như yêu cầu mục 15 đã hỏi.
- **Firestore hiện tại đã tổ chức đúng nguyên tắc "1 Budget riêng cho mỗi tháng"** — mỗi document `budgets/{budgetId}` có field `month` (string `"MM/yyyy"`) + `categoryId` riêng, **không có** tình trạng "1 Budget duy nhất đổi tháng". Yêu cầu mục 1 trong bản đề xuất **đã được đáp ứng sẵn từ trước**, không cần sửa gì ở điểm này.
- **`Budget` model/service ĐÃ TỒN TẠI** (`lib/models/budget_model.dart`, các hàm CRUD trong `FirestoreService`) — đây là điểm mấu chốt cần sửa, không phải tạo mới từ đầu:
  ```dart
  class Budget {
    final String budgetId, userId, categoryId, month;
    final double limit;
    final double spent; // ⚠️ ĐANG LÀ FIELD LƯU TRỰC TIẾP TRONG FIRESTORE
    double get percentUsed => limit == 0 ? 0 : (spent / limit).clamp(0, 1.5); // ⚠️ bị CLAMP ở 150%
    bool get isOverBudget => spent > limit;
    bool get isNearLimit => percentUsed >= 0.9 && !isOverBudget; // ⚠️ ngưỡng 90%, không phải 80%
  }
  ```
  `spent` hiện được cộng dồn bằng `FieldValue.increment()` qua hàm `FirestoreService.adjustBudgetSpent()`, gọi từ `createTransaction()`, `updateTransactionSafely()`, `deleteTransaction()` mỗi khi có giao dịch `expense`. Đây **chính là nợ kỹ thuật đã được ghi nhận từ trước** ở `context/ARCHITECTURE.md` mục 5.3 ("`Budget.spent` tính bằng `FieldValue.increment` ở client → có thể lệch nếu nhiều thiết bị sửa cùng lúc") — bản đề xuất trong tài liệu đính kèm về bản chất là **yêu cầu dọn đúng món nợ kỹ thuật này**, không phải ý tưởng ngẫu nhiên.

**Kết luận kiến trúc:** giữ nguyên toàn bộ hạ tầng Firestore hiện có (collection `budgets`, field `userId/categoryId/month/limit`), **chỉ bỏ vai trò "nguồn sự thật" của field `spent`**, thay bằng tính `spentAmount` **on-the-fly** từ `transactions` mỗi lần hiển thị — đúng tinh thần "Budget.limit + Transaction thực tế → Tính spentAmount → Hiển thị UI" trong bản đề xuất, và đúng pattern client-side aggregation **đã dùng sẵn** ở `home_dashboard_screen.dart._buildCategoryPie()` / `ai_insight_screen.dart` — không phát minh cách làm mới, tái dùng đúng convention đã có trong dự án.

## 1. Fix Requirements

### 1.1. `lib/models/budget_model.dart` — bỏ `spent` khỏi model, đổi các getter thành hàm nhận `spentAmount` từ ngoài truyền vào

```dart
class Budget {
  final String budgetId;
  final String userId;
  final String categoryId;
  final double limit;
  final String month; // "MM/yyyy" — GIỮ NGUYÊN, đã đúng nguyên tắc 1 Budget/tháng

  Budget({
    required this.budgetId,
    required this.userId,
    required this.categoryId,
    required this.limit,
    required this.month,
  });

  factory Budget.fromMap(Map<String, dynamic> map, String id) {
    return Budget(
      budgetId: id,
      userId: map['userId'] ?? '',
      categoryId: map['categoryId'] ?? '',
      limit: (map['limit'] ?? 0).toDouble(),
      month: map['month'] ?? '',
      // Lưu ý: field 'spent' cũ (nếu còn sót trong document cũ) KHÔNG đọc nữa,
      // không throw lỗi — Firestore vẫn có thể còn field thừa, bỏ qua an toàn.
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'categoryId': categoryId,
      'limit': limit,
      'month': month,
      // Không còn ghi field 'spent' — không còn là nguồn sự thật.
    };
  }

  /// Tính % đã dùng — KHÔNG clamp giới hạn trên, cho phép vượt >100%
  /// (chỉ clamp 0 ở cận dưới để tránh số âm hiển thị sai khi có dữ liệu bất thường).
  double percentUsed(double spentAmount) =>
      limit <= 0 ? 0 : (spentAmount / limit).clamp(0, double.infinity);

  bool isOverBudget(double spentAmount) => spentAmount > limit;

  /// Cảnh báo sắp vượt: 80–99%, đúng theo yêu cầu mới (KHÔNG còn 90%).
  bool isNearLimit(double spentAmount) {
    final p = percentUsed(spentAmount);
    return p >= 0.8 && !isOverBudget(spentAmount);
  }

  double remaining(double spentAmount) => limit - spentAmount; // có thể âm nếu vượt — không clamp
}
```

**Vì sao đổi từ field/getter cố định sang hàm nhận tham số:** `Budget` giờ chỉ còn là "giới hạn đã đặt", còn "đã chi bao nhiêu" là dữ liệu **tính động** ở tầng UI (mục 1.3) — tách đúng 2 trách nhiệm, không trộn dữ liệu tĩnh (limit) với dữ liệu động (spent) trong cùng 1 object lấy thẳng từ Firestore.

### 1.2. `lib/services/firestore_service.dart` — bỏ toàn bộ phần cộng dồn `spent`

- **Xóa** hàm `adjustBudgetSpent()` — không còn cần thiết.
- Trong `createTransaction()`: xóa toàn bộ đoạn code liên quan tới `budgetRef`/`budgetSnap`/cộng `spent` bên trong `runTransaction`. Giữ nguyên phần ghi `transactions` doc + cập nhật `wallets.balance` (không đụng tới, đây là nguyên tắc RULES.md mục 4 vẫn áp dụng đúng cho `wallets.balance`, chỉ `budgets.spent` là được gỡ bỏ).
- Trong `updateTransactionSafely()`: xóa toàn bộ phần cập nhật `spent` (cả hoàn tác oldTx lẫn áp dụng newTx).
- Trong `deleteTransaction()`: xóa dòng `adjustBudgetSpent(...)`.
- **Thêm hàm mới trong `FirestoreService`** — tính tổng chi tiêu (`expense`) theo `categoryId` trong 1 tháng cụ thể. Dùng lại đúng composite index đã có (`userId` + `date`), **không** thêm `where('categoryId', ...)` vào query Firestore (tránh cần index mới `userId+categoryId+date`) — lọc `categoryId` bằng Dart sau khi đã có danh sách giao dịch trong tháng, đúng pattern client-side aggregation đã dùng xuyên suốt dự án:
  ```dart
  /// Tính tổng chi tiêu (expense) của 1 category trong 1 tháng cụ thể —
  /// tính ĐỘNG từ transactions, không đọc field spent (đã bỏ khỏi Budget).
  /// Dùng cho: cảnh báo vượt ngân sách khi thêm giao dịch (validation_utils.dart),
  /// và kiểm tra vượt mốc 80% để bắn thông báo (createTransaction/updateTransactionSafely).
  Future<double> getCategorySpentThisMonth(
    String userId,
    String categoryId, {
    DateTime? month, // mặc định tháng hiện tại nếu không truyền
  }) async {
    final target = month ?? DateTime.now();
    final monthStart = DateTime(target.year, target.month, 1);
    final monthEnd = DateTime(target.year, target.month + 1, 1).subtract(const Duration(seconds: 1));
    final txQuery = await _db
        .collection('transactions')
        .where('userId', isEqualTo: userId)
        .where('date', isGreaterThanOrEqualTo: monthStart.toIso8601String())
        .where('date', isLessThanOrEqualTo: monthEnd.toIso8601String())
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

- **Giữ nguyên cảnh báo ngân sách qua `AppNotification`**, đổi nguồn tính toán sang `getCategorySpentThisMonth()` ở trên, **đổi ngưỡng cảnh báo từ 90% → 80%**. Code chính xác cho từng hàm:

  **Trong `createTransaction()`** — giữ nguyên đoạn tìm `budgetRef` (query `budgets` theo `categoryId`+`month`, **trước** `runTransaction`, chỉ để biết category này có Budget hay không), xóa mọi thao tác đọc/ghi `spent` bên trong `runTransaction`. Đoạn kiểm tra thông báo **sau khi** `runTransaction` commit thành công, thay bằng:
  ```dart
  if (tx.type == 'expense' && budgetRef != null) {
    final budgetDoc = await budgetRef.get();
    final data = budgetDoc.data() as Map<String, dynamic>?;
    if (data != null) {
      final limit = (data['limit'] as num).toDouble();
      final newSpent = await getCategorySpentThisMonth(tx.userId, tx.categoryId, month: tx.date);
      final oldSpent = newSpent - tx.amount; // trạng thái trước khi có giao dịch vừa tạo
      if (limit > 0 && newSpent >= limit * 0.8 && oldSpent < limit * 0.8) {
        await createNotification(AppNotification(
          notificationId: '',
          userId: tx.userId,
          title: 'Cảnh báo ngân sách',
          content: 'Bạn đã tiêu vượt 80% ngân sách tháng $monthStr cho danh mục này.',
          status: 'unread',
          type: 'budget',
          createdAt: DateTime.now(),
        ));
      }
    }
  }
  ```

  **Trong `updateTransactionSafely()`** — giữ nguyên cách tìm `oldBudgetRef`/`newBudgetRef` đã có (xử lý đúng cả trường hợp đổi category), xóa các đoạn cộng/trừ `spent`. Đoạn kiểm tra thông báo cuối hàm (hiện đang check `updatedBudgetQuery` sau khi update) đổi thành:
  ```dart
  if (newTx.type == 'expense' && newBudgetRef != null) {
    final budgetDoc = await newBudgetRef.get();
    final data = budgetDoc.data() as Map<String, dynamic>?;
    if (data != null) {
      final limit = (data['limit'] as num).toDouble();
      final newSpent = await getCategorySpentThisMonth(newTx.userId, newTx.categoryId, month: newTx.date);
      // So sánh trước/sau dựa trên đúng phần chênh lệch của lần sửa này
      final delta = newTx.categoryId == oldTx.categoryId ? (newTx.amount - oldTx.amount) : newTx.amount;
      final oldSpent = newSpent - delta;
      if (limit > 0 && newSpent >= limit * 0.8 && oldSpent < limit * 0.8) {
        await createNotification(AppNotification(
          notificationId: '',
          userId: newTx.userId,
          title: 'Cảnh báo ngân sách',
          content: 'Giao dịch vừa sửa đã làm bạn tiêu vượt 80% ngân sách tháng $monthStrNew cho danh mục này.',
          status: 'unread',
          type: 'budget',
          createdAt: DateTime.now(),
        ));
      }
    }
  }
  ```

  **Trong `deleteTransaction()`** — chỉ cần xóa dòng gọi `adjustBudgetSpent(...)` như đã ghi ở trên, **không** cần thêm logic thông báo (hành vi hiện tại vốn không bắn thông báo khi xóa giao dịch, giữ nguyên).

### 1.3. `lib/widgets/budget_progress_card.dart` — nhận `spentAmount` từ ngoài, không tự đọc `budget.spent`

Đổi constructor: thêm `required double spentAmount`. Toàn bộ nội dung hiện có (`isOver`, `isNear`, màu sắc, `LinearPercentIndicator`, dòng "Đã vượt hạn mức...") đổi từ gọi `budget.isOverBudget`/`budget.spent`/`budget.percentUsed` sang gọi `budget.isOverBudget(spentAmount)`/`spentAmount`/`budget.percentUsed(spentAmount)`.

**Về hiển thị khi vượt >100%:** thanh `LinearPercentIndicator.percent` bắt buộc clamp `0..1` (giới hạn kỹ thuật của widget, không thể vẽ vượt khung) — nhưng **số/% hiển thị bằng chữ (`'${(percentUsed*100).round()}% đã sử dụng'`, số tiền, "Đã vượt hạn mức X VNĐ") giữ nguyên giá trị thật, không được làm tròn về 100%.** Khi `isOverBudget == true`, thanh progress tô màu `AppColors.expense` đầy 100% để báo hiệu trực quan, chữ vẫn hiện đúng số thật (VD "133%").

### 1.4. `lib/screens/management/budget_management_screen.dart` — redesign toàn bộ theo mockup + chuyển sang tính `spentAmount` động

**Đổi từ `StatelessWidget` sang `StatefulWidget`** — cần lưu state tháng đang chọn (`DateTime _selectedMonth`, mặc định tháng hiện tại).

**Cấu trúc màn hình mới (khớp mockup `budget-management__1_.png`):**

1. **AppBar**: title `'Ngân sách'`, nút back mặc định.
2. **Hàng "Thời gian áp dụng"**: label bên trái (`AppColors.textSecondary`) + tên tháng đang chọn bên phải (`AppColors.primary`, bold, VD `'Tháng 8, 2026'`) — bấm vào mở dialog chọn tháng/năm, **tái dùng đúng pattern dialog đã có** ở `transaction_list_screen._selectSpecificMonth()` (2 `DropdownButton` Tháng + Năm trong `AlertDialog`) thay vì viết dialog mới.
3. **Card tối "TỔNG NGÂN SÁCH"** — `Container` bo góc 20, nền gradient/màu tối (dùng `AppColors.textPrimary`-tối hoặc màu cố định tối riêng cho card này theo đúng mockup, ghi `// TODO: chuẩn hóa theo AppColors nếu có token màu tối chính thức` nếu chưa có token phù hợp — theo đúng quy ước `RULES.md` mục 3), bên trong:
   - Label nhỏ `'TỔNG NGÂN SÁCH'` màu xanh nhạt/`AppColors.income`.
   - Dòng lớn `'${AppFormatters.currency(totalSpent)} / ${AppFormatters.currency(totalLimit)}'`, chữ trắng, bold, cỡ lớn.
   - Vòng tròn % ở góc phải (`CircularProgressIndicator` hoặc vẽ tay bằng `Stack` + `CircularProgressIndicator` nền + text `%` ở giữa) — hiển thị `(totalSpent/totalLimit*100).round()%`, không clamp.
   - `totalLimit` = tổng `limit` của **tất cả Budget trong tháng đang chọn** (đúng yêu cầu mục 7 — chỉ tính category **đã có Budget**, không phải toàn bộ chi tiêu).
   - `totalSpent` = tổng `spentAmount` đã tính cho **từng category có Budget** (không phải tổng toàn bộ chi tiêu tháng đó — 1 giao dịch thuộc category **chưa có Budget** không được cộng vào tổng này, đúng yêu cầu mục 10).
4. **Tiêu đề `'Hạn mức chi tiêu chi tiết'`**.
5. **Danh sách `BudgetProgressCard`** (đã sửa ở mục 1.3), style card trắng bo góc theo mockup, mỗi card 1 category budget + `spentAmount` tương ứng.
6. **Nút `'Thiết lập ngân sách'`** — full-width, nền tối (đồng bộ tông màu với card TỔNG NGÂN SÁCH), thay cho `FloatingActionButton` hiện tại → điều hướng sang `BudgetSetupScreen` (mục 1.5), truyền theo `_selectedMonth` đang chọn.

**Cách lấy dữ liệu (1 lần cho cả màn, không N+1 query):**
```dart
final monthStart = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
final monthEnd = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1)
    .subtract(const Duration(seconds: 1));
final monthKey = AppFormatters.month(_selectedMonth); // "MM/yyyy"

StreamBuilder<List<Budget>>(
  stream: firestoreService.streamBudgets(uid, month: monthKey),
  builder: (context, budgetSnap) {
    final budgets = budgetSnap.data ?? [];
    return StreamBuilder<List<AppTransaction>>(
      stream: firestoreService.streamTransactions(uid, from: monthStart, to: monthEnd),
      builder: (context, txSnap) {
        final monthTx = txSnap.data ?? [];
        final Map<String, double> spentByCategory = {};
        for (final tx in monthTx.where((t) => t.type == 'expense')) {
          spentByCategory[tx.categoryId] = (spentByCategory[tx.categoryId] ?? 0) + tx.amount;
        }
        // totalLimit/totalSpent + build list từ budgets + spentByCategory[budget.categoryId] ?? 0
        ...
      },
    );
  },
)
```
Nhờ dùng `snapshots()` (real-time), **mọi thao tác sửa/xóa/đổi category của 1 giao dịch tự động khiến `monthTx` cập nhật lại → `spentByCategory` tính lại đúng ngay lập tức, không cần viết thêm bất kỳ logic đồng bộ thủ công nào** — đây chính là câu trả lời cho yêu cầu mục 6 trong bản đề xuất ("Edit/Delete Transaction phải tự động ảnh hưởng Budget"): với kiến trúc tính động, yêu cầu này **tự động đúng theo thiết kế**, không cần code riêng.

### 1.5. `lib/screens/management/budget_setup_screen.dart` (MỚI) — màn Thiết lập ngân sách

Nhận `DateTime initialMonth` (tháng đang xem ở màn chính) làm tham số constructor.

**Nội dung theo đúng yêu cầu mục 14:**
- Chọn tháng (dùng lại dialog chọn tháng/năm như mục 1.4.2, mặc định = `initialMonth`).
- Danh sách category **expense** đã có Budget cho tháng đang chọn — mỗi dòng: tên category + `TextField` nhập `limit` + nút xóa (icon `Icons.delete_outline`, gọi `firestoreService.deleteBudget(budgetId)`, xác nhận trước khi xóa qua `AlertDialog` đơn giản).
- Nút **"Thêm danh mục"** — mở `DropdownButtonFormField<Category>` liệt kê **category expense chưa có trong danh sách Budget tháng này** (lọc client-side, tránh trùng), chọn xong thêm 1 dòng nhập limit mới vào danh sách cục bộ (chưa lưu Firestore ngay, chỉ lưu khi bấm "Lưu").
- Nút **"Lưu"** (cuối màn hoặc AppBar action) — với mỗi dòng: nếu là budget đã tồn tại → `updateBudget(budgetId, {'limit': ...})`; nếu là dòng mới thêm → `createBudget(Budget(...))`. Dùng `Future.wait` cho tất cả thay đổi, hiện loading khi đang lưu, `AppSnackbar.show` báo thành công/thất bại, `Navigator.pop()` sau khi lưu xong.
- **Tùy chọn "Sao chép ngân sách tháng trước"** (nút phụ, không bắt buộc phải làm nếu vượt thời gian — ghi rõ đây là optional theo đúng bản đề xuất mục 14 "Có thể có thêm..."): đọc `streamBudgets(uid, month: thángTrước).first`, với mỗi budget tháng trước **chưa có** ở danh sách tháng đang thiết lập → thêm vào danh sách cục bộ với đúng `categoryId`+`limit`, không tự lưu ngay (người dùng vẫn bấm "Lưu" để xác nhận).
- **Validate không cho 2 dòng cùng category** trong cùng lần thiết lập (client-side, dropdown "Thêm danh mục" đã tự loại category trùng — mục "Thêm danh mục" ở trên).

### 1.6. Bắt buộc sửa 2 nơi khác đang đọc `budget.spent` trực tiếp (dễ bỏ sót, gây vỡ tính năng)

Rà bằng `grep -r "\.spent" lib/` sau khi sửa `Budget` model để chắc chắn không bỏ sót thêm chỗ nào ngoài 2 nơi đã xác định dưới đây.

**a) `lib/utils/validation_utils.dart` — `exceedsCategoryBudget()`:**

Đây là logic đứng sau cảnh báo *"Giao dịch sẽ vượt quá ngân sách danh mục"* ở màn Thêm giao dịch (`add_transaction_screen.dart._runValidation()`) — **không đổi signature hàm này** (để không phải sửa nơi gọi), chỉ đổi cách tính bên trong:

```dart
static Future<bool> exceedsCategoryBudget({
  required String userId,
  required String categoryId,
  required double amount,
  required FirestoreService firestoreService,
}) async {
  final budget = await firestoreService.getCategoryBudget(userId, categoryId);
  if (budget == null) return false; // Chưa có Budget cho category này — không cảnh báo (đúng nguyên tắc mục 10)
  final currentSpent = await firestoreService.getCategorySpentThisMonth(userId, categoryId);
  final projectedSpent = currentSpent + amount; // spent hiện tại + số tiền đang định nhập
  return projectedSpent > budget.limit;
}
```

**b) `lib/screens/ai/ai_chat_screen.dart` — `_buildFinancialContext()`:**

Hàm này **đã fetch sẵn** `transactions` của tháng hiện tại (`streamTransactions(uid, from: monthStart).first`) ngay phía trên đoạn build context — **tái dùng đúng danh sách đó**, không query thêm:

```dart
if (budgets.isNotEmpty) {
  final Map<String, double> spentByCategory = {};
  for (final t in transactions.where((t) => t.type == 'expense')) {
    spentByCategory[t.categoryId] = (spentByCategory[t.categoryId] ?? 0) + t.amount;
  }
  buffer.writeln('\nTình trạng ngân sách:');
  for (final b in budgets) {
    final spent = spentByCategory[b.categoryId] ?? 0;
    final percent = b.limit > 0 ? (spent / b.limit * 100).round() : 0;
    buffer.writeln('- Danh mục ${b.categoryId}: đã chi ${AppFormatters.number(spent)}/${AppFormatters.number(b.limit)} đ ($percent%)');
  }
}
```

## 2. Nguyên tắc dữ liệu cần đảm bảo (đối chiếu đúng bản đề xuất, không được sai)

| # | Yêu cầu | Cách ticket này đáp ứng |
|---|---|---|
| 3 | `spentAmount` phải tính từ Transaction thực tế | Mục 1.1–1.4 — bỏ hẳn field lưu cứng, tính động |
| 4 | Chỉ `Expense` ảnh hưởng Budget | `.where((t) => t.type == 'expense')` ở mọi chỗ tính tổng |
| 5 | Transaction phải khớp đúng tháng + category | Lọc theo `categoryId` + khoảng `monthStart`–`monthEnd` |
| 6 | Sửa/xóa/đổi category transaction tự động ảnh hưởng | Tự động đúng nhờ `snapshots()` real-time + tính lại toàn bộ mỗi lần build (mục 1.4) |
| 7 | Tổng ngân sách = tổng limit các category; tổng đã chi = tổng spent các category | Mục 1.4 bước 3 |
| 8 | Percentage không clamp về 100%, remaining có thể âm | `Budget.percentUsed()`/`remaining()` không clamp (mục 1.1) |
| 9 | Trạng thái: <80% bình thường / 80–99% cảnh báo / ≥100% vượt | `isNearLimit()` đổi ngưỡng 80% (mục 1.1) |
| 10 | Category chưa có Budget → không tự tạo Budget | Không có logic auto-create Budget ở bất kỳ đâu trong ticket này |
| 11 | Không ép tổng category = 1 tổng cố định | Không thêm validate nào ép buộc điều này |
| 12 | Budget không gắn Wallet | `Budget` model không có field `walletId`, giữ nguyên |

## 3. Không đổi (Out of scope)

- Không đổi `wallets.balance` hay cách `adjustWalletBalance()` hoạt động — chỉ `budgets.spent` bị loại bỏ, nguyên tắc atomic cho ví (ticket 010) giữ nguyên 100%.
- Không thêm composite index Firestore mới — mọi truy vấn tổng hợp đều dùng lại `streamTransactions(uid, from, to)` đã có sẵn index, gộp bằng Dart.
- Không tự động tạo Budget cho category chưa từng thiết lập, dù category đó có giao dịch expense mới (đúng yêu cầu mục 10).
- Không migrate dữ liệu `spent` cũ trong các document `budgets` đã tồn tại — field đó chỉ đơn giản không còn được đọc/ghi nữa (an toàn, không throw lỗi nhờ `fromMap` dùng `??`).
- Không làm 2 loại thông báo riêng biệt cho "sắp vượt" (80%) và "đã vượt" (100%) — chỉ giữ 1 thông báo khi vừa vượt mốc 80%, đúng phạm vi thông báo đã có từ trước (chỉ đổi ngưỡng số, không mở rộng thêm loại thông báo mới).
- Không đổi `context/SCHEMA.md`/`ARCHITECTURE.md` trong ticket này — nếu ticket được duyệt và triển khai, **cần 1 bước riêng cập nhật lại 2 file đó** (xóa mô tả field `spent` ở mục 2.5 `SCHEMA.md`, xóa dòng nợ kỹ thuật #3 ở `ARCHITECTURE.md` vì đã được giải quyết, và cập nhật `RULES.md` mục 4 — dòng "Mọi write ảnh hưởng tới `budgets.spent`..." sẽ không còn đúng sau ticket này) — ghi chú lại để làm ở bước tài liệu hóa sau, không bắt buộc trong lần code này nhưng nên làm sớm để tài liệu không nói sai kiến trúc thật.

## 4. Acceptance Criteria

- [ ] Tạo Budget "Ăn uống" tháng 8/2026, limit 2.000.000đ → tạo 3 giao dịch expense category Ăn uống (100k/150k/200k) → card hiện đúng "450.000 VNĐ / 2.000.000 VNĐ", "Đã dùng 23%".
- [ ] Sửa giao dịch 200k thành 300k → card tự cập nhật thành "550.000 VNĐ", không cần thao tác gì thêm ngoài lưu giao dịch.
- [ ] Xóa 1 giao dịch trong 3 giao dịch trên → tổng card giảm đúng số tiền vừa xóa.
- [ ] Đổi category của 1 giao dịch từ "Ăn uống" sang "Mua sắm" (cả 2 đều có Budget tháng đó) → số tiền tự chuyển đúng: Ăn uống giảm, Mua sắm tăng, không cần code đồng bộ thủ công nào khác ngoài redesign đã làm.
- [ ] Chi vượt limit (VD limit 1.000.000, chi 1.200.000) → card hiện đúng "120%" (không bị ép về 100%), thanh progress tô đỏ đầy, dòng "Đã vượt hạn mức 200.000 VNĐ" hiện đúng.
- [ ] Card "TỔNG NGÂN SÁCH" hiện đúng tổng theo công thức mục 7, khớp % vòng tròn góc phải.
- [ ] Tạo giao dịch expense cho 1 category **chưa có Budget** tháng đó → không xuất hiện Budget mới nào tự động, giao dịch vẫn lưu bình thường, không ảnh hưởng tới tổng "TỔNG NGÂN SÁCH".
- [ ] Đổi "Thời gian áp dụng" sang tháng khác → toàn bộ danh sách + tổng ngân sách đổi đúng theo đúng Budget/giao dịch của tháng đó (không lẫn dữ liệu tháng khác).
- [ ] Bấm "Thiết lập ngân sách" → vào đúng màn mới, thêm 1 category chưa có budget + nhập limit → Lưu → quay lại màn chính thấy card mới xuất hiện đúng.
- [ ] Ở màn Thiết lập, xóa 1 category khỏi Budget → Lưu → card tương ứng biến mất ở màn chính, giao dịch cũ thuộc category đó **không bị xóa** (chỉ xóa liên kết Budget, không đụng transactions).
- [ ] (Nếu triển khai) Bấm "Sao chép ngân sách tháng trước" ở màn Thiết lập cho 1 tháng chưa có Budget nào → danh sách tự điền đúng theo tháng trước, vẫn cần bấm "Lưu" mới thực sự ghi vào Firestore.
- [ ] Giao dịch expense mới khiến 1 category vừa vượt mốc 80% → có đúng 1 thông báo mới trong `NotificationScreen`, không bắn lặp lại nếu tiếp tục thêm giao dịch mà vẫn trong khoảng 80–99% (chỉ bắn khi **vừa vượt qua** mốc, không bắn mỗi lần).
- [ ] `flutter analyze` không phát sinh lỗi mới — đặc biệt kiểm tra không còn nơi nào gọi `budget.spent`/`budget.isOverBudget`/`budget.percentUsed`/`budget.isNearLimit` theo kiểu getter cũ (phải đổi hết sang dạng hàm nhận `spentAmount`), và không còn nơi nào trong toàn bộ `lib/` tham chiếu field `spent` đã bị xóa (`grep -r "\.spent" lib/` sạch, trừ các biến cục bộ tự đặt tên `spent`/`spentAmount`/`newSpent`/`oldSpent` không liên quan tới `Budget` model).
- [ ] Ở màn Thêm giao dịch, chọn category đã có Budget tháng này gần chạm limit → nhập số tiền khiến tổng vượt limit → cảnh báo "Giao dịch sẽ vượt quá ngân sách danh mục" **vẫn hiện đúng** như trước khi đổi kiến trúc (xác nhận `validation_utils.dart` không bị vỡ sau khi bỏ field `spent`).
- [ ] Mở AI Chat, hỏi về tình trạng ngân sách (VD "Ngân sách nào sắp vượt hạn mức?") → AI trả lời đúng dựa trên số liệu chi tiêu thật của tháng hiện tại, không lỗi/crash màn hình do tham chiếu field đã xóa.
