# TICKET 009 — Batch fix: Onboarding hint, đổi tên bộ lọc lịch sử, sửa biểu đồ AI Insight, nạp tiền mục tiêu trừ ví, cải tiến dialog ngân sách

**Loại:** Bug fix + Feature (5 phần độc lập, xử lý theo đúng thứ tự đánh số)
**File bị ảnh hưởng:** liệt kê riêng trong từng phần

---

## PHẦN A — Vấn đề 1: Thêm hướng dẫn ở bước Onboarding (Hướng B)

**File:** `lib/screens/setup/wallet_setup_screen.dart`, `lib/screens/setup/category_setup_screen.dart`

### Fix Requirements
Thêm 1 dòng text hướng dẫn ngay dưới phần mô tả hiện có ở mỗi màn, **không đổi logic chọn mặc định**.

Trong `wallet_setup_screen.dart`, sau dòng:
```dart
const Text('Chọn các ví bạn muốn sử dụng và nhập số dư hiện tại',
    style: TextStyle(color: AppColors.textSecondary)),
```
Thêm:
```dart
const SizedBox(height: 4),
const Text('💡 Bạn có thể bỏ chọn các ví không cần thiết — vẫn có thể thêm/sửa lại sau ở mục Quản lý ví.',
    style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontStyle: FontStyle.italic)),
```

Trong `category_setup_screen.dart`, sau dòng:
```dart
const Text('Chọn danh mục thu/chi phù hợp với bạn (có thể chỉnh sửa sau)',
    style: TextStyle(color: AppColors.textSecondary)),
```
Thêm:
```dart
const SizedBox(height: 4),
const Text('💡 Danh mục đang được chọn sẵn hết — bỏ chọn bớt nếu bạn không dùng tới, hoặc thêm mới sau ở mục Quản lý danh mục.',
    style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontStyle: FontStyle.italic)),
```

### Acceptance Criteria
- [ ] 2 màn setup hiện đúng dòng hint mới, không phá layout hiện có.

---

## PHẦN B — Vấn đề 4: Đổi tên bộ lọc lịch sử giao dịch (Hướng B)

**File:** `lib/screens/home/transaction_list_screen.dart`

### Fix Requirements

1. Đổi nhãn 3 nút lọc cho rõ nghĩa "khoảng ngắn hạn":
```dart
_filterChip('Hôm nay', _FilterRange.day),
_filterChip('7 ngày qua', _FilterRange.week),
_filterChip('Tháng này', _FilterRange.month),
```
(Đổi text hiển thị trong `_filterChip()`, không đổi enum `_FilterRange` hay logic `_fromDate`.)

2. Thêm 1 action trên AppBar để xem toàn bộ lịch sử (không giới hạn thời gian):
```dart
appBar: AppBar(
  title: const Text('Giao dịch'),
  actions: [
    IconButton(
      icon: const Icon(Icons.history),
      tooltip: 'Xem toàn bộ lịch sử',
      onPressed: () {
        setState(() => _showAllHistory = !_showAllHistory);
      },
    ),
  ],
  bottom: ...
),
```
Thêm field mới `bool _showAllHistory = false;`. Khi `true`, bỏ qua `from:` trong query:
```dart
stream: _showAllHistory
    ? _firestoreService.streamTransactions(uid) // không truyền from → lấy toàn bộ
    : _firestoreService.streamTransactions(uid, from: _fromDate),
```
Khi `_showAllHistory == true`, đổi `_groupByDay()` thành nhóm theo **tháng** thay vì theo ngày (dùng `AppFormatters.month(tx.date)` làm key thay vì `AppFormatters.date(tx.date)`), và ẩn 3 nút lọc Ngày/Tuần/Tháng đi (vì không còn ý nghĩa khi đang xem toàn bộ).

### Acceptance Criteria
- [ ] 3 nút lọc hiện đúng tên mới, hành vi lọc không đổi.
- [ ] Bấm icon lịch sử → hiện toàn bộ giao dịch mọi thời điểm, nhóm theo tháng, mới nhất lên đầu.
- [ ] Bấm lại icon đó → quay về chế độ lọc theo Ngày/Tuần/Tháng như cũ.

