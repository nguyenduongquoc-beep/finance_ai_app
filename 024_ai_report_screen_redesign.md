# TICKET 024 — Redesign màn Báo cáo AI (`AiReportScreen`) theo thiết kế Figma mới

**Loại:** UI/UX redesign + bổ sung logic tính toán (Dart thuần, không đổi kiến trúc AI)
**Độ ưu tiên:** Trung bình
**File bị ảnh hưởng:** `lib/screens/ai/ai_report_screen.dart`
**File mới (tùy chọn, khuyến nghị):** `lib/widgets/spending_trend_bar_chart.dart`

---

## 1. Context (Bối cảnh)

Màn `AiReportScreen` hiện tại (`ListView` gồm 4 `_reportRow` dạng `Card`/`ListTile` + 1 card khuyến nghị tĩnh) cần được thiết kế lại hoàn toàn theo ảnh Figma đính kèm (`screen-ai-report.png`). Thiết kế mới gồm:

1. **AppBar**: nút back + tiêu đề "Báo cáo AI" + 1 icon action tròn nền mint (icon biểu đồ) ở góc phải.
2. **Hero card nền tối** (navy/charcoal, bo góc lớn):
   - Dòng "BÁO CÁO THÁNG {N}" (mint, in hoa, bold) + badge "AI Generated" (nền mint nhạt, chữ xanh đậm) ở góc phải.
   - "Tổng chi tiêu của bạn" (chữ xám) + số tiền lớn màu trắng.
   - `Divider` mờ.
   - 2 cột: **Tiết kiệm** (giá trị xanh lá) | **So với tháng trước** (% thay đổi, màu cam nếu tăng chi tiêu, xanh nếu giảm).
3. **Card "Cơ cấu chi tiêu"**: donut chart chi tiêu theo danh mục tháng hiện tại, tâm donut hiện label "Tháng {N}", bên phải là legend (chấm màu + tên danh mục + % + số tiền dạng rút gọn "VNĐ X,XXXK").
4. **Card "Xu hướng chi tiêu 3 tháng"**: 3 cột biểu đồ (3 tháng gần nhất), mỗi cột hiện giá trị rút gọn (vd "12.4M") phía trên, cột tháng hiện tại tô màu xanh lá đậm nổi bật, 2 cột còn lại tô màu xám nhạt.
5. **Card "💡 Đánh giá quan trọng từ AI"**: danh sách 2-3 dòng, mỗi dòng gồm icon tròn (mặt cười xanh = tích cực, tam giác cảnh báo cam = cảnh báo, dấu tick xanh = hoàn thành mục tiêu) + tiêu đề bold + mô tả ngắn màu xám.
6. **2 nút cuối trang**: "Chia sẻ báo cáo" (outlined, icon share) + "Xuất file PDF" (filled xanh lá, icon download) — nằm ngang hàng, chia đều 2 nửa.

**Nguyên tắc bắt buộc (theo `context/RULES.md` mục 7):** mọi số liệu hiển thị (tổng chi tiêu, % thay đổi, % cơ cấu, insight) đều phải được **tính bằng Dart thuần** từ dữ liệu Firestore thật — **không** để Gemini tự bịa số hay tự viết nội dung "Đánh giá quan trọng từ AI". Card AI Report này **không gọi Gemini** — toàn bộ nội dung là suy luận từ ngưỡng/số liệu có sẵn, đúng tinh thần đã áp dụng ở `FinancialAnalyticsService`/`AiInsightScreen`.

## 2. Fix Requirements

### 2.1. Chuyển `AiReportScreen` sang `StatefulWidget`

Cần fetch thêm dữ liệu tháng trước + 2 tháng trước nữa (cho biểu đồ xu hướng 3 tháng) và tính toán insight — không còn gọn trong 1 `StatelessWidget` với `StreamBuilder` lồng đơn giản như hiện tại. Giữ nguyên cách lấy dữ liệu qua `FirestoreService` (`streamTransactions`, `streamCategories`, `streamBudgets`, `streamSavingGoals`) — dùng `.first` để lấy 1 lần (giống pattern đã dùng trong `ai_insight_screen.dart` và `ai_chat_screen.dart._buildFinancialContext()`), load trong `initState()`.

