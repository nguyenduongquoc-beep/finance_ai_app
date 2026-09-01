# TICKET 013 — Redesign màn Home Dashboard theo Figma mới + Biểu đồ cột tương tác với Donut chart theo tháng (gộp ticket 006 phần A)

**Loại:** UI/UX redesign + Feature (biểu đồ tương tác)
**Độ ưu tiên:** Cao
**File bị ảnh hưởng:** `lib/screens/home/home_dashboard_screen.dart`, `lib/widgets/dashboard_chart.dart`

---

## 1. Context (Bối cảnh)

Đang áp dụng lại giao diện Home Dashboard theo thiết kế Figma mới (dark/theme mới đã thiết kế riêng). Ngoài việc đổi UI, gộp chung 2 thay đổi về logic đã được xác nhận:

1. **Đổi ý nghĩa thẻ số dư đầu trang**: từ "Số dư tháng này" (hiện tính bằng `income - expense` của tháng hiện tại, đã được ghi nhận là chưa hợp lý ở `008_consolidated_feedback_round.md` vấn đề 5) → đổi thành **"Tổng số dư"**, là tổng `balance` của **tất cả ví cộng lại**, đúng ý nghĩa "tổng tài sản hiện có" phục vụ nhìn tổng thể tình hình tài chính.
2. **Biểu đồ cột Thu/Chi 6 tháng trở nên tương tác được** (đây chính là ticket 006 phần A đã đề xuất trước đó, nay gộp thực hiện luôn cùng đợt redesign): người dùng chạm vào cột của tháng bất kỳ → biểu đồ Donut "Top danh mục chi tiêu" bên dưới **cập nhật động** theo đúng tháng vừa chạm, thay vì luôn cố định hiển thị tháng hiện tại như code hiện tại.

Thu nhập tháng hiện tại và Chi tiêu tháng hiện tại (2 chip thống kê) **giữ nguyên không đổi ý nghĩa**, chỉ đổi theo style UI mới.

## 2. Fix Requirements

### 2.1. Đổi "Số dư tháng này" → "Tổng số dư"

Trong `home_dashboard_screen.dart`, thêm 1 tầng `StreamBuilder<List<Wallet>>` (dùng `firestoreService.streamWallets(uid)` đã có sẵn, không cần thêm hàm mới) để lấy tổng số dư thật:

```dart
StreamBuilder<List<Wallet>>(
  stream: firestoreService.streamWallets(uid),
  builder: (context, walletSnap) {
    final wallets = walletSnap.data ?? [];
    final totalBalance = wallets.fold<double>(0, (a, w) => a + w.balance);
    // Dùng totalBalance thay cho biến `balance` (income - expense) hiện tại
    // khi build phần header
    ...
  },
)
```

- Đổi label hiển thị từ `'Số dư tháng này'` → `'Tổng số dư'`.
- **Xóa** biến `balance = income - expense` hiện đang dùng cho mục đích này (không còn cần thiết cho phần header — 2 chip "Thu tháng này"/"Chi tiêu tháng này" vẫn tính riêng như cũ, không phụ thuộc biến này).
- Cần thêm `import '../../models/wallet_model.dart';` nếu file chưa import.

### 2.2. Biểu đồ cột tương tác — chạm vào cột để đổi tháng cho Donut chart

**a) `lib/widgets/dashboard_chart.dart` — `IncomeExpenseBarChart`:**

Thêm tham số mới vào constructor:
```dart
class IncomeExpenseBarChart extends StatelessWidget {
  final List<double> incomeByMonth;
  final List<double> expenseByMonth;
  final List<String> monthLabels;
  final int selectedIndex;                    // MỚI — tháng đang được chọn
  final void Function(int monthIndex) onMonthTap; // MỚI — callback khi chạm cột

  const IncomeExpenseBarChart({
    super.key,
    required this.incomeByMonth,
    required this.expenseByMonth,
    required this.monthLabels,
    required this.selectedIndex,
    required this.onMonthTap,
  });
  ...
}
```

