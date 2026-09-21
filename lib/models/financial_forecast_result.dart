import 'financial_issue.dart';

/// Trạng thái dự báo ngân sách
enum BudgetForecastStatus {
  safe, // An toàn
  warning, // Cảnh báo (dùng >=80% hoặc sắp chạm hạn mức trong 7 ngày)
  atRisk, // Có nguy cơ vượt trong tháng hiện tại
  exceeded, // Đã vượt hạn mức
}

/// 1. Dự báo số dư cuối tháng
class MonthEndForecast {
  final double currentTotalBalance;
  final double monthToDateExpense;
  final double monthToDateIncome;
  final double averageDailyExpense;
  final int elapsedDays;
  final int remainingDays;
  final int totalDaysInMonth;
  final double projectedRemainingExpense;
  final double projectedEndBalance;
  final bool hasEnoughData;
  final double plannedRemainingIncome;
  final double plannedRemainingExpense;
  final double averageDailyDiscretionaryExpense;
  final double projectedRemainingDiscretionaryExpense;

  const MonthEndForecast({
    required this.currentTotalBalance,
    required this.monthToDateExpense,
    required this.monthToDateIncome,
    required this.averageDailyExpense,
    required this.elapsedDays,
    required this.remainingDays,
    required this.totalDaysInMonth,
    required this.projectedRemainingExpense,
    required this.projectedEndBalance,
    required this.hasEnoughData,
    this.plannedRemainingIncome = 0,
    this.plannedRemainingExpense = 0,
    double? averageDailyDiscretionaryExpense,
    double? projectedRemainingDiscretionaryExpense,
  })  : averageDailyDiscretionaryExpense =
            averageDailyDiscretionaryExpense ?? averageDailyExpense,
        projectedRemainingDiscretionaryExpense =
            projectedRemainingDiscretionaryExpense ?? projectedRemainingExpense;
}

/// 2. Dự báo nguy cơ vượt ngân sách cho từng danh mục
class BudgetForecast {
  final String budgetId;
  final String categoryId;
  final String categoryName;
  final double limit;
  final double spent;
  final double dailyPace;
  final double percentUsed;
  final DateTime? estimatedExceededDate;
  final int? daysToLimit;
  final BudgetForecastStatus status;

  const BudgetForecast({
    required this.budgetId,
    required this.categoryId,
    required this.categoryName,
    required this.limit,
    required this.spent,
    required this.dailyPace,
    required this.percentUsed,
    this.estimatedExceededDate,
    this.daysToLimit,
    required this.status,
  });
}

/// 3. Chi tiêu bất thường so với lịch sử 3 tháng trước
class SpendingAnomaly {
  final String categoryId;
  final String categoryName;
  final double currentSpend;
  final double expectedSpendToDate;
  final double averageMonthlySpend;
  final double excessAmount;
  final double excessRatio; // ví dụ 1.35 = vượt 35%
  final int monthsOfHistory;
  final IssueSeverity severity;

  const SpendingAnomaly({
    required this.categoryId,
    required this.categoryName,
    required this.currentSpend,
    required this.expectedSpendToDate,
    required this.averageMonthlySpend,
    required this.excessAmount,
    required this.excessRatio,
    required this.monthsOfHistory,
    required this.severity,
  });
}

/// 4. Chi tiết khoản trừ điểm sức khỏe tài chính
class HealthScoreDeduction {
  final String reason;
  final int points;
  final String? categoryId;

  const HealthScoreDeduction({
    required this.reason,
    required this.points,
    this.categoryId,
  });
}

/// 5. Tổng hợp toàn bộ Insight
class FinancialInsightSummary {
  final MonthEndForecast monthEndForecast;
  final List<BudgetForecast> budgetForecasts;
  final List<SpendingAnomaly> anomalies;
  final List<FinancialIssue> issues;
  final int healthScore;
  final String
      healthRating; // Tốt | Cần theo dõi | Có rủi ro | Cần hành động ngay
  final List<HealthScoreDeduction> deductions;
  final DateTime referenceDate;

  const FinancialInsightSummary({
    required this.monthEndForecast,
    required this.budgetForecasts,
    required this.anomalies,
    required this.issues,
    required this.healthScore,
    required this.healthRating,
    required this.deductions,
    required this.referenceDate,
  });
}