### 2.2. Tính toán dữ liệu (Dart thuần)

Trong hàm `_loadReportData()`:

```dart
final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
final now = DateTime.now();
final monthStart = DateTime(now.year, now.month, 1);
final lastMonthStart = DateTime(now.year, now.month - 1, 1);
final lastMonthEnd = DateTime(now.year, now.month, 0, 23, 59, 59);
final twoMonthsAgoStart = DateTime(now.year, now.month - 2, 1);
final twoMonthsAgoEnd = DateTime(now.year, now.month - 1, 0, 23, 59, 59);

final currentTx = await firestoreService.streamTransactions(uid, from: monthStart).first;
final lastMonthTx = await firestoreService
    .streamTransactions(uid, from: lastMonthStart, to: lastMonthEnd).first;
final twoMonthsAgoTx = await firestoreService
    .streamTransactions(uid, from: twoMonthsAgoStart, to: twoMonthsAgoEnd).first;
final categories = await firestoreService.streamCategories(uid).first;
final budgets = await firestoreService
    .streamBudgets(uid, month: AppFormatters.month(now)).first;
final savingGoals = await firestoreService.streamSavingGoals(uid).first;
```

Từ đó tính:
- `totalExpense` = tổng `amount` các giao dịch `expense` tháng này.
- `totalIncome`, `savings` = `totalIncome - totalExpense` (giữ đúng công thức cũ).
- `lastMonthExpense` = tổng expense tháng trước.
- `percentChange` = `lastMonthExpense == 0 ? null : ((totalExpense - lastMonthExpense) / lastMonthExpense) * 100`.
  - Hiển thị **"Tăng X%"** màu `AppColors.warning` nếu `percentChange > 0` (chi tiêu tăng — xấu).
  - Hiển thị **"Giảm X%"** màu `AppColors.income` nếu `percentChange < 0` (chi tiêu giảm — tốt).
  - Nếu `lastMonthExpense == 0` (không có dữ liệu so sánh) → ẩn cột này hoặc hiện "Chưa có dữ liệu".
- `categoryTotals` (tháng này) và `lastMonthCategoryTotals` (tháng trước) — gom theo `categoryId`, dùng lại đúng pattern `_sumByCategory` đã có trong `FinancialAnalyticsService`.
- 3 tháng gần nhất cho biểu đồ xu hướng: `[twoMonthsAgoExpense, lastMonthExpense, totalExpense]` (đơn vị: giữ nguyên VNĐ, chỉ format hiển thị rút gọn ở widget).

### 2.3. Card hero (nền tối)

```dart
Container(
  width: double.infinity,
  padding: const EdgeInsets.all(20),
  decoration: BoxDecoration(
    color: const Color(0xFF16283A), // navy tối, có thể thêm AppColors.reportDark nếu muốn chuẩn hóa
    borderRadius: BorderRadius.circular(20),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('BÁO CÁO THÁNG ${now.month}',
              style: const TextStyle(color: AppColors.accentGreen, fontWeight: FontWeight.bold,
                  fontSize: 12, letterSpacing: 0.5)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accentGreen.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('AI Generated',
                style: TextStyle(color: AppColors.accentGreen, fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      const SizedBox(height: 16),
      const Text('Tổng chi tiêu của bạn', style: TextStyle(color: Colors.white60, fontSize: 13)),
      const SizedBox(height: 4),
      Text(AppFormatters.currency(totalExpense),
          style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      const Divider(color: Colors.white24, height: 1),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tiết kiệm', style: TextStyle(color: Colors.white60, fontSize: 12)),
                const SizedBox(height: 4),
                Text(AppFormatters.currency(savings),
                    style: const TextStyle(color: AppColors.accentGreen, fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('So với tháng trước', style: TextStyle(color: Colors.white60, fontSize: 12)),
                const SizedBox(height: 4),
                if (percentChange != null)
                  Text(
                    '${percentChange > 0 ? 'Tăng' : 'Giảm'} ${percentChange.abs().toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: percentChange > 0 ? AppColors.warning : AppColors.accentGreen,
                      fontWeight: FontWeight.bold, fontSize: 15,
                    ),
                  )
                else
                  const Text('Chưa có dữ liệu', style: TextStyle(color: Colors.white60, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    ],
  ),
)
```

