# TICKET 013 — Financial Analytics Layer + Điểm sức khỏe tài chính + Mở rộng AI Insight

**Loại:** Feature (định hướng phát triển chính sau phản biện hội đồng — xem PRD.md mục 2.1, ARCHITECTURE.md mục 3.4, RULES.md mục 7)
**Độ ưu tiên:** Cao — đây là nội dung cốt lõi cần có trước khi bảo vệ
**File bị ảnh hưởng:** `lib/models/financial_issue.dart` (mới), `lib/services/financial_analytics_service.dart` (mới), `lib/services/ai_service.dart`, `lib/screens/ai/ai_insight_screen.dart`

---

## 1. Context

Hội đồng nhận xét: (1) cần thể hiện phần "tự viết", không chỉ nhúng Gemini; (2) AI phải tìm ra **vấn đề cụ thể**, không dừng ở tường thuật số liệu. Giải pháp: thêm tầng tính toán Dart thuần **trước** khi gọi Gemini, chuyển vai trò Gemini từ "phân tích từ đầu" sang "giải thích + đề xuất dựa trên vấn đề đã phát hiện sẵn".

## 2. Fix Requirements

### 2.1. Model mới — `lib/models/financial_issue.dart`

```dart
enum IssueSeverity { warning, critical } // vàng / đỏ

class FinancialIssue {
  final String title;           // VD: "Ăn uống tăng 32% so với tháng trước"
  final String description;     // câu mô tả ngắn, không cần AI viết
  final IssueSeverity severity;
  final String? categoryName;   // null nếu vấn đề không gắn 1 danh mục cụ thể (VD tỷ lệ tiết kiệm)
  final double? currentValue;   // giá trị hiện tại (số tiền hoặc %)
  final double? thresholdValue; // ngưỡng đã vi phạm

  FinancialIssue({
    required this.title,
    required this.description,
    required this.severity,
    this.categoryName,
    this.currentValue,
    this.thresholdValue,
  });
}
```

### 2.2. Service mới — `lib/services/financial_analytics_service.dart`

