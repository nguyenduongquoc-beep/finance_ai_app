# TICKET 014 — Tái cấu trúc màn AI Insight: từ "tường thuật bằng chữ" sang "phát hiện vấn đề có căn cứ + AI giải thích theo yêu cầu"

**Loại:** UI/UX redesign + Cải tiến kiến trúc AI Insight (không phải bug fix)
**Độ ưu tiên:** Cao — đây là màn phản hồi trực tiếp nhận xét hội đồng (xem context/PRD.md mục 2.1, context/ARCHITECTURE.md mục 3.4)
**File bị ảnh hưởng:** `lib/models/financial_issue.dart`, `lib/services/financial_analytics_service.dart`, `lib/services/ai_service.dart`, `lib/screens/ai/ai_insight_screen.dart`, thêm mới `lib/widgets/weekly_heatmap_card.dart`

---

## 1. Context (Bối cảnh)

Sau nhận xét hội đồng ("Đừng để AI chỉ là một cái API Gemini được nhúng vào app. Phải biến AI thành phần tạo ra giá trị chính của ứng dụng"), và phản hồi thực tế khi dùng thử: màn `AiInsightScreen` hiện tại **hiện ngay 1 loạt đoạn văn dài** (Phân tích thói quen chi tiêu, Dự đoán chi tiêu cuối tháng, Đề xuất từ AI cho vấn đề...) ngay khi mở màn, gây cảm giác rườm rà, toàn chữ, người dùng phải đọc hết mới nắm được trọng tâm.

Financial Analytics Layer (Dart thuần, `FinancialAnalyticsService`) đã đúng hướng kiến trúc hội đồng yêu cầu — chỉ cần **thay đổi cách trình bày**: ưu tiên hiển thị NGAY dữ liệu đã tính toán sẵn (số liệu, % cụ thể, ngưỡng vi phạm) dưới dạng thẻ gọn — còn phần diễn giải bằng AI (Gemini) chỉ tải **khi người dùng chủ động bấm xem thêm**, không còn hiện sẵn hàng loạt đoạn văn ngay khi mở màn.

Thiết kế Figma mới cho thấy rõ hướng này: các thẻ vấn đề dạng "Chi tiêu đột biến", "Cảnh báo ngân sách"... có kèm % **"Tin cậy"** — con số này PHẢI tính bằng Dart theo công thức xác định (không được để Gemini tự đoán, xem `RULES.md` mục 7).

## 2. Nguyên tắc thiết kế lại (áp dụng xuyên suốt ticket)

1. **Dart tính toán trước, hiển thị ngay, không cần chờ AI** — màn hình mở lên hiện đúng ngay: Điểm sức khỏe, danh sách vấn đề (kèm số liệu, % tin cậy), tần suất chi tiêu (heatmap) — tất cả tính bằng `FinancialAnalyticsService`, **không cần gọi Gemini**, không có màn hình loading chờ AI như hiện tại.
2. **AI chỉ được gọi khi người dùng chủ động yêu cầu** (bấm "Xem giải thích từ AI" trên từng thẻ riêng lẻ) — theo đúng pattern lazy-load đã có sẵn cho "Gợi ý cắt giảm chi tiêu" (`_loadCutSuggestion`), áp dụng nhất quán cho toàn màn.
3. **Mỗi phản hồi AI phải ngắn gọn, có số liệu cụ thể** — không viết đoạn văn dài, tối đa 2-3 câu/lần.

## 3. Fix Requirements

### 3.1. `lib/models/financial_issue.dart` — thêm phân loại + điểm tin cậy

```dart
enum IssueSeverity { warning, critical }
enum IssueCategory { spike, budgetShare, lowSaving } // MỚI — dùng để chọn icon/nhóm thẻ

class FinancialIssue {
  final String title;
  final String description;
  final IssueSeverity severity;
  final IssueCategory category;      // MỚI
  final double confidenceScore;      // MỚI — 0-100, tính bằng Dart (mục 3.2)
  final String? categoryName;
  final double? currentValue;
  final double? thresholdValue;

  FinancialIssue({
    required this.title,
    required this.description,
    required this.severity,
    required this.category,
    required this.confidenceScore,
    this.categoryName,
    this.currentValue,
    this.thresholdValue,
  });
}
```

