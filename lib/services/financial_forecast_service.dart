import '../models/budget_model.dart';
import '../models/category_model.dart';
import '../models/financial_forecast_result.dart';
import '../models/financial_issue.dart';
import '../models/recurring_transaction_model.dart';
import '../models/transaction_model.dart';
import '../models/wallet_model.dart';
import 'recurring_transaction_service.dart';

/// ============================================================
/// FINANCIAL FORECAST SERVICE
/// Dự báo dòng tiền, cảnh báo ngân sách & phát hiện chi tiêu bất thường.
/// TOÀN BỘ HÀM TRONG FILE NÀY LÀ DART THUẦN — KHÔNG GỌI GEMINI/AI.
/// ============================================================
class FinancialForecastService {
  static const double kMinAnomalyAmountVnd = 100000.0; // Ngưỡng 100.000đ
  static const double kAnomalyThresholdRatio = 1.30; // Vượt 30% kỳ vọng
  static const double kAnomalyCriticalRatio = 1.60; // Vượt 60% -> critical
  static const double kBudgetWarningRatio = 0.80; // Dùng >= 80% hạn mức

  /// 1. Dự báo số dư cuối tháng (Có hỗ trợ các khoản định kỳ chưa đến hạn)
  MonthEndForecast calculateMonthEndForecast({
    required List<Wallet> activeWallets,
    required List<AppTransaction> currentMonthTx,
    List<RecurringTransactionSchedule>? recurringSchedules,
    DateTime? refDate,
  }) {
    final today = refDate ?? DateTime.now();
    final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
    final elapsedDays = today.day.clamp(1, daysInMonth);
    final remainingDays = (daysInMonth - today.day).clamp(0, daysInMonth);

    // Tính tổng số dư hiện tại của các ví đang active
    final currentTotalBalance = activeWallets
        .where((w) => w.isActive)
        .fold<double>(0, (sum, w) => sum + w.balance);

    // Chỉ tính expense và income thực tế. LOẠI TRỪ transfer, goal_deposit, goal_withdraw
    final expenseTx = currentMonthTx.where((t) => t.type == 'expense');
    final incomeTx = currentMonthTx.where((t) => t.type == 'income');

    final monthToDateExpense =
        expenseTx.fold<double>(0, (sum, t) => sum + t.amount);
    final monthToDateIncome =
        incomeTx.fold<double>(0, (sum, t) => sum + t.amount);

    // Tính riêng chi tiêu linh hoạt thủ công (không chứa recurringScheduleId)
    final discretionaryExpenseTx = expenseTx.where(
        (t) => t.recurringScheduleId == null || t.recurringScheduleId!.isEmpty);
    final monthToDateDiscretionaryExpense =
        discretionaryExpenseTx.fold<double>(0, (sum, t) => sum + t.amount);

    // Tính thu/chi định kỳ còn lại trong tháng chưa phát sinh
    double plannedRemainingIncome = 0;
    double plannedRemainingExpense = 0;
    if (recurringSchedules != null && recurringSchedules.isNotEmpty) {
      final planned =
          RecurringTransactionService().computePlannedRemainingAmounts(
        schedules: recurringSchedules,
        referenceDate: today,
      );
      plannedRemainingIncome = planned.plannedRemainingIncome;
      plannedRemainingExpense = planned.plannedRemainingExpense;
    }

    final hasEnoughData = monthToDateExpense > 0 && expenseTx.isNotEmpty;

    if (!hasEnoughData) {
      final projectedEndBalance = currentTotalBalance +
          plannedRemainingIncome -
          plannedRemainingExpense;

      return MonthEndForecast(
        currentTotalBalance: currentTotalBalance,
        monthToDateExpense: 0,
        monthToDateIncome: monthToDateIncome,
        averageDailyExpense: 0,
        elapsedDays: elapsedDays,
        remainingDays: remainingDays,
        totalDaysInMonth: daysInMonth,
        projectedRemainingExpense: plannedRemainingExpense,
        projectedEndBalance: projectedEndBalance,
        hasEnoughData: false,
        plannedRemainingIncome: plannedRemainingIncome,
        plannedRemainingExpense: plannedRemainingExpense,
        averageDailyDiscretionaryExpense: 0,
        projectedRemainingDiscretionaryExpense: 0,
      );
    }

    final averageDailyExpense = monthToDateExpense / elapsedDays;
    final projectedRemainingExpense = averageDailyExpense * remainingDays;

    final averageDailyDiscretionaryExpense =
        monthToDateDiscretionaryExpense / elapsedDays;
    final projectedRemainingDiscretionaryExpense =
        averageDailyDiscretionaryExpense * remainingDays;

    // Công thức: projectedEndBalance = currentTotalBalance + plannedRemainingIncome - projectedRemainingDiscretionaryExpense - plannedRemainingExpense
    final projectedEndBalance = currentTotalBalance +
        plannedRemainingIncome -
        projectedRemainingDiscretionaryExpense -
        plannedRemainingExpense;

    return MonthEndForecast(
      currentTotalBalance: currentTotalBalance,
      monthToDateExpense: monthToDateExpense,
      monthToDateIncome: monthToDateIncome,
      averageDailyExpense: averageDailyExpense,
      elapsedDays: elapsedDays,
      remainingDays: remainingDays,
      totalDaysInMonth: daysInMonth,
      projectedRemainingExpense: projectedRemainingExpense,
      projectedEndBalance: projectedEndBalance,
      hasEnoughData: true,
      plannedRemainingIncome: plannedRemainingIncome,
      plannedRemainingExpense: plannedRemainingExpense,
      averageDailyDiscretionaryExpense: averageDailyDiscretionaryExpense,
      projectedRemainingDiscretionaryExpense:
          projectedRemainingDiscretionaryExpense,
    );
  }