```dart
import '../models/transaction_model.dart';
import '../models/category_model.dart';
import '../models/financial_issue.dart';

/// ============================================================
/// FINANCIAL ANALYTICS SERVICE
/// Tính toán chỉ số tài chính & phát hiện vấn đề bằng NGƯỠNG CỤ THỂ.
/// Toàn bộ hàm trong file này là DART THUẦN — không gọi Gemini/AI.
/// Đây là tầng phân tích độc lập, phục vụ đúng yêu cầu hội đồng:
/// "hệ thống phải tự tính toán, không giao phó hết cho AI".
/// ============================================================
class FinancialAnalyticsService {
  // Ngưỡng phát hiện vấn đề — có thể tinh chỉnh, để hằng số cho dễ đọc/sửa
  static const double kCategorySpikeThreshold = 0.30;   // tăng >30% so tháng trước
  static const double kCategoryShareThreshold = 0.25;   // 1 danh mục chiếm >25% thu nhập
  static const double kLowSavingRateThreshold = 0.20;   // tỷ lệ tiết kiệm <20%

  Map<String, double> _sumByCategory(List<AppTransaction> transactions) {
    final Map<String, double> result = {};
    for (final tx in transactions.where((t) => t.type == 'expense')) {
      result[tx.categoryId] = (result[tx.categoryId] ?? 0) + tx.amount;
    }
    return result;
  }

  /// Phát hiện danh sách vấn đề tài chính của tháng hiện tại, so với tháng trước.
  /// [currentMonthTx] và [lastMonthTx]: giao dịch đã lọc sẵn theo đúng khoảng
  /// thời gian (KHÔNG lọc lại trong hàm này — tách trách nhiệm rõ ràng).
  List<FinancialIssue> detectIssues({
    required List<AppTransaction> currentMonthTx,
    required List<AppTransaction> lastMonthTx,
    required List<Category> categories,
    required double monthlyIncome,
  }) {
    final issues = <FinancialIssue>[];

    final currentByCategory = _sumByCategory(currentMonthTx);
    final lastByCategory = _sumByCategory(lastMonthTx);

    final totalExpense = currentByCategory.values.fold<double>(0, (a, b) => a + b);
    final totalIncome = currentMonthTx
        .where((t) => t.type == 'income')
        .fold<double>(0, (a, t) => a + t.amount);
    final effectiveIncome = totalIncome > 0 ? totalIncome : monthlyIncome;

    // 1. Phát hiện danh mục tăng đột biến so với tháng trước
    currentByCategory.forEach((categoryId, currentAmount) {
      final lastAmount = lastByCategory[categoryId] ?? 0;
      if (lastAmount > 0) {
        final percentChange = (currentAmount - lastAmount) / lastAmount;
        if (percentChange > kCategorySpikeThreshold) {
          final catName = categories
              .firstWhere((c) => c.categoryId == categoryId,
                  orElse: () => Category(
                      categoryId: categoryId, userId: '', name: 'Khác',
                      type: 'expense', icon: 'category', color: 0xFF9E9E9E))
              .name;
          issues.add(FinancialIssue(
            title: '$catName tăng ${(percentChange * 100).round()}% so với tháng trước',
            description:
                'Tháng trước: ${lastAmount.round()}đ → Tháng này: ${currentAmount.round()}đ',
            severity: percentChange > 0.5 ? IssueSeverity.critical : IssueSeverity.warning,
            categoryName: catName,
            currentValue: currentAmount,
            thresholdValue: lastAmount * (1 + kCategorySpikeThreshold),
          ));
        }
      }
    });

    // 2. Phát hiện danh mục chiếm tỷ trọng quá lớn trong thu nhập
    if (effectiveIncome > 0) {
      currentByCategory.forEach((categoryId, amount) {
        final share = amount / effectiveIncome;
        if (share > kCategoryShareThreshold) {
          final catName = categories
              .firstWhere((c) => c.categoryId == categoryId,
                  orElse: () => Category(
                      categoryId: categoryId, userId: '', name: 'Khác',
                      type: 'expense', icon: 'category', color: 0xFF9E9E9E))
              .name;
          issues.add(FinancialIssue(
            title: '$catName chiếm ${(share * 100).round()}% thu nhập tháng này',
            description: 'Vượt ngưỡng khuyến nghị ${(kCategoryShareThreshold * 100).round()}%',
            severity: share > 0.4 ? IssueSeverity.critical : IssueSeverity.warning,
            categoryName: catName,
            currentValue: share,
            thresholdValue: kCategoryShareThreshold,
          ));
        }
      });
    }

    // 3. Phát hiện tỷ lệ tiết kiệm thấp
    if (effectiveIncome > 0) {
      final savingRate = (effectiveIncome - totalExpense) / effectiveIncome;
      if (savingRate < kLowSavingRateThreshold) {
        issues.add(FinancialIssue(
          title: 'Tỷ lệ tiết kiệm chỉ đạt ${(savingRate * 100).round()}%',
          description: 'Thấp hơn ngưỡng khuyến nghị ${(kLowSavingRateThreshold * 100).round()}%',
          severity: savingRate < 0.05 ? IssueSeverity.critical : IssueSeverity.warning,
          currentValue: savingRate,
          thresholdValue: kLowSavingRateThreshold,
        ));
      }
    }

    return issues;
  }

  /// Tính Điểm sức khỏe tài chính (0-100).
  /// Công thức: điểm khởi đầu 100, trừ điểm theo mức độ nghiêm trọng của
  /// từng vấn đề đã phát hiện (critical trừ nhiều hơn warning), tối thiểu 0.
  int calculateHealthScore(List<FinancialIssue> issues) {
    double score = 100;
    for (final issue in issues) {
      score -= issue.severity == IssueSeverity.critical ? 20 : 10;
    }
    return score.clamp(0, 100).round();
  }
}
```

### 2.3. `ai_service.dart` — thêm hàm mới, KHÔNG sửa các hàm AI 1-6 cũ