### 3.2. `lib/services/financial_analytics_service.dart` — tính điểm tin cậy + heatmap (Dart thuần, không gọi AI)

**a) Công thức tính "Điểm tin cậy" (`confidenceScore`)** — phản ánh mức độ vi phạm ngưỡng càng xa, tin cậy càng cao rằng đây là vấn đề thật sự đáng chú ý (không phải xác suất thống kê, mà là độ lệch chuẩn hóa so với ngưỡng đã định nghĩa sẵn):

```dart
double _calculateConfidence(double currentValue, double thresholdValue) {
  if (thresholdValue == 0) return 60;
  final deviation = (currentValue - thresholdValue).abs() / thresholdValue;
  return (60 + deviation * 100).clamp(60, 99);
}
```

Áp dụng hàm này khi tạo từng `FinancialIssue` trong `detectIssues()` — truyền đúng `currentValue`/`thresholdValue` đã có sẵn ở từng nhánh phát hiện (spike, share, saving rate), gán thêm `category` tương ứng (`IssueCategory.spike`, `.budgetShare`, `.lowSaving`).

**b) Hàm mới — tính tần suất chi tiêu theo tuần (heatmap), thay cho việc AI tự mô tả:**

```dart
/// Trả về Map<TênDanhMục, List<int>> — mỗi phần tử trong List là mức độ đậm
/// nhạt (0-4) của chi tiêu vào đúng thứ đó trong tuần (index 0=Thứ 2 ... 6=CN),
/// tính từ TẤT CẢ giao dịch chi tiêu được truyền vào (nên truyền dữ liệu 30 
/// ngày gần nhất). Chỉ lấy tối đa 3-4 danh mục có tổng chi tiêu cao nhất.
Map<String, List<int>> computeWeeklyHeatmap(
  List<AppTransaction> transactions,
  List<Category> categories, {
  int topN = 4,
}) {
  final Map<String, List<double>> sums = {}; // tên danh mục -> tổng theo 7 thứ
  for (final tx in transactions.where((t) => t.type == 'expense')) {
    final cat = categories
        .firstWhere((c) => c.categoryId == tx.categoryId,
            orElse: () => Category(categoryId: tx.categoryId, userId: '', name: 'Khác',
                type: 'expense', icon: 'category', color: 0xFF9E9E9E));
    final weekday = tx.date.weekday - 1; // 0 = Thứ 2
    sums.putIfAbsent(cat.name, () => List.filled(7, 0));
    sums[cat.name]![weekday] += tx.amount;
  }
  // Chỉ giữ topN danh mục theo tổng chi tiêu, chuẩn hóa mỗi ô về thang 0-4
  final sortedEntries = sums.entries.toList()
    ..sort((a, b) => b.value.reduce((x, y) => x + y).compareTo(a.value.reduce((x, y) => x + y)));
  final top = sortedEntries.take(topN);

  final result = <String, List<int>>{};
  for (final entry in top) {
    final maxVal = entry.value.reduce((a, b) => a > b ? a : b);
    result[entry.key] = entry.value
        .map((v) => maxVal == 0 ? 0 : (v / maxVal * 4).round().clamp(0, 4))
        .toList();
  }
  return result;
}
```

### 3.3. `lib/services/ai_service.dart` — thêm hàm giải thích TỪNG vấn đề riêng lẻ (lazy-load)

Thêm hàm mới, **không xóa/sửa** `explainAndSuggestForIssues()` cũ (vẫn giữ nguyên trong file, không dùng ở màn này nữa nhưng không xóa để tránh phá vỡ nơi khác nếu có):

```dart
/// Giải thích + đề xuất cho ĐÚNG 1 vấn đề, gọi khi người dùng bấm xem chi
/// tiết trên 1 thẻ cụ thể — ngắn gọn, không viết đoạn văn dài.
Future<String> explainSingleIssue(FinancialIssue issue) async {
  final prompt = '''
Bạn là trợ lý tài chính cá nhân. Hệ thống đã phát hiện vấn đề sau (đã tính
sẵn bằng số liệu, không cần bạn tính toán lại):

${issue.title}: ${issue.description}

Viết TỐI ĐA 2-3 câu bằng tiếng Việt: 1 câu nêu nguyên nhân có thể, 1 câu đề
xuất phương án cải thiện CÓ SỐ LIỆU CỤ THỂ. Không lan man, không mở đầu bằng
lời chào.
''';
  final response = await _generateWithFallback([Content.text(prompt)]);
  return response.text ?? 'Không thể tạo đề xuất lúc này.';
}
```

