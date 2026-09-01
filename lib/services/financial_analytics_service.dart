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

  /// Tính "Điểm tin cậy" — mức độ vi phạm ngưỡng càng xa, tin cậy càng cao
  /// rằng đây là vấn đề thật sự (không phải xác suất thống kê, mà là độ lệch
  /// chuẩn hóa so với ngưỡng đã định nghĩa sẵn).
  double _calculateConfidence(double currentValue, double thresholdValue) {
    if (thresholdValue == 0) return 60;
    final deviation = (currentValue - thresholdValue).abs() / thresholdValue;
    return (60 + deviation * 100).clamp(60, 99).toDouble();
  }

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
          final threshold = lastAmount * (1 + kCategorySpikeThreshold);
          issues.add(FinancialIssue(
            title: '$catName tăng ${(percentChange * 100).round()}% so với tháng trước',
            description:
                'Tháng trước: ${lastAmount.round()}đ → Tháng này: ${currentAmount.round()}đ',
            severity: percentChange > 0.5 ? IssueSeverity.critical : IssueSeverity.warning,
            category: IssueCategory.spike,
            confidenceScore: _calculateConfidence(currentAmount, threshold),
            categoryName: catName,
            currentValue: currentAmount,
            thresholdValue: threshold,
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
            category: IssueCategory.budgetShare,
            confidenceScore: _calculateConfidence(share, kCategoryShareThreshold),
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
          category: IssueCategory.lowSaving,
          confidenceScore: _calculateConfidence(savingRate, kLowSavingRateThreshold),
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

  /// Tính tần suất chi tiêu theo tuần (heatmap).
  /// Trả về Map<TênDanhMục, List<int>> — mỗi phần tử trong List là mức độ đậm
  /// nhạt (0-4) của chi tiêu vào đúng thứ đó trong tuần (index 0=Thứ 2 ... 6=CN),
  /// tính từ TẤT CẢ giao dịch chi tiêu được truyền vào (nên truyền dữ liệu 30
  /// ngày gần nhất). Chỉ lấy tối đa topN danh mục có tổng chi tiêu cao nhất.
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
}
