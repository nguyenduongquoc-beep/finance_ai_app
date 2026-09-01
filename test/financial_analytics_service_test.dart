import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/models/category_model.dart';
import 'package:finance_ai_app/models/financial_issue.dart';
import 'package:finance_ai_app/models/transaction_model.dart';
import 'package:finance_ai_app/services/financial_analytics_service.dart';

void main() {
  group('FinancialAnalyticsService Tests', () {
    final analyticsService = FinancialAnalyticsService();

    final testCategories = [
      Category(
        categoryId: 'cat_food',
        userId: 'user_1',
        name: 'Ăn uống',
        type: 'expense',
        icon: 'restaurant',
        color: 0xFFD32F2F,
      ),
      Category(
        categoryId: 'cat_shopping',
        userId: 'user_1',
        name: 'Mua sắm',
        type: 'expense',
        icon: 'shopping_bag',
        color: 0xFFE64A19,
      ),
    ];

    test('detectIssues: category spike threshold (>30% spike)', () {
      final lastMonthTx = [
        AppTransaction(
          transactionId: 'tx1',
          userId: 'user_1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 100000,
          type: 'expense',
          date: DateTime.now().subtract(const Duration(days: 35)),
        ),
      ];

      final currentMonthTx = [
        AppTransaction(
          transactionId: 'tx2',
          userId: 'user_1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 140000, // Spike of 40% (>30%)
          type: 'expense',
          date: DateTime.now(),
        ),
      ];

      final issues = analyticsService.detectIssues(
        currentMonthTx: currentMonthTx,
        lastMonthTx: lastMonthTx,
        categories: testCategories,
        monthlyIncome: 1000000, // Large income to avoid other warnings
      );

      final foodSpikeIssue = issues.firstWhere((i) => i.title.contains('Ăn uống tăng'));
      expect(foodSpikeIssue, isNotNull);
      expect(foodSpikeIssue.severity, equals(IssueSeverity.warning));
      expect(foodSpikeIssue.currentValue, equals(140000.0));
    });

    test('detectIssues: category share threshold (>25% of income)', () {
      final lastMonthTx = <AppTransaction>[];

      final currentMonthTx = [
        AppTransaction(
          transactionId: 'tx3',
          userId: 'user_1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 300000, // 30% of monthly income (1,000,000)
          type: 'expense',
          date: DateTime.now(),
        ),
      ];

      final issues = analyticsService.detectIssues(
        currentMonthTx: currentMonthTx,
        lastMonthTx: lastMonthTx,
        categories: testCategories,
        monthlyIncome: 1000000,
      );

      final foodShareIssue = issues.firstWhere((i) => i.title.contains('chiếm 30% thu nhập'));
      expect(foodShareIssue, isNotNull);
      expect(foodShareIssue.severity, equals(IssueSeverity.warning));
    });

    test('detectIssues: low saving rate (<20%)', () {
      final lastMonthTx = <AppTransaction>[];

      final currentMonthTx = [
        AppTransaction(
          transactionId: 'tx4',
          userId: 'user_1',
          walletId: 'w1',
          categoryId: 'cat_food',
          amount: 850000, // 85% of monthly income, so savings rate is 15% (<20%)
          type: 'expense',
          date: DateTime.now(),
        ),
      ];

      final issues = analyticsService.detectIssues(
        currentMonthTx: currentMonthTx,
        lastMonthTx: lastMonthTx,
        categories: testCategories,
        monthlyIncome: 1000000,
      );

      final lowSavingIssue = issues.firstWhere((i) => i.title.contains('Tỷ lệ tiết kiệm chỉ đạt 15%'));
      expect(lowSavingIssue, isNotNull);
      expect(lowSavingIssue.severity, equals(IssueSeverity.warning));
    });

    test('calculateHealthScore', () {
      final issues = [
        FinancialIssue(
          title: 'Issue 1',
          description: 'Desc 1',
          severity: IssueSeverity.warning,
          category: IssueCategory.spike,
          confidenceScore: 80.0,
        ),
        FinancialIssue(
          title: 'Issue 2',
          description: 'Desc 2',
          severity: IssueSeverity.critical,
          category: IssueCategory.spike,
          confidenceScore: 80.0,
        ),
      ];

      // Starts at 100.
      // Warning subtracts 10, Critical subtracts 20.
      // 100 - 10 - 20 = 70.
      final score = analyticsService.calculateHealthScore(issues);
      expect(score, equals(70));
    });
  });
}