  /// 2. Dự báo nguy cơ vượt ngân sách
  List<BudgetForecast> calculateBudgetForecasts({
    required List<Budget> currentMonthBudgets,
    required List<Category> categories,
    required List<AppTransaction> currentMonthTx,
    DateTime? refDate,
  }) {
    final today = refDate ?? DateTime.now();
    final daysInMonth = DateTime(today.year, today.month + 1, 0).day;
    final elapsedDays = today.day.clamp(1, daysInMonth);

    // Tính tổng expense theo categoryId từ danh sách giao dịch tháng hiện tại
    final Map<String, double> spentByCategory = {};
    for (final tx in currentMonthTx.where((t) => t.type == 'expense')) {
      spentByCategory[tx.categoryId] =
          (spentByCategory[tx.categoryId] ?? 0) + tx.amount;
    }

    final results = <BudgetForecast>[];

    for (final budget in currentMonthBudgets) {
      final category = categories.firstWhere(
        (c) => c.categoryId == budget.categoryId,
        orElse: () => Category(
          categoryId: budget.categoryId,
          userId: '',
          name: 'Danh mục',
          type: 'expense',
          icon: 'category',
          color: 0xFF9E9E9E,
        ),
      );

      final spent = spentByCategory[budget.categoryId] ?? 0;
      final limit = budget.limit;
      final dailyPace = spent / elapsedDays;
      final percentUsed = limit <= 0 ? 0.0 : spent / limit;

      BudgetForecastStatus status;
      DateTime? estimatedExceededDate;
      int? daysToLimit;

      if (spent >= limit) {
        status = BudgetForecastStatus.exceeded;
        daysToLimit = 0;
        estimatedExceededDate = null;
      } else if (dailyPace > 0 && limit > 0) {
        final daysNeededDouble = (limit - spent) / dailyPace;
        daysToLimit = daysNeededDouble.ceil();
        estimatedExceededDate = today.add(Duration(days: daysToLimit));

        final inCurrentMonth = estimatedExceededDate.month == today.month &&
            estimatedExceededDate.year == today.year;

        if (inCurrentMonth) {
          status = BudgetForecastStatus.atRisk;
        } else if (percentUsed >= kBudgetWarningRatio) {
          status = BudgetForecastStatus.warning;
        } else {
          status = BudgetForecastStatus.safe;
        }
      } else {
        if (percentUsed >= kBudgetWarningRatio) {
          status = BudgetForecastStatus.warning;
        } else {
          status = BudgetForecastStatus.safe;
        }
      }

      results.add(BudgetForecast(
        budgetId: budget.budgetId,
        categoryId: budget.categoryId,
        categoryName: category.name,
        limit: limit,
        spent: spent,
        dailyPace: dailyPace,
        percentUsed: percentUsed,
        estimatedExceededDate: estimatedExceededDate,
        daysToLimit: daysToLimit,
        status: status,
      ));
    }

    return results;
  }