---

## PHẦN C — Vấn đề 6: Sửa biểu đồ AI Insight bị lệch/xấu

**File:** `lib/widgets/trend_chart_card.dart`

### Root Cause
`titlesData` chỉ cấu hình `leftTitles`/`bottomTitles`, bỏ sót `topTitles`/`rightTitles` — 2 trục này mặc định **hiện số thô** (không tắt), gây chồng chéo 2 trục X và 2 trục Y như trong ảnh. Ngoài ra `reservedSize: 40` quá hẹp cho label dạng "198.8K" khiến chữ bị vỡ dòng.

### Fix Requirements

```dart
titlesData: FlTitlesData(
  show: true,
  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
  leftTitles: AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: 52, // tăng từ 40 lên 52 để đủ chỗ cho label dài
      interval: _calcYInterval(),
      getTitlesWidget: (value, meta) {
        // Format gọn: làm tròn về K (nghìn) hoặc Tr (triệu), không hiện số thập phân lẻ
        String label;
        if (value >= 1000000) {
          label = '${(value / 1000000).toStringAsFixed(1)}Tr';
        } else if (value >= 1000) {
          label = '${(value / 1000).round()}K';
        } else {
          label = value.round().toString();
        }
        return Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
        );
      },
    ),
  ),
  bottomTitles: AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      interval: 1,
      getTitlesWidget: (value, meta) {
        if (value != value.toInt()) return const SizedBox();
        final index = value.toInt();
        if (index < 0 || index >= trendResult.monthlyAmounts.length) return const SizedBox();
        final now = DateTime.now();
        final month = DateTime(now.year, now.month - (trendResult.monthlyAmounts.length - 1 - index), 1);
        return Text('Th${month.month}', style: const TextStyle(fontSize: 10, color: Colors.black54));
      },
    ),
  ),
),
```

**Thay đổi chính:** thêm 2 dòng `topTitles`/`rightTitles` tắt hẳn (giống cách `dashboard_chart.dart` đã làm đúng), tăng `reservedSize`, và thêm `getTitlesWidget` tùy chỉnh cho `leftTitles` để label gọn gàng, nhất quán định dạng (K/Tr), không còn số thập phân lẻ khó đọc.

### Acceptance Criteria
- [ ] Biểu đồ chỉ còn đúng 1 trục X (tên tháng Th3-Th8) và 1 trục Y (giá trị tiền dạng K/Tr gọn gàng), không còn số 0-5 hay trục phải dư thừa.
- [ ] Label trục Y không bị vỡ dòng/chồng chữ ở bất kỳ khoảng giá trị nào (test với dữ liệu nhỏ và dữ liệu triệu đồng).

---

## PHẦN D — Vấn đề 7: Nạp tiền mục tiêu tiết kiệm phải trừ ví

**File:** `lib/screens/management/saving_goal_screen.dart`, `lib/services/firestore_service.dart`

### Fix Requirements

**1. Sửa `_addDeposit()` trong `_GoalCardState`** — thêm chọn ví, validate số dư, trừ ví khi xác nhận:
```dart
Future<void> _addDeposit() async {
  final amountController = TextEditingController();
  String? selectedWalletId;
  final wallets = await widget.firestoreService.streamWallets(
    FirebaseAuth.instance.currentUser?.uid ?? '',
  ).first;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Nạp tiền vào "${widget.goal.name}"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: selectedWalletId,
              decoration: const InputDecoration(labelText: 'Nạp từ ví', prefixIcon: Icon(Icons.account_balance_wallet_outlined)),
              items: wallets.map((w) => DropdownMenuItem(
                value: w.walletId,
                child: Text('${w.walletName} (${AppFormatters.currency(w.balance)})'),
              )).toList(),
              onChanged: (v) => setDialogState(() => selectedWalletId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Số tiền nạp (đ)',
                prefixIcon: Icon(Icons.add_circle_outline),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Nạp'),
          ),
        ],
      ),
    ),
  );

  if (confirmed == true) {
    final deposit = AppFormatters.parseCurrencyInput(amountController.text);
    if (deposit <= 0 || selectedWalletId == null) return;

    final wallet = wallets.firstWhere((w) => w.walletId == selectedWalletId);
    if (deposit > wallet.balance) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Số tiền vượt quá số dư ví đã chọn')),
        );
      }
      return;
    }

    final newSaved = (widget.goal.savedAmount + deposit).clamp(0, widget.goal.targetAmount);
    await widget.firestoreService.updateSavingGoal(widget.goal.goalId, {'savedAmount': newSaved});
    await widget.firestoreService.adjustWalletBalance(selectedWalletId!, -deposit);
  }
}
```