### 3.4. `lib/screens/ai/ai_insight_screen.dart` — tái cấu trúc toàn bộ luồng hiển thị

**a) Bỏ eager-loading (Future.wait toàn bộ khi mở màn):**
`_loadInsights()` giờ **chỉ** chạy `FinancialAnalyticsService` (Dart thuần — nhanh, không cần chờ mạng) để có: `healthScore`, `issues` (đã có `confidenceScore`/`category`), `weeklyHeatmap`, và danh sách gợi ý cắt giảm (`topCuts`, tái sử dụng logic đã có). **Không** gọi `analyzeSpendingHabits`/`predictMonthEnd`/`analyzeTrend`/`explainAndSuggestForIssues` ngay lúc mở màn nữa — màn hình hiện dữ liệu gần như tức thời, không còn màn hình "AI đang phân tích dữ liệu của bạn..." chờ dài.

**b) Cấu trúc hiển thị mới (từ trên xuống):**
1. **Điểm sức khỏe tài chính** — giữ nguyên như hiện tại (đã tốt, không đổi).
2. **"Vấn đề & Cơ hội"** — gộp `issues` (từ `detectIssues`) và `topCuts` (từ logic cắt giảm hiện có, coi là loại "Cơ hội tiết kiệm") thành 1 danh sách thẻ chung. Mỗi thẻ:
   - Icon theo `category` (spike → mũi tên tăng, budgetShare → biểu đồ tròn, lowSaving → ví, cơ hội tiết kiệm → bóng đèn).
   - Badge % **"Tin cậy"** ở góc (dùng `confidenceScore`, hoặc với thẻ "Cơ hội tiết kiệm" gán cố định `85%` vì không có ngưỡng vi phạm để tính — ghi rõ trong code là giá trị mặc định cho loại thẻ này).
   - `title` + `description` (đã có sẵn, hiện luôn — đây là phần Dart tính, không cần chờ AI).
   - Nút **"Xem giải thích từ AI"** — khi bấm, gọi `explainSingleIssue(issue)` (loading spinner nhỏ chỉ trong phạm vi thẻ đó, không chặn cả màn hình), kết quả hiện thêm bên dưới thẻ, có thể thu gọn lại.
   - Nút **"Bỏ qua"** — ẩn thẻ khỏi danh sách **chỉ trong phiên xem hiện tại** (state cục bộ trong `_AiInsightScreenState`, KHÔNG lưu Firestore — đúng phạm vi đã xác định ở `context/PRD.md` mục 2.1, không có collection lưu lịch sử vấn đề).
3. **"Tần suất chi tiêu theo tuần"** — widget mới `WeeklyHeatmapCard` (tạo file riêng `lib/widgets/weekly_heatmap_card.dart`), nhận `Map<String, List<int>>` từ `computeWeeklyHeatmap()`, vẽ dạng lưới 7 cột (T2-CN) × N hàng (danh mục), mỗi ô tô màu theo mức độ 0-4 (dùng `AppColors.primary` với opacity tăng dần). Hoàn toàn Dart, hiện ngay không cần AI — khớp đúng phần "Tần suất chi tiêu theo tuần" đã thấy trong thiết kế Figma.
4. **"Xu hướng chi tiêu 6 tháng"** (`TrendChartCard`) — giữ nguyên, nhưng chuyển sang **lazy-load**: chỉ gọi `analyzeTrend()` khi người dùng cuộn tới/bấm mở rộng section này (dùng `ExpansionTile` hoặc nút "Xem phân tích xu hướng"), không gọi ngay lúc mở màn.