  /// 3. Phát hiện chi tiêu bất thường
  /// [preceding3MonthsTx] chứa 3 danh sách giao dịch của 3 tháng hoàn chỉnh trước đó (ví dụ [tháng -3, tháng -2, tháng -1])
  List<SpendingAnomaly> detectSpendingAnomalies({
    required List<AppTransaction> currentMonthTx,
    required List<List<AppTransaction>> preceding3MonthsTx,
    required List<Category> categories,
    DateTime? refDate,
  }) {
    final today = refDate ?? DateTime.now();
    final daysInCurrentMonth = DateTime(today.year, today.month + 1, 0).day;
    final elapsedDays = today.day.clamp(1, daysInCurrentMonth);

    // Tính chi tiêu tháng hiện tại theo categoryId
    final Map<String, double> currentByCategory = {};
    for (final tx in currentMonthTx.where((t) => t.type == 'expense')) {
      currentByCategory[tx.categoryId] =
          (currentByCategory[tx.categoryId] ?? 0) + tx.amount;
    }

    // Tính chi tiêu của 3 tháng trước theo categoryId
    final List<Map<String, double>> historyByCategoryMaps = [];
    for (final monthTx in preceding3MonthsTx) {
      final Map<String, double> monthMap = {};
      for (final tx in monthTx.where((t) => t.type == 'expense')) {
        monthMap[tx.categoryId] = (monthMap[tx.categoryId] ?? 0) + tx.amount;
      }
      historyByCategoryMaps.add(monthMap);
    }

    final anomalies = <SpendingAnomaly>[];

    currentByCategory.forEach((catId, currentSpend) {
      int monthsWithHistory = 0;
      double totalHistoricalSpend = 0;

      for (final monthMap in historyByCategoryMaps) {
        final val = monthMap[catId] ?? 0;
        if (val > 0) {
          monthsWithHistory++;
          totalHistoricalSpend += val;
        }
      }

      // Yêu cầu tối thiểu 2 tháng lịch sử có chi tiêu
      if (monthsWithHistory < 2) return;

      final averageMonthlySpend = totalHistoricalSpend / monthsWithHistory;
      final expectedSpendToDate =
          (averageMonthlySpend * elapsedDays) / daysInCurrentMonth;
      final excessAmount = currentSpend - expectedSpendToDate;

      // Điều kiện bất thường: > 30% kỳ vọng VÀ chênh lệch tuyệt đối >= 100.000đ
      if (currentSpend > expectedSpendToDate * kAnomalyThresholdRatio &&
          excessAmount >= kMinAnomalyAmountVnd) {
        final catName = categories
            .firstWhere(
              (c) => c.categoryId == catId,
              orElse: () => Category(
                categoryId: catId,
                userId: '',
                name: 'Danh mục',
                type: 'expense',
                icon: 'category',
                color: 0xFF9E9E9E,
              ),
            )
            .name;

        final excessRatio = expectedSpendToDate > 0
            ? (currentSpend / expectedSpendToDate)
            : 1.0;
        final severity = excessRatio >= kAnomalyCriticalRatio
            ? IssueSeverity.critical
            : IssueSeverity.warning;

        anomalies.add(SpendingAnomaly(
          categoryId: catId,
          categoryName: catName,
          currentSpend: currentSpend,
          expectedSpendToDate: expectedSpendToDate,
          averageMonthlySpend: averageMonthlySpend,
          excessAmount: excessAmount,
          excessRatio: excessRatio,
          monthsOfHistory: monthsWithHistory,
          severity: severity,
        ));
      }
    });

    return anomalies;
  }