Thêm `barTouchData` để bắt sự kiện chạm:
```dart
BarChartData(
  barTouchData: BarTouchData(
    touchTooltipData: BarTouchTooltipData(
      getTooltipItem: (group, groupIndex, rod, rodIndex) {
        // Hiện rõ số tiền chính xác (không làm tròn về triệu) khi chạm
        final isIncome = rodIndex == 0;
        final rawValue = (isIncome ? incomeByMonth : expenseByMonth)[groupIndex] * 1e6;
        return BarTooltipItem(
          AppFormatters.currency(rawValue),
          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
        );
      },
    ),
    touchCallback: (event, response) {
      if (event is FlTapUpEvent && response?.spot != null) {
        onMonthTap(response!.spot!.touchedBarGroupIndex);
      }
    },
  ),
  ...
)
```

- Cột của `selectedIndex` cần có **viền/hiệu ứng nổi bật** (VD viền sáng hoặc opacity cao hơn các cột khác) để người dùng biết đang xem tháng nào — style theo đúng thiết kế Figma.
- Cần `import '../utils/formatters.dart';` vào file này nếu chưa có (để dùng `AppFormatters.currency`).

**b) `home_dashboard_screen.dart` — quản lý state tháng được chọn:**

Đổi `HomeDashboardScreen` từ `StatelessWidget` sang `StatefulWidget` (bắt buộc, vì cần lưu `_selectedMonthIndex`):
```dart
class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});
  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  int _selectedMonthIndex = 5; // mặc định = tháng cuối cùng (tháng hiện tại) trong mảng 6 tháng
  ...
}
```

- Khi build `IncomeExpenseBarChart`, truyền `selectedIndex: _selectedMonthIndex` và `onMonthTap: (i) => setState(() => _selectedMonthIndex = i)`.
- Hàm `_buildCategoryPie()` hiện đang **hardcode lọc theo `monthTx`** (giao dịch tháng hiện tại) — sửa để nhận tham số `List<AppTransaction> transactions` là giao dịch của **đúng tháng đang được chọn** (tính từ `allTx` đã fetch sẵn, lọc theo khoảng `[selectedMonthStart, selectedMonthEnd)`, hoàn toàn tính toán phía client, KHÔNG query Firestore thêm).
- Thêm dòng tiêu đề động ngay trên Donut, VD: `'Top danh mục chi tiêu — Tháng ${selectedMonth.month}/${selectedMonth.year}'`, để rõ ràng đang xem đúng tháng nào (đặc biệt quan trọng khi tháng được chọn khác tháng hiện tại).
- Tháng không có dữ liệu chi tiêu → giữ nguyên xử lý hiện có (hiện text "Chưa có dữ liệu chi tiêu tháng này"), không lỗi chia 0.

### 2.3. Bộ lọc nửa năm (mở rộng xem quá khứ, vẫn cố định khối 6 tháng)

Theo yêu cầu: biểu đồ tối đa hiển thị 6 tháng/lần, chia cố định theo 2 khối: **Tháng 1 → Tháng 6** và **Tháng 7 → Tháng 12** của 1 năm bất kỳ (không dùng date-range picker tự do).

- Thêm 1 hàng chọn phía trên biểu đồ: 1 `DropdownButton<int>` chọn **năm** (danh sách năm từ `DateTime.now().year - 4` tới `DateTime.now().year`, đủ dùng cho phạm vi hợp lý) + 1 `ToggleButtons`/`SegmentedButton` 2 lựa chọn **"Th1–Th6"** / **"Th7–Th12"**.
- **Mặc định khi mở màn hình**: tự động chọn đúng năm hiện tại + đúng nửa năm chứa tháng hiện tại (VD nếu hôm nay là tháng 8 → mặc định chọn "Th7–Th12" của năm hiện tại).
- Khi đổi lựa chọn (năm hoặc nửa năm) → tính lại khoảng `from`/`to` tương ứng (VD "Th1–Th6/2026" → `from: DateTime(2026,1,1)`, `to: DateTime(2026,6,30,23,59,59)`), gọi lại `firestoreService.streamTransactions(uid, from: ..., to: ...)` để lấy đúng dữ liệu — thay cho cách tính `sixMonthsAgo` tương đối hiện tại (chỉ áp dụng đúng cho "6 tháng gần nhất tính tới hôm nay", giờ cần tổng quát hóa theo lựa chọn của người dùng).
- Sau khi đổi bộ lọc, `_selectedMonthIndex` (cho Donut) reset về tháng cuối cùng của khối 6 tháng đang xem (hoặc tháng gần hiện tại nhất nếu khối đó chứa cả tháng tương lai — không cho chọn tháng tương lai chưa có dữ liệu).
- `monthLabels` cần hiện rõ **cả năm** khi người dùng đang xem năm khác năm hiện tại (VD "Th1/25" thay vì chỉ "Th1"), tránh nhầm lẫn.