### 2.4. Card "Cơ cấu chi tiêu" — tái sử dụng `CategoryPieChart`

Widget `CategoryPieChart` trong `lib/widgets/dashboard_chart.dart` đã có sẵn donut chart + legend đúng bố cục (chấm màu, tên, %). Cần:
1. Thêm tham số optional `String? centerLabel` vào `CategoryPieChart` — nếu có, hiện `centerLabel` (VD `"Tháng 10"`) ở tâm donut **thay cho** "Tổng/100%" mặc định; nếu không truyền, giữ hành vi cũ (không phá vỡ chỗ gọi ở `home_dashboard_screen.dart`).
2. Thêm tham số optional format cho subtitle legend (hiện đang chỉ có %, cần thêm dòng phụ "VNĐ X,XXXK" bên dưới hoặc bên cạnh %) — hoặc đơn giản hơn: bọc `CategoryPieChart` trong `AiReportScreen` bằng 1 `Column` riêng, tự vẽ legend list (không sửa widget dùng chung) để tránh ảnh hưởng Dashboard. **Khuyến nghị chọn cách này** để giữ `dashboard_chart.dart` không đổi, tránh rủi ro regression ở Dashboard.

Format số tiền rút gọn "K" (nghìn): viết hàm helper cục bộ trong `AiReportScreen`:
```dart
String _formatCompact(double amount) {
  if (amount >= 1000000) return '${(amount / 1000000).toStringAsFixed(1)}Tr';
  if (amount >= 1000) return '${(amount / 1000).round()}K';
  return amount.round().toString();
}
```

### 2.5. Card "Xu hướng chi tiêu 3 tháng" — widget mới `SpendingTrendBarChart`

Tạo `lib/widgets/spending_trend_bar_chart.dart`, nhận `List<double> amounts` (đúng 3 phần tử, cũ→mới) + `List<String> monthLabels` (VD `['Tháng 8', 'Tháng 9', 'Tháng 10']`):

```dart
import 'package:flutter/material.dart';
import '../utils/constants.dart';

class SpendingTrendBarChart extends StatelessWidget {
  final List<double> amounts; // 3 tháng, cũ -> mới
  final List<String> monthLabels;

  const SpendingTrendBarChart({super.key, required this.amounts, required this.monthLabels});

  String _compact(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).round()}K';
    return v.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    final maxVal = amounts.isEmpty ? 1.0 : amounts.reduce((a, b) => a > b ? a : b);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(amounts.length, (i) {
        final isCurrent = i == amounts.length - 1;
        final heightFactor = maxVal == 0 ? 0.1 : (amounts[i] / maxVal).clamp(0.1, 1.0);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_compact(amounts[i]),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: isCurrent ? AppColors.textPrimary : AppColors.textSecondary)),
            const SizedBox(height: 6),
            Container(
              width: 48,
              height: 90 * heightFactor,
              decoration: BoxDecoration(
                color: isCurrent ? AppColors.accentGreen : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 8),
            Text(monthLabels[i],
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        );
      }),
    );
  }
}
```

### 2.6. Card "Đánh giá quan trọng từ AI" — logic phát hiện (Dart thuần, KHÔNG gọi Gemini)

Sinh tối đa 3 insight theo thứ tự ưu tiên, mỗi insight có `title`, `description`, `type` (`positive` | `warning` | `success`):