  /// 4. Tổng hợp điểm sức khỏe tài chính & chống trùng phạt (Deduplicated Health Score)
  int calculateOverallHealthScore({
    required MonthEndForecast monthEndForecast,
    required List<BudgetForecast> budgetForecasts,
    required List<SpendingAnomaly> anomalies,
    required List<FinancialIssue> issues,
    required List<HealthScoreDeduction> outDeductions,
  }) {
    double score = 100;
    outDeductions.clear();

    // 1. Phạt dự báo số dư cuối tháng
    if (monthEndForecast.hasEnoughData) {
      if (monthEndForecast.projectedEndBalance < 0) {
        outDeductions.add(const HealthScoreDeduction(
          reason: 'Dự báo âm số dư cuối tháng',
          points: 25,
        ));
        score -= 25;
      } else if (monthEndForecast.projectedEndBalance < 1000000) {
        outDeductions.add(const HealthScoreDeduction(
          reason: 'Dự báo số dư cuối tháng thấp (< 1.000.000đ)',
          points: 10,
        ));
        score -= 10;
      }
    }

    // Khống chế trừ điểm phạt theo danh mục để tránh double penalty (tối đa 20 điểm/danh mục)
    final Map<String, int> categoryDeductionMap = {};

    // 2. Ngân sách vượt / nguy cơ
    for (final b in budgetForecasts) {
      if (b.status == BudgetForecastStatus.exceeded) {
        const pts = 15;
        categoryDeductionMap[b.categoryId] =
            (categoryDeductionMap[b.categoryId] ?? 0) + pts;
        outDeductions.add(HealthScoreDeduction(
          reason: 'Ngân sách "${b.categoryName}" đã vượt hạn mức',
          points: pts,
          categoryId: b.categoryId,
        ));
      } else if (b.status == BudgetForecastStatus.atRisk) {
        const pts = 10;
        categoryDeductionMap[b.categoryId] =
            (categoryDeductionMap[b.categoryId] ?? 0) + pts;
        outDeductions.add(HealthScoreDeduction(
          reason: 'Ngân sách "${b.categoryName}" có nguy cơ vượt trong tháng',
          points: pts,
          categoryId: b.categoryId,
        ));
      } else if (b.status == BudgetForecastStatus.warning) {
        const pts = 5;
        categoryDeductionMap[b.categoryId] =
            (categoryDeductionMap[b.categoryId] ?? 0) + pts;
        outDeductions.add(HealthScoreDeduction(
          reason: 'Ngân sách "${b.categoryName}" gần chạm hạn mức (>=80%)',
          points: pts,
          categoryId: b.categoryId,
        ));
      }
    }

    // 3. Chi tiêu bất thường (Anomaly) — giảm phạt nếu danh mục đã dính penalty ngân sách
    for (final a in anomalies) {
      final currentCategoryDeduction = categoryDeductionMap[a.categoryId] ?? 0;
      int basePts = a.severity == IssueSeverity.critical ? 15 : 8;

      // Cap tối đa 20 điểm phạt cho cùng 1 danh mục
      final maxAllowedPts = (20 - currentCategoryDeduction).clamp(0, 20);
      final actualPts = basePts.clamp(0, maxAllowedPts);

      if (actualPts > 0) {
        categoryDeductionMap[a.categoryId] =
            currentCategoryDeduction + actualPts;
        outDeductions.add(HealthScoreDeduction(
          reason:
              'Chi tiêu bất thường danh mục "${a.categoryName}" (${(a.excessRatio * 100 - 100).round()}% over)',
          points: actualPts,
          categoryId: a.categoryId,
        ));
      }
    }

    // Trừ tổng các khoản của danh mục
    for (final pts in categoryDeductionMap.values) {
      score -= pts;
    }

    // 4. Các vấn đề tài chính khác (FinancialIssue không trùng với category anomalies)
    for (final issue in issues) {
      // Chỉ tính nếu chưa được gộp
      if (issue.category == IssueCategory.lowSaving) {
        final pts = issue.severity == IssueSeverity.critical ? 15 : 8;
        outDeductions.add(HealthScoreDeduction(
          reason: issue.title,
          points: pts,
        ));
        score -= pts;
      }
    }

    return score.clamp(0, 100).round();
  }

  /// 5. Tạo FinancialInsightSummary hoàn chỉnh
  FinancialInsightSummary generateSummary({
    required List<Wallet> activeWallets,
    required List<Budget> currentMonthBudgets,
    required List<Category> categories,
    required List<AppTransaction> currentMonthTx,
    required List<List<AppTransaction>> preceding3MonthsTx,
    required double monthlyIncome,
    required List<FinancialIssue> issues,
    List<RecurringTransactionSchedule>? recurringSchedules,
    DateTime? refDate,
  }) {
    final today = refDate ?? DateTime.now();

    final monthEnd = calculateMonthEndForecast(
      activeWallets: activeWallets,
      currentMonthTx: currentMonthTx,
      recurringSchedules: recurringSchedules,
      refDate: today,
    );

    final budgetForecasts = calculateBudgetForecasts(
      currentMonthBudgets: currentMonthBudgets,
      categories: categories,
      currentMonthTx: currentMonthTx,
      refDate: today,
    );

    final anomalies = detectSpendingAnomalies(
      currentMonthTx: currentMonthTx,
      preceding3MonthsTx: preceding3MonthsTx,
      categories: categories,
      refDate: today,
    );

    final deductions = <HealthScoreDeduction>[];
    final healthScore = calculateOverallHealthScore(
      monthEndForecast: monthEnd,
      budgetForecasts: budgetForecasts,
      anomalies: anomalies,
      issues: issues,
      outDeductions: deductions,
    );

    final String healthRating;
    if (healthScore >= 80) {
      healthRating = 'Tốt';
    } else if (healthScore >= 60) {
      healthRating = 'Cần theo dõi';
    } else if (healthScore >= 40) {
      healthRating = 'Có rủi ro';
    } else {
      healthRating = 'Cần hành động ngay';
    }

    return FinancialInsightSummary(
      monthEndForecast: monthEnd,
      budgetForecasts: budgetForecasts,
      anomalies: anomalies,
      issues: issues,
      healthScore: healthScore,
      healthRating: healthRating,
      deductions: deductions,
      referenceDate: today,
    );
  }
}