**2. Không cần thêm hàm mới ở `FirestoreService`** — `adjustWalletBalance()` đã có sẵn, dùng lại trực tiếp.

### Acceptance Criteria
- [ ] Dialog "Nạp tiền" hiện dropdown chọn ví kèm số dư hiện tại của từng ví.
- [ ] Nạp số tiền lớn hơn số dư ví đã chọn → báo lỗi, không cho nạp.
- [ ] Nạp hợp lệ → `savedAmount` của mục tiêu tăng đúng, đồng thời số dư ví đã chọn giảm đúng bằng số tiền nạp.

---

## PHẦN E — Vấn đề 9: Cải tiến dialog Thêm/Sửa ngân sách

**File:** `lib/screens/management/budget_management_screen.dart`

### Lưu ý quan trọng trước khi làm
Code hiện tại **không** set `value:` cho dropdown Danh mục, nên về lý thuyết lỗi crash "value: Instance of Category" trong ảnh bạn gửi **không nên xảy ra** với code này. Khả năng cao ảnh đó chụp từ **trước khi bạn gỡ cài đặt + cài lại app**. Trước khi giao ticket này, hãy test lại 1 lần trên bản build mới nhất — nếu **không** còn crash, phần fix dưới đây vẫn nên làm (vì có lỗi UX thật: chọn xong Danh mục nhưng dropdown không hiện lại đúng lựa chọn).

### Fix Requirements

```dart
if (budget == null)
  StreamBuilder<List<Category>>(
    stream: firestoreService.streamCategories(uid, type: 'expense'),
    builder: (context, snap) {
      if (snap.hasError) return const Text('Lỗi tải danh mục');
      final categories = snap.data ?? [];
      if (categories.isEmpty) {
        return const Text('Chưa có danh mục chi tiêu nào — hãy tạo danh mục trước.',
            style: TextStyle(color: AppColors.textSecondary));
      }
      // Đảm bảo selectedCategory (nếu có) khớp đúng 1 phần tử trong danh sách hiện tại
      final validSelected = categories.any((c) => c.categoryId == selectedCategory?.categoryId)
          ? categories.firstWhere((c) => c.categoryId == selectedCategory!.categoryId)
          : null;
      return DropdownButtonFormField<Category>(
        value: validSelected, // ✅ thêm dòng này — trước đây thiếu, dropdown không hiện lựa chọn
        decoration: const InputDecoration(labelText: 'Danh mục'),
        items: categories
            .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
            .toList(),
        onChanged: (v) => setDialogState(() => selectedCategory = v),
      );
    },
  ),
```

**Giải thích:** thay vì set `value: selectedCategory` trực tiếp (có thể gây đúng lỗi "duplicate/no matching item" nếu `Category` không override `==` khiến mỗi lần Firestore emit lại là instance mới không `==` với instance cũ đã chọn), code tính lại `validSelected` bằng cách tìm đúng object **trong danh sách `categories` hiện tại** theo `categoryId` — đảm bảo luôn khớp identity, tránh chính xác loại lỗi trong ảnh nếu nó có xảy ra thật.

### Acceptance Criteria
- [ ] Test lại crash cũ trên build mới nhất trước — báo lại kết quả.
- [ ] Mở dialog Thêm ngân sách → chọn 1 danh mục → dropdown hiện đúng tên đã chọn (không bị trống lại).
- [ ] Trường hợp chưa có danh mục chi tiêu nào → hiện thông báo rõ ràng thay vì dropdown rỗng gây khó hiểu.