1. **Cảnh báo ngân sách** (`warning`, icon tam giác cam): với mỗi `Budget` trong `budgets` (tháng này) có `isOverBudget == true` hoặc `isNearLimit == true` → tạo 1 insight:
   - `title`: `'Cảnh giác ${categoryName}'`
   - `description`: `'Đã chi ${AppFormatters.currency(budget.spent)}/${AppFormatters.currency(budget.limit)} ngân sách'`
   (Lấy `categoryName` từ `categories` theo `budget.categoryId`, fallback `'Danh mục'`.)

2. **Danh mục giảm chi tiêu mạnh** (`positive`, icon mặt cười xanh): so `categoryTotals` (tháng này) với `lastMonthCategoryTotals`, tìm danh mục có `(last - current) / last >= 0.10` (giảm ≥10%) và giá trị `last > 0`, lấy danh mục giảm mạnh nhất:
   - `title`: `'Mua sắm thông minh'` nếu category là loại mua sắm/tiêu dùng, hoặc tổng quát `'${categoryName} tiết kiệm hơn'`
   - `description`: `'Chi tiêu ${categoryName} giảm ${percent.round()}% so với tháng trước'`

3. **Hoàn thành mục tiêu tiết kiệm** (`success`, icon dấu tick xanh): nếu có `SavingGoal` trong `savingGoals` với `percentComplete >= 1.0` → 1 insight:
   - `title`: `'Tích lũy đều đặn'`
   - `description`: `'Hoàn thành 100% mục tiêu tiết kiệm "${goal.name}"'`
   Nếu không có mục tiêu nào hoàn thành nhưng có mục tiêu đang tiến triển tốt (`percentComplete >= 0.5`), có thể thay bằng: `'Đã đạt ${(percentComplete*100).round()}% mục tiêu "${goal.name}"'`.

Nếu không có insight nào được sinh ra (dữ liệu quá ít / mọi thứ trong ngưỡng an toàn) → hiện 1 dòng duy nhất: `'Chưa có đánh giá nổi bật nào cho tháng này.'`

Mỗi item hiển thị dạng:
```dart
Row(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    CircleAvatar(
      radius: 14,
      backgroundColor: iconColor.withOpacity(0.15),
      child: Icon(iconData, color: iconColor, size: 16),
    ),
    const SizedBox(width: 10),
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(insight.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 2),
          Text(insight.description, style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4)),
        ],
      ),
    ),
  ],
)
```
`iconData`/`iconColor` theo `type`: `positive` → `Icons.sentiment_satisfied_alt`, `AppColors.income`; `warning` → `Icons.warning_amber_rounded`, `AppColors.warning`; `success` → `Icons.check_circle`, `AppColors.income`.

### 2.7. 2 nút cuối trang

```dart
Row(
  children: [
    Expanded(
      child: OutlinedButton.icon(
        onPressed: () {
          // TODO: tích hợp package share_plus nếu cần chia sẻ thật;
          // trước mắt có thể để trống/gọi AppSnackbar báo "Tính năng đang phát triển"
          AppSnackbar.show(context, 'Tính năng chia sẻ đang được phát triển');
        },
        icon: const Icon(Icons.ios_share_rounded, size: 18),
        label: const Text('Chia sẻ báo cáo'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: BorderSide(color: Colors.grey.shade300),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ),
    const SizedBox(width: 12),
    Expanded(
      child: ElevatedButton.icon(
        onPressed: () {
          // Giữ nguyên hành vi TODO PDF đã có sẵn trong code cũ
          AppSnackbar.show(context, 'TODO: Xuất PDF - dùng package pdf/printing');
        },
        icon: const Icon(Icons.download_rounded, size: 18),
        label: const Text('Xuất file PDF'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentGreen,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
      ),
    ),
  ],
)
```
Giữ nguyên đúng hành vi TODO cũ của nút xuất PDF (đã có trong `AiReportScreen` hiện tại, chỉ đổi vị trí/style từ icon trên AppBar sang nút cuối trang) — **xóa** icon PDF cũ trên AppBar vì đã chuyển xuống nút mới, tránh trùng 2 chỗ cùng chức năng.

