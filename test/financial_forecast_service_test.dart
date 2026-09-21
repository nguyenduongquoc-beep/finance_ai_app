import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/models/budget_model.dart';
import 'package:finance_ai_app/models/category_model.dart';
import 'package:finance_ai_app/models/financial_forecast_result.dart';
import 'package:finance_ai_app/models/financial_issue.dart';
import 'package:finance_ai_app/models/transaction_model.dart';
import 'package:finance_ai_app/models/wallet_model.dart';
import 'package:finance_ai_app/services/financial_forecast_service.dart';

void main() {
  group('FinancialForecastService Unit Tests', () {
    final service = FinancialForecastService();
    final fixedRefDate =
        DateTime(2026, 9, 15); // Month with 30 days, elapsed 15, remaining 15

    final testCategories = [
      Category(
        categoryId: 'cat_food',
        userId: 'u1',
        name: 'Ăn uống',
        type: 'expense',
        icon: 'restaurant',
        color: 0xFFD32F2F,
      ),
      Category(
        categoryId: 'cat_shopping',
        userId: 'u1',
        name: 'Mua sắm',
        type: 'expense',
        icon: 'shopping_bag',
        color: 0xFFE64A19,
      ),
    ];

    final activeWallets = [
      Wallet(
        walletId: 'w1',
        userId: 'u1',
        walletName: 'Ví chính',
        balance: 10000000.0,
        type: 'bank',
        createdAt: DateTime(2026, 1, 1),
      ),
    ];

    // Test 1: Forecast loại trừ transfer, goal_deposit, goal_withdraw
    test(
        '1. Forecast excludes transfer, goal_deposit, goal_withdraw from income/expense',
        () {
      final transactions = [
        AppTransaction(
          transactionId: 't1',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 500000,
          type: 'expense',
          date: fixedRefDate,
        ),
        AppTransaction(
          transactionId: 't2',
          userId: 'u1',
          walletId: 'w1',
          categoryId: '',
          amount: 2000000,
          type: 'transfer',
          toWalletId: 'w2',
          date: fixedRefDate,
        ),
        AppTransaction(
          transactionId: 't3',
          userId: 'u1',
          walletId: 'w1',
          categoryId: '',
          amount: 1000000,
          type: 'goal_deposit',
          goalId: 'g1',
          date: fixedRefDate,
        ),
        AppTransaction(
          transactionId: 't4',
          userId: 'u1',
          walletId: 'w1',
          categoryId: '',
          amount: 500000,
          type: 'goal_withdraw',
          goalId: 'g1',
          date: fixedRefDate,
        ),
      ];

      final forecast = service.calculateMonthEndForecast(
        activeWallets: activeWallets,
        currentMonthTx: transactions,
        refDate: fixedRefDate,
      );

      expect(forecast.monthToDateExpense, equals(500000.0));
      expect(forecast.monthToDateIncome, equals(0.0));
    });

    // Test 2: Forecast cuối tháng khi có chi tiêu bình thường
    test('2. Month-end forecast with normal expenses', () {
      final transactions = [
        AppTransaction(
          transactionId: 't1',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 1500000, // 1,500,000 in 15 days -> 100,000/day
          type: 'expense',
          date: fixedRefDate,
        ),
      ];

      final forecast = service.calculateMonthEndForecast(
        activeWallets: activeWallets,
        currentMonthTx: transactions,
        refDate: fixedRefDate,
      );

      expect(forecast.hasEnoughData, isTrue);
      expect(forecast.elapsedDays, equals(15));
      expect(forecast.remainingDays, equals(15));
      expect(forecast.averageDailyExpense, equals(100000.0));
      expect(forecast.projectedRemainingExpense, equals(1500000.0));
      // Balance = 10,000,000 - 1,500,000 = 8,500,000
      expect(forecast.projectedEndBalance, equals(8500000.0));
    });

    // Test 3: Forecast khi chưa có giao dịch chi
    test('3. Forecast when zero expense transactions', () {
      final transactions = <AppTransaction>[];

      final forecast = service.calculateMonthEndForecast(
        activeWallets: activeWallets,
        currentMonthTx: transactions,
        refDate: fixedRefDate,
      );

      expect(forecast.hasEnoughData, isFalse);
      expect(forecast.monthToDateExpense, equals(0.0));
      expect(forecast.averageDailyExpense, equals(0.0));
      expect(forecast.projectedEndBalance, equals(10000000.0));
    });

    // Test 4: Budget đã vượt hạn mức
    test('4. Budget status exceeded when spent >= limit', () {
      final budgets = [
        Budget(
          budgetId: 'b1',
          userId: 'u1',
          categoryId: 'cat_food',
          limit: 1000000,
          month: '09/2026',
        ),
      ];

      final transactions = [
        AppTransaction(
          transactionId: 't1',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 1200000,
          type: 'expense',
          date: fixedRefDate,
        ),
      ];

      final forecasts = service.calculateBudgetForecasts(
        currentMonthBudgets: budgets,
        categories: testCategories,
        currentMonthTx: transactions,
        refDate: fixedRefDate,
      );

      expect(forecasts.length, equals(1));
      expect(forecasts.first.status, equals(BudgetForecastStatus.exceeded));
      expect(forecasts.first.spent, equals(1200000.0));
    });

    // Test 5: Budget có nguy cơ vượt trong tháng
    test(
        '5. Budget status atRisk when estimated overrun date is within current month',
        () {
      final budgets = [
        Budget(
          budgetId: 'b1',
          userId: 'u1',
          categoryId: 'cat_food',
          limit: 2000000,
          month: '09/2026',
        ),
      ];

      final transactions = [
        AppTransaction(
          transactionId: 't1',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount:
              1500000, // 1500k in 15 days -> 100k/day. Needs 5 more days to reach 2000k limit.
          type: 'expense',
          date: fixedRefDate,
        ),
      ];

      final forecasts = service.calculateBudgetForecasts(
        currentMonthBudgets: budgets,
        categories: testCategories,
        currentMonthTx: transactions,
        refDate: fixedRefDate,
      );

      expect(forecasts.first.status, equals(BudgetForecastStatus.atRisk));
      expect(forecasts.first.daysToLimit, equals(5));
      expect(forecasts.first.estimatedExceededDate?.day, equals(20));
    });

    // Test 6: Budget không có nguy cơ vượt (safe)
    test(
        '6. Budget status safe when spent is low and daily pace will not exceed limit',
        () {
      final budgets = [
        Budget(
          budgetId: 'b1',
          userId: 'u1',
          categoryId: 'cat_food',
          limit: 10000000,
          month: '09/2026',
        ),
      ];

      final transactions = [
        AppTransaction(
          transactionId: 't1',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount:
              500000, // 500k in 15 days -> ~33k/day. Projected month total ~1000k << 10000k limit.
          type: 'expense',
          date: fixedRefDate,
        ),
      ];

      final forecasts = service.calculateBudgetForecasts(
        currentMonthBudgets: budgets,
        categories: testCategories,
        currentMonthTx: transactions,
        refDate: fixedRefDate,
      );

      expect(forecasts.first.status, equals(BudgetForecastStatus.safe));
    });

    // Test 7: Anomaly khi chi hiện tại vượt kỳ vọng >30% và vượt ngưỡng 100,000đ
    test(
        '7. Spending anomaly detected when spend > expected * 1.30 and excess >= 100,000 VND',
        () {
      final currentTx = [
        AppTransaction(
          transactionId: 'tc',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 1500000, // In 15 days of 30-day month -> 1,500,000
          type: 'expense',
          date: fixedRefDate,
        ),
      ];

      // History 3 months: 1,000,000 per month avg
      // Expected spend to date (day 15 of 30) = 1,000,000 * 15 / 30 = 500,000
      // 1.30 * 500,000 = 650,000. Current spend 1,500,000 > 650,000 and excess 1,000,000 >= 100,000
      final m1 = [
        AppTransaction(
          transactionId: 'tm1',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 1000000,
          type: 'expense',
          date: fixedRefDate.subtract(const Duration(days: 30)),
        )
      ];
      final m2 = [
        AppTransaction(
          transactionId: 'tm2',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 1000000,
          type: 'expense',
          date: fixedRefDate.subtract(const Duration(days: 60)),
        )
      ];
      final m3 = [
        AppTransaction(
          transactionId: 'tm3',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 1000000,
          type: 'expense',
          date: fixedRefDate.subtract(const Duration(days: 90)),
        )
      ];

      final anomalies = service.detectSpendingAnomalies(
        currentMonthTx: currentTx,
        preceding3MonthsTx: [m3, m2, m1],
        categories: testCategories,
        refDate: fixedRefDate,
      );

      expect(anomalies.length, equals(1));
      expect(anomalies.first.categoryId, equals('cat_food'));
      expect(anomalies.first.excessAmount, equals(1000000.0));
    });

    // Test 8: Không anomaly khi lịch sử không đủ 2 tháng
    test('8. No anomaly if spending history is less than 2 months', () {
      final currentTx = [
        AppTransaction(
          transactionId: 'tc',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 1500000,
          type: 'expense',
          date: fixedRefDate,
        ),
      ];

      // Only 1 month of history
      final m1 = [
        AppTransaction(
          transactionId: 'tm1',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 1000000,
          type: 'expense',
          date: fixedRefDate.subtract(const Duration(days: 30)),
        )
      ];
      final m2 = <AppTransaction>[];
      final m3 = <AppTransaction>[];

      final anomalies = service.detectSpendingAnomalies(
        currentMonthTx: currentTx,
        preceding3MonthsTx: [m3, m2, m1],
        categories: testCategories,
        refDate: fixedRefDate,
      );

      expect(anomalies, isEmpty);
    });

    // Test 9: Không anomaly khi chỉ vượt rất ít (< 100,000 VND)
    test('9. No anomaly if excess amount is less than 100,000 VND threshold',
        () {
      // Historical avg per month = 100,000 VND -> expected to date = 50,000 VND.
      // Current spend = 70,000 VND (> 30% ratio 65,000), but excess is 20,000 VND < 100,000 VND.
      final currentTx = [
        AppTransaction(
          transactionId: 'tc',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 70000,
          type: 'expense',
          date: fixedRefDate,
        ),
      ];

      final m1 = [
        AppTransaction(
          transactionId: 'tm1',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 100000,
          type: 'expense',
          date: fixedRefDate.subtract(const Duration(days: 30)),
        )
      ];
      final m2 = [
        AppTransaction(
          transactionId: 'tm2',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 100000,
          type: 'expense',
          date: fixedRefDate.subtract(const Duration(days: 60)),
        )
      ];
      final m3 = <AppTransaction>[];

      final anomalies = service.detectSpendingAnomalies(
        currentMonthTx: currentTx,
        preceding3MonthsTx: [m3, m2, m1],
        categories: testCategories,
        refDate: fixedRefDate,
      );

      expect(anomalies, isEmpty);
    });

    // Test 10: Health score luôn nằm 0-100 & deduplicated
    test(
        '10. Health score remains between 0 and 100 with deduplicated category penalties',
        () {
      final forecast = service.calculateMonthEndForecast(
        activeWallets: activeWallets,
        currentMonthTx: [],
        refDate: fixedRefDate,
      );

      final budgetForecasts = [
        const BudgetForecast(
          budgetId: 'b1',
          categoryId: 'cat_food',
          categoryName: 'Ăn uống',
          limit: 1000000,
          spent: 1500000,
          dailyPace: 100000,
          percentUsed: 1.5,
          status: BudgetForecastStatus.exceeded,
        ),
      ];

      final anomalies = [
        const SpendingAnomaly(
          categoryId: 'cat_food',
          categoryName: 'Ăn uống',
          currentSpend: 1500000,
          expectedSpendToDate: 500000,
          averageMonthlySpend: 1000000,
          excessAmount: 1000000,
          excessRatio: 3.0,
          monthsOfHistory: 3,
          severity: IssueSeverity.critical,
        ),
      ];

      final deductions = <HealthScoreDeduction>[];
      final score = service.calculateOverallHealthScore(
        monthEndForecast: forecast,
        budgetForecasts: budgetForecasts,
        anomalies: anomalies,
        issues: [],
        outDeductions: deductions,
      );

      // cat_food exceeded = -15 pts. Anomaly is capped at max 20 per category so cat_food gets +5 pts extra max = 20 total.
      // Base 100 - 20 = 80 pts.
      expect(score, equals(80));
      expect(score, greaterThanOrEqualTo(0));
      expect(score, lessThanOrEqualTo(100));
    });

    // Test 11: DateTime tham chiếu cố định cho kết quả dự báo có thể lặp lại
    test('11. Deterministic calculation results with fixed reference DateTime',
        () {
      final ref1 = DateTime(2026, 9, 15);
      final ref2 = DateTime(2026, 9, 15);

      final tx = [
        AppTransaction(
          transactionId: 't1',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 3000000,
          type: 'expense',
          date: ref1,
        ),
      ];

      final res1 = service.calculateMonthEndForecast(
        activeWallets: activeWallets,
        currentMonthTx: tx,
        refDate: ref1,
      );

      final res2 = service.calculateMonthEndForecast(
        activeWallets: activeWallets,
        currentMonthTx: tx,
        refDate: ref2,
      );

      expect(res1.projectedEndBalance, equals(res2.projectedEndBalance));
      expect(res1.averageDailyExpense, equals(res2.averageDailyExpense));
      expect(res1.projectedRemainingExpense,
          equals(res2.projectedRemainingExpense));
    });
  });
}