**c) Bỏ hẳn 2 card cũ "Phân tích thói quen chi tiêu" và "Dự đoán chi tiêu cuối tháng"** dạng đoạn văn dài hiện sẵn — gộp chung thành 1 mục **"Nhận định tổng quan từ AI"** dạng thu gọn (`ExpansionTile`, đóng mặc định), khi mở ra mới gọi `analyzeSpendingHabits()` + `predictMonthEnd()` (giữ nguyên 2 hàm này trong `AiService`, không đổi logic bên trong — chỉ đổi thời điểm gọi từ "ngay khi mở màn" sang "khi người dùng bấm mở rộng").

### 3.5. Áp dụng UI theo Figma

Đổi màu sắc/spacing/card style theo đúng thiết kế Figma đã cung cấp cho màn "Phân tích AI".

## 4. Không đổi (Out of scope)

- Không đổi `kCategorySpikeThreshold`, `kCategoryShareThreshold`, `kLowSavingRateThreshold`, công thức `calculateHealthScore()` — giữ nguyên như hiện tại.
- Không triển khai tính năng "phát hiện đăng ký dịch vụ trùng lặp" (như ví dụ trong Figma "Cơ hội tiết kiệm: phát hiện đăng ký dịch vụ trùng lặp") — đây là thuật toán mới phức tạp (so khớp giao dịch định kỳ), chưa có trong `SCHEMA.md`/`ARCHITECTURE.md`, để dành cho ticket riêng sau nếu cần. Thẻ "Cơ hội tiết kiệm" trong ticket này **tái sử dụng** logic gợi ý cắt giảm chi tiêu (AI 6) đã có sẵn.
- Không thêm collection Firestore mới để lưu trạng thái "đã bỏ qua" vĩnh viễn — chỉ ẩn tạm trong phiên xem.
- Không xóa `analyzeSpendingHabits()`, `predictMonthEnd()`, `analyzeTrend()`, `explainAndSuggestForIssues()` khỏi `AiService` — chỉ đổi cách/thời điểm gọi ở `AiInsightScreen`, các hàm vẫn giữ nguyên logic bên trong.
- Không đổi `AiChatScreen`, `AiReportScreen`.

## 5. Acceptance Criteria

- [ ] Mở màn AI Insight → hiện **ngay lập tức** (không có màn "đang phân tích" chờ mạng): Điểm sức khỏe, danh sách thẻ Vấn đề & Cơ hội (kèm % Tin cậy), heatmap tần suất chi tiêu.
- [ ] Mỗi thẻ vấn đề hiện đúng % Tin cậy tính từ công thức Dart, không phải số Gemini tự nghĩ ra (kiểm tra: đóng mạng/tắt wifi vẫn thấy đầy đủ danh sách vấn đề + % tin cậy, chỉ phần "Xem giải thích từ AI" mới báo lỗi mạng khi bấm).
- [ ] Bấm "Xem giải thích từ AI" trên 1 thẻ → chỉ thẻ đó hiện loading, các thẻ khác không bị ảnh hưởng; kết quả trả về ngắn gọn (2-3 câu), có số liệu cụ thể nhắc đúng tên vấn đề.
- [ ] Bấm "Bỏ qua" trên 1 thẻ → thẻ biến mất khỏi danh sách ngay; thoát màn rồi vào lại → thẻ đó xuất hiện lại (xác nhận không lưu Firestore, chỉ ẩn tạm theo phiên).
- [ ] Heatmap hiện đúng tối đa 4 danh mục chi tiêu nhiều nhất, màu đậm nhạt phản ánh đúng ngày chi tiêu nhiều/ít trong tuần.
- [ ] Mục "Xu hướng chi tiêu 6 tháng" và "Nhận định tổng quan từ AI" mặc định thu gọn, chỉ gọi Gemini khi người dùng bấm mở rộng.
- [ ] Tháng không có vấn đề gì (an toàn) → hiện điểm gần 100, danh sách thẻ vấn đề rỗng nhưng vẫn hiện đúng heatmap + các mục khác, không lỗi.
- [ ] So sánh cảm nhận: màn hình mới không còn cảm giác "toàn chữ" ngay từ đầu — phần chữ dài chỉ xuất hiện khi người dùng chủ động bấm xem.
- [ ] Test tối thiểu 2 tài khoản: 1 tài khoản có nhiều vấn đề (nhiều thẻ), 1 tài khoản sạch (ít/không vấn đề) để xác nhận cả 2 trường hợp hiển thị đúng.