### 2.8. Icon action trên AppBar

Icon tròn nền mint bên phải AppBar (theo ảnh) — gợi ý dùng `Icons.bar_chart_rounded`, `onPressed` có thể điều hướng sang `AiInsightScreen` (đã có, cùng nhóm phân tích tài chính) hoặc để trống làm placeholder với `AppSnackbar`. Không bắt buộc phải có hành vi phức tạp, ưu tiên đúng UI trước.

### 2.9. Bọc Dark Mode

Áp dụng đúng pattern đã dùng trong toàn bộ dự án (`021_dark_mode_sync_fix.md`): bọc `build()` bằng `ValueListenableBuilder<ThemeMode>` để đảm bảo màn tự rebuild khi đổi Dark Mode. Riêng **card hero nền tối giữ nguyên màu cố định** (không đổi theo dark mode, vì thiết kế gốc đã tối sẵn) — 3 card còn lại (Cơ cấu chi tiêu, Xu hướng, Đánh giá AI) dùng `AppColors.card`/`AppColors.textPrimary`/`AppColors.textSecondary` (động) như quy ước.

## 3. Không đổi (Out of scope)

- Không đổi cách gọi Firestore hiện có (`streamTransactions`, `streamCategories`, `streamBudgets`, `streamSavingGoals`) — chỉ gọi thêm với khoảng thời gian khác.
- Không thêm tính năng chia sẻ/xuất PDF thật trong ticket này — giữ nguyên dạng placeholder/TODO như code gốc, chỉ đổi vị trí hiển thị nút.
- Không đổi `CategoryPieChart`/`dashboard_chart.dart` nếu chọn hướng tự vẽ legend riêng (mục 2.4) — tránh rủi ro ảnh hưởng Dashboard.
- Không gọi Gemini (`AiService`) ở màn này — toàn bộ nội dung "Đánh giá quan trọng từ AI" là suy luận ngưỡng bằng Dart, đúng tinh thần `RULES.md` mục 7.

## 4. Acceptance Criteria

- [ ] Card hero hiện đúng tháng hiện tại, tổng chi tiêu, tiết kiệm, và % so với tháng trước với màu đúng (cam khi tăng, xanh khi giảm), không lỗi chia 0 khi tháng trước không có dữ liệu.
- [ ] Donut "Cơ cấu chi tiêu" hiện đúng tỷ lệ % và số tiền rút gọn theo danh mục chi tiêu tháng hiện tại; tháng không có chi tiêu → hiện thông báo rõ ràng, không donut rỗng gây lỗi.
- [ ] Biểu đồ "Xu hướng chi tiêu 3 tháng" hiện đúng 3 cột tương ứng 3 tháng gần nhất, cột tháng hiện tại được tô nổi bật.
- [ ] "Đánh giá quan trọng từ AI" hiện đúng tối đa 3 insight theo logic ngưỡng đã định nghĩa, có số liệu cụ thể trong mô tả (không phải text tĩnh bịa sẵn); tháng không có gì nổi bật → hiện đúng thông báo mặc định.
- [ ] 2 nút "Chia sẻ báo cáo"/"Xuất file PDF" hiển thị đúng theo thiết kế, bấm vào không crash (dù chỉ là placeholder).
- [ ] Test dark mode: 3 card trắng đổi màu đúng theo dark mode, card hero giữ nguyên nền tối cố định.
- [ ] `flutter analyze` không phát sinh lỗi/warning mới.
- [ ] Test với ít nhất 2 tài khoản: 1 tài khoản có đủ dữ liệu 3 tháng + ngân sách + mục tiêu tiết kiệm (để thấy đủ 3 loại insight), 1 tài khoản mới/ít dữ liệu (để xác nhận không crash, hiện đúng fallback).