### 2.4. Áp dụng theme/UI theo Figma

- Đổi toàn bộ màu sắc, spacing, typography của các thành phần trong Dashboard theo đúng thiết kế Figma (dark theme, thẻ Tổng số dư, card giao dịch, card AI Insight...).
- Vẫn tuân thủ `RULES.md` mục 3: **không hardcode `Color(0xFF...)`** — nếu bảng màu `AppColors` trong `constants.dart` đã được cập nhật theo theme mới ở 1 ticket khác trước đó, dùng lại đúng token đó; nếu chưa, chỉ dùng token tạm với comment `// TODO: chuẩn hóa theo AppColors khi có bảng màu chính thức`.

## 3. Không đổi (Out of scope)

- Không đổi cách tính "Thu tháng này"/"Chi tháng này" (2 chip) — vẫn giữ nguyên logic hiện tại, chỉ đổi style.
- Không đổi `firestoreService.streamTransactions()` — hàm đã hỗ trợ sẵn `from`/`to`, không cần sửa signature.
- Không thêm animation phức tạp ngoài hiệu ứng chọn cột (highlight) đã nêu.
- Không đổi phần "Giao dịch gần đây" và card "AI Phân tích chi tiêu" về mặt logic — chỉ đổi UI theo Figma.
- Không cho chọn khoảng ngày tự do (date range picker) — chỉ 2 khối cố định Th1–Th6/Th7–Th12 như yêu cầu.

## 4. Acceptance Criteria

- [ ] Thẻ đầu trang hiện đúng **"Tổng số dư"** = tổng `balance` tất cả ví, cập nhật đúng ngay khi có giao dịch mới hoặc đổi số dư ví thủ công.
- [ ] Mặc định mở Dashboard → biểu đồ hiện đúng 6 tháng gần nhất (khối chứa tháng hiện tại), Donut hiện đúng dữ liệu tháng hiện tại, cột tháng hiện tại được highlight.
- [ ] Chạm vào cột tháng bất kỳ (không phải tháng hiện tại) → Donut cập nhật ngay đúng dữ liệu chi tiêu của tháng đó, tiêu đề phía trên Donut đổi đúng theo tháng/năm đã chọn, cột vừa chạm được highlight thay cột cũ.
- [ ] Chạm giữ/tap vào cột → hiện tooltip số tiền chính xác (VNĐ, không làm tròn) của đúng cột thu hoặc chi vừa chạm.
- [ ] Đổi bộ lọc năm/nửa năm → biểu đồ tải lại đúng đúng 6 tháng của khối đã chọn, Donut reset về tháng phù hợp, không lỗi khi khối đó có tháng chưa có giao dịch.
- [ ] Tháng được chọn (bất kỳ, kể cả quá khứ) không có giao dịch chi tiêu → Donut hiện "Chưa có dữ liệu chi tiêu tháng này", không crash/chia 0.
- [ ] Giao diện tổng thể (màu sắc, spacing, thẻ, card) khớp đúng thiết kế Figma đã cung cấp.
- [ ] Test tối thiểu: mở Dashboard lần đầu, chạm 2-3 cột khác nhau, đổi bộ lọc sang năm/nửa năm khác rồi chạm tiếp — xác nhận Donut luôn đúng theo tháng đang chọn, không bị lệch dữ liệu tháng cũ.