Thêm hàm mới (giữ nguyên toàn bộ code hiện có, chỉ thêm):
```dart
/// AI Insight nâng cao: nhận danh sách vấn đề ĐÃ PHÁT HIỆN SẴN (bằng
/// FinancialAnalyticsService), yêu cầu Gemini giải thích nguyên nhân và
/// đề xuất phương án — KHÔNG đưa dữ liệu thô, không để Gemini tự tính %.
Future<String> explainAndSuggestForIssues(List<FinancialIssue> issues) async {
  if (issues.isEmpty) {
    return 'Chúc mừng bạn! Chưa phát hiện vấn đề tài chính đáng chú ý nào trong tháng này.';
  }
  final issuesText = issues.map((i) => '- ${i.title}: ${i.description}').join('\n');
  final prompt = '''
Bạn là trợ lý tài chính cá nhân. Hệ thống đã PHÁT HIỆN SẴN các vấn đề tài chính
sau đây (dựa trên phân tích số liệu, không cần bạn tính toán lại):

$issuesText

Với MỖI vấn đề, hãy viết ngắn gọn (1-2 câu):
1. Nguyên nhân có thể (dựa trên loại vấn đề)
2. Đề xuất phương án cải thiện CÓ SỐ LIỆU CỤ THỂ (VD "giảm xuống còn X đồng/tháng")

Trả lời bằng tiếng Việt, giọng thân thiện, đi thẳng vào từng vấn đề.
''';
  final response = await _generateWithFallback([Content.text(prompt)]);
  return response.text ?? 'Không thể tạo đề xuất lúc này.';
}
```
Cần thêm `import '../models/financial_issue.dart';` vào đầu file.

### 2.4. `ai_insight_screen.dart` — mở rộng hiển thị (giữ nguyên phần cũ)

- Thêm gọi `FinancialAnalyticsService().detectIssues(...)` và `.calculateHealthScore(...)` khi load dữ liệu (cần fetch thêm giao dịch **tháng trước** để so sánh — dùng `streamTransactions` đã có, chỉ đổi khoảng `from`/`to`).
- Thêm UI đầu trang: card hiển thị **Điểm sức khỏe tài chính** (số lớn 0-100, màu theo mức: xanh ≥70, vàng 40-69, đỏ <40).
- Thêm UI danh sách **vấn đề phát hiện** (mỗi item: icon cảnh báo theo `severity`, `title`, `description`) — hiển thị **trước** phần "Phân tích thói quen chi tiêu" cũ.
- Gọi `AiService().explainAndSuggestForIssues(issues)` để lấy đề xuất, hiển thị dưới mỗi vấn đề hoặc thành 1 card riêng "Đề xuất từ AI".
- **Giữ nguyên** toàn bộ phần cũ (trend chart, spending analysis, month-end prediction, cut suggestions) — chỉ **thêm**, không xóa.

## 3. Không đổi (Out of scope)

- Không đổi `AI 1-6` cũ trong `ai_service.dart` — vẫn giữ nguyên, hoạt động song song với tính năng mới.
- Không tạo collection Firestore mới (xem SCHEMA.md) — mọi thứ tính on-the-fly.
- Không làm màn "AI Financial Coach" riêng — dùng chung `AiInsightScreen`.
- Không làm vòng lặp theo dõi kết quả dài hạn.

## 4. Acceptance Criteria

- [ ] Mở `AiInsightScreen` → hiện đúng Điểm sức khỏe tài chính (0-100), màu sắc đúng theo mức.
- [ ] Có ít nhất 1 danh mục chi tiêu tăng >30% so tháng trước (test bằng dữ liệu giả) → hiện đúng trong danh sách vấn đề, kèm số liệu cụ thể (không phải văn bản AI tự bịa).
- [ ] Đề xuất từ Gemini phải **nhắc đúng tên vấn đề đã phát hiện**, có số liệu cụ thể trong câu trả lời (không chung chung kiểu "bạn nên tiết kiệm hơn").
- [ ] Tháng không có vấn đề gì (tất cả trong ngưỡng an toàn) → hiện điểm gần 100, thông báo tích cực, không hiện danh sách vấn đề rỗng gây khó hiểu.
- [ ] Toàn bộ tính năng cũ của `AiInsightScreen` (trend chart, spending habits, prediction, cut suggestions) vẫn hoạt động bình thường, không bị ảnh hưởng.
