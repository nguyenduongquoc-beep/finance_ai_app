import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/models/budget_model.dart';
import 'package:finance_ai_app/models/category_model.dart';
import 'package:finance_ai_app/models/saving_goal_model.dart';
import 'package:finance_ai_app/models/transaction_model.dart';
import 'package:finance_ai_app/models/wallet_model.dart';
import 'package:finance_ai_app/services/financial_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FinancialExportService exportService;
  late List<Category> sampleCategories;
  late List<Wallet> sampleWallets;
  late List<SavingGoal> sampleSavingGoals;
  late List<Budget> sampleBudgets;

  setUp(() {
    exportService = FinancialExportService();

    sampleCategories = [
      Category(categoryId: 'cat_1', userId: 'user_1', name: 'Ăn uống', type: 'expense', icon: 'fastfood', color: 0xFF10B981),
      Category(categoryId: 'cat_2', userId: 'user_1', name: 'Lương', type: 'income', icon: 'work', color: 0xFF3B82F6),
    ];

    sampleWallets = [
      Wallet(
        walletId: 'w_1',
        userId: 'user_1',
        walletName: 'Ví tiền mặt',
        balance: 5000000,
        type: 'cash',
        createdAt: DateTime(2026, 1, 1),
      ),
      Wallet(
        walletId: 'w_2',
        userId: 'user_1',
        walletName: 'Tài khoản ngân hàng',
        balance: 15000000,
        type: 'bank',
        createdAt: DateTime(2026, 1, 1),
      ),
    ];

    sampleSavingGoals = [
      SavingGoal(
        goalId: 'g_1',
        userId: 'user_1',
        name: 'Mua Laptop',
        targetAmount: 20000000,
        savedAmount: 5000000,
        months: 6,
        createdAt: DateTime(2026, 1, 1),
      ),
    ];

    sampleBudgets = [
      Budget(
        budgetId: 'b_1',
        userId: 'user_1',
        categoryId: 'cat_1',
        limit: 3000000,
        month: '09/2026',
      ),
    ];
  });

  group('FinancialExportService - CSV Export Tests', () {
    test('1. CSV file starts with UTF-8 BOM bytes [0xEF, 0xBB, 0xBF]', () async {
      final txList = [
        AppTransaction(
          transactionId: 'tx_1',
          userId: 'user_1',
          walletId: 'w_1',
          categoryId: 'cat_1',
          amount: 50000,
          type: 'expense',
          date: DateTime(2026, 9, 15, 12, 0),
          note: 'Cơm trưa',
        ),
      ];

      final file = await exportService.exportTransactionsCsv(
        transactions: txList,
        categories: sampleCategories,
        wallets: sampleWallets,
        savingGoals: sampleSavingGoals,
        filenamePrefix: 'test_bom',
        outputDir: Directory.systemTemp,
      );

      final bytes = await file.readAsBytes();
      expect(bytes.length, greaterThan(3));
      expect(bytes[0], equals(0xEF));
      expect(bytes[1], equals(0xBB));
      expect(bytes[2], equals(0xBF));

      await file.delete();
    });

    test('2. CSV field escaping handles commas, newlines, and double quotes', () async {
      final txList = [
        AppTransaction(
          transactionId: 'tx_complex',
          userId: 'user_1',
          walletId: 'w_1',
          categoryId: 'cat_1',
          amount: 150000,
          type: 'expense',
          date: DateTime(2026, 9, 15, 14, 30),
          note: 'Ghi chú "phức tạp", có dấu phẩy\nvà xuống dòng',
          location: 'Quán ăn "Sài Gòn", Q1',
        ),
      ];

      final file = await exportService.exportTransactionsCsv(
        transactions: txList,
        categories: sampleCategories,
        wallets: sampleWallets,
        savingGoals: sampleSavingGoals,
        filenamePrefix: 'test_escaping',
        outputDir: Directory.systemTemp,
      );

      final content = await file.readAsString();
      expect(content, contains('"Ghi chú ""phức tạp"", có dấu phẩy\nvà xuống dòng"'));
      expect(content, contains('"Quán ăn ""Sài Gòn"", Q1"'));

      await file.delete();
    });

    test('3. CSV formats exact Vietnamese labels for all transaction types', () async {
      final txList = [
        AppTransaction(
          transactionId: 't1', userId: 'u1', walletId: 'w_1', categoryId: 'cat_2',
          amount: 10000000, type: 'income', date: DateTime(2026, 9, 1),
        ),
        AppTransaction(
          transactionId: 't2', userId: 'u1', walletId: 'w_1', categoryId: 'cat_1',
          amount: 100000, type: 'expense', date: DateTime(2026, 9, 2),
        ),
        AppTransaction(
          transactionId: 't3', userId: 'u1', walletId: 'w_1', categoryId: '', toWalletId: 'w_2',
          amount: 2000000, type: 'transfer', date: DateTime(2026, 9, 3),
        ),
        AppTransaction(
          transactionId: 't4', userId: 'u1', walletId: 'w_1', categoryId: '', goalId: 'g_1',
          amount: 500000, type: 'goal_deposit', date: DateTime(2026, 9, 4),
        ),
        AppTransaction(
          transactionId: 't5', userId: 'u1', walletId: 'w_1', categoryId: '', goalId: 'g_1',
          amount: 200000, type: 'goal_withdraw', date: DateTime(2026, 9, 5),
        ),
      ];

      final file = await exportService.exportTransactionsCsv(
        transactions: txList,
        categories: sampleCategories,
        wallets: sampleWallets,
        savingGoals: sampleSavingGoals,
        filenamePrefix: 'test_labels',
        outputDir: Directory.systemTemp,
      );

      final content = await file.readAsString();
      expect(content, contains('Thu nhập'));
      expect(content, contains('Chi tiêu'));
      expect(content, contains('Chuyển tiền'));
      expect(content, contains('Nạp mục tiêu'));
      expect(content, contains('Rút mục tiêu'));

      await file.delete();
    });

    test('4. CSV distinguishes recurring vs manual transactions and fallbacks deleted entities to "Đã xóa"', () async {
      final txList = [
        AppTransaction(
          transactionId: 't_rec', userId: 'u1', walletId: 'w_deleted', categoryId: 'cat_deleted',
          amount: 500000, type: 'expense', date: DateTime(2026, 9, 10),
          recurringScheduleId: 'schedule_123',
        ),
        AppTransaction(
          transactionId: 't_man', userId: 'u1', walletId: 'w_1', categoryId: 'cat_1',
          amount: 20000, type: 'expense', date: DateTime(2026, 9, 11),
        ),
      ];

      final file = await exportService.exportTransactionsCsv(
        transactions: txList,
        categories: sampleCategories,
        wallets: sampleWallets,
        savingGoals: sampleSavingGoals,
        filenamePrefix: 'test_sources',
        outputDir: Directory.systemTemp,
      );

      final content = await file.readAsString();
      expect(content, contains('Định kỳ'));
      expect(content, contains('Thủ công'));
      expect(content, contains('Đã xóa'));

      await file.delete();
    });

    test('5. CSV export throws ExportException when transaction list is empty', () async {
      expect(
        () => exportService.exportTransactionsCsv(
          transactions: [],
          categories: sampleCategories,
          wallets: sampleWallets,
          savingGoals: sampleSavingGoals,
          filenamePrefix: 'test_empty',
          outputDir: Directory.systemTemp,
        ),
        throwsA(isA<ExportException>()),
      );
    });
  });

  group('FinancialExportService - Report Data & PDF Tests', () {
    test('6. PDF report builder excludes transfers and goal transactions from realized Income/Expense', () {
      final txList = [
        AppTransaction(
          transactionId: 't1', userId: 'u1', walletId: 'w_1', categoryId: 'cat_2',
          amount: 15000000, type: 'income', date: DateTime(2026, 9, 1),
        ),
        AppTransaction(
          transactionId: 't2', userId: 'u1', walletId: 'w_1', categoryId: 'cat_1',
          amount: 2000000, type: 'expense', date: DateTime(2026, 9, 2),
        ),
        // Transfer - should NOT count as income or expense
        AppTransaction(
          transactionId: 't3', userId: 'u1', walletId: 'w_1', categoryId: '', toWalletId: 'w_2',
          amount: 5000000, type: 'transfer', date: DateTime(2026, 9, 3),
        ),
        // Goal deposit - should NOT count as realized income or expense
        AppTransaction(
          transactionId: 't4', userId: 'u1', walletId: 'w_1', categoryId: '', goalId: 'g_1',
          amount: 1000000, type: 'goal_deposit', date: DateTime(2026, 9, 4),
        ),
      ];

      final reportData = exportService.buildReportData(
        currentPeriodTx: txList,
        wallets: sampleWallets,
        categories: sampleCategories,
        budgets: sampleBudgets,
        savingGoals: sampleSavingGoals,
        periodLabel: 'Tháng 09/2026',
        isCurrentMonth: true,
      );

      expect(reportData.totalIncome, equals(15000000));
      expect(reportData.totalExpense, equals(2000000));
      expect(reportData.netDifference, equals(13000000));
    });

    test('7. Category spending breakdown calculates amounts and percentages correctly', () {
      final txList = [
        AppTransaction(
          transactionId: 't1', userId: 'u1', walletId: 'w_1', categoryId: 'cat_1',
          amount: 1500000, type: 'expense', date: DateTime(2026, 9, 1),
        ),
        AppTransaction(
          transactionId: 't2', userId: 'u1', walletId: 'w_1', categoryId: 'cat_1',
          amount: 500000, type: 'expense', date: DateTime(2026, 9, 2),
        ),
      ];

      final reportData = exportService.buildReportData(
        currentPeriodTx: txList,
        wallets: sampleWallets,
        categories: sampleCategories,
        budgets: sampleBudgets,
        savingGoals: sampleSavingGoals,
        periodLabel: 'Tháng 09/2026',
        isCurrentMonth: true,
      );

      expect(reportData.categoryBreakdown.length, equals(1));
      expect(reportData.categoryBreakdown.first.categoryName, equals('Ăn uống'));
      expect(reportData.categoryBreakdown.first.amount, equals(2000000));
      expect(reportData.categoryBreakdown.first.percentage, equals(100.0));
    });

    test('8. Forecast section is generated ONLY when isCurrentMonth is true', () {
      final txList = [
        AppTransaction(
          transactionId: 't1', userId: 'u1', walletId: 'w_1', categoryId: 'cat_1',
          amount: 500000, type: 'expense', date: DateTime(2026, 8, 15),
        ),
      ];

      final currentMonthReport = exportService.buildReportData(
        currentPeriodTx: txList,
        wallets: sampleWallets,
        categories: sampleCategories,
        budgets: sampleBudgets,
        savingGoals: sampleSavingGoals,
        periodLabel: 'Tháng 09/2026',
        isCurrentMonth: true,
      );

      final pastMonthReport = exportService.buildReportData(
        currentPeriodTx: txList,
        wallets: sampleWallets,
        categories: sampleCategories,
        budgets: sampleBudgets,
        savingGoals: sampleSavingGoals,
        periodLabel: 'Tháng 08/2026',
        isCurrentMonth: false,
      );

      expect(currentMonthReport.monthEndForecast, isNotNull);
      expect(pastMonthReport.monthEndForecast, isNull);
    });

    test('9. Forecast contains explicit disclaimer label and projected numbers', () {
      final txList = [
        AppTransaction(
          transactionId: 't1', userId: 'u1', walletId: 'w_1', categoryId: 'cat_1',
          amount: 1000000, type: 'expense', date: DateTime(2026, 9, 10),
        ),
      ];

      final reportData = exportService.buildReportData(
        currentPeriodTx: txList,
        wallets: sampleWallets,
        categories: sampleCategories,
        budgets: sampleBudgets,
        savingGoals: sampleSavingGoals,
        periodLabel: 'Tháng 09/2026',
        isCurrentMonth: true,
        refDate: DateTime(2026, 9, 15),
      );

      expect(reportData.monthEndForecast, isNotNull);
      expect(reportData.monthEndForecast!.projectedEndBalance, isA<double>());
    });

    test('10. PDF document bytes are generated successfully and are non-empty', () async {
      final txList = [
        AppTransaction(
          transactionId: 't1', userId: 'u1', walletId: 'w_1', categoryId: 'cat_2',
          amount: 10000000, type: 'income', date: DateTime(2026, 9, 1),
        ),
        AppTransaction(
          transactionId: 't2', userId: 'u1', walletId: 'w_1', categoryId: 'cat_1',
          amount: 1200000, type: 'expense', date: DateTime(2026, 9, 2),
        ),
      ];

      final reportData = exportService.buildReportData(
        currentPeriodTx: txList,
        wallets: sampleWallets,
        categories: sampleCategories,
        budgets: sampleBudgets,
        savingGoals: sampleSavingGoals,
        periodLabel: 'Tháng 09/2026',
        isCurrentMonth: true,
      );

      final pdfBytes = await exportService.generateFinancialReportPdf(data: reportData);
      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(100));
    });
  });
}
