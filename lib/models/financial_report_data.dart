import 'financial_forecast_result.dart';

/// Item đại diện cho cơ cấu chi tiêu theo danh mục trong PDF report
class CategoryExpenseItem {
  final String categoryName;
  final double amount;
  final double percentage;

  CategoryExpenseItem({
    required this.categoryName,
    required this.amount,
    required this.percentage,
  });
}

/// Item đại diện cho trạng thái ngân sách trong PDF report
class BudgetReportItem {
  final String categoryName;
  final double spent;
  final double limit;
  final double percentage;
  final String status; // 'An toàn' | 'Cảnh báo' | 'Có nguy cơ' | 'Đã vượt'

  BudgetReportItem({
    required this.categoryName,
    required this.spent,
    required this.limit,
    required this.percentage,
    required this.status,
  });
}

/// Item đại diện cho mục tiêu tiết kiệm trong PDF report
class SavingGoalReportItem {
  final String goalName;
  final double savedAmount;
  final double targetAmount;
  final double percentage;

  SavingGoalReportItem({
    required this.goalName,
    required this.savedAmount,
    required this.targetAmount,
    required this.percentage,
  });
}

/// Item đại diện cho AI Financial Insight / Cảnh báo trong PDF report
class ReportInsightItem {
  final String title;
  final String description;
  final String type; // 'warning' | 'positive' | 'success'

  ReportInsightItem({
    required this.title,
    required this.description,
    required this.type,
  });
}

/// Model chứa toàn bộ số liệu báo cáo tài chính đã được tổng hợp (Pure-Dart).
/// Tầng PDF Renderer chỉ nhận model này để vẽ giao diện, không query Firestore
/// và không chứa business logic trùng lặp.
class FinancialReportData {
  final String reportTitle;
  final String periodLabel;
  final DateTime exportDate;
  final bool isCurrentMonth;

  final double totalIncome;
  final double totalExpense;
  final double netDifference;
  final double? currentWalletBalance; // Chỉ hiển thị nếu isCurrentMonth == true

  final List<CategoryExpenseItem> categoryBreakdown;
  final List<BudgetReportItem> budgets;
  final List<SavingGoalReportItem> savingGoals;
  final List<ReportInsightItem> insights;

  final int healthScore;
  final String healthRating;

  final MonthEndForecast? monthEndForecast; // Chỉ hiển thị nếu isCurrentMonth == true

  FinancialReportData({
    required this.reportTitle,
    required this.periodLabel,
    required this.exportDate,
    required this.isCurrentMonth,
    required this.totalIncome,
    required this.totalExpense,
    required this.netDifference,
    this.currentWalletBalance,
    required this.categoryBreakdown,
    required this.budgets,
    required this.savingGoals,
    required this.insights,
    required this.healthScore,
    required this.healthRating,
    this.monthEndForecast,
  });
}
