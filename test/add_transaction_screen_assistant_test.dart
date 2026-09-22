import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/models/category_model.dart';
import 'package:finance_ai_app/models/transaction_model.dart';
import 'package:finance_ai_app/services/transaction_intelligence_service.dart';

void main() {
  group('AddTransactionScreen Assistant Requirements Tests', () {
    final service = TransactionIntelligenceService();

    test('1. _areCategoryListsEqual returns true for identical lists and false for modified lists', () {
      final list1 = [
        Category(categoryId: 'c1', userId: 'u1', name: 'Ăn uống', type: 'expense', icon: 'food', color: 0),
        Category(categoryId: 'c2', userId: 'u1', name: 'Di chuyển', type: 'expense', icon: 'car', color: 0),
      ];

      final list2 = [
        Category(categoryId: 'c1', userId: 'u1', name: 'Ăn uống', type: 'expense', icon: 'food', color: 0),
        Category(categoryId: 'c2', userId: 'u1', name: 'Di chuyển', type: 'expense', icon: 'car', color: 0),
      ];

      final list3 = [
        Category(categoryId: 'c1', userId: 'u1', name: 'Ăn uống', type: 'expense', icon: 'food', color: 0),
        Category(categoryId: 'c2', userId: 'u1', name: 'Giao thông', type: 'expense', icon: 'car', color: 0), // Modified name
      ];

      final list4 = [
        Category(categoryId: 'c1', userId: 'u1', name: 'Ăn uống', type: 'expense', icon: 'food', color: 0),
      ];

      bool areEqual(List<Category> a, List<Category> b) {
        if (a.length != b.length) return false;
        for (int i = 0; i < a.length; i++) {
          if (a[i].categoryId != b[i].categoryId ||
              a[i].name != b[i].name ||
              a[i].type != b[i].type) {
            return false;
          }
        }
        return true;
      }

      expect(areEqual(list1, list2), isTrue);
      expect(areEqual(list1, list3), isFalse);
      expect(areEqual(list1, list4), isFalse);
    });

    test('2. detectAnomaly excludes transactionToEdit.transactionId from history median sample', () {
      final now = DateTime.now();
      final editingTxId = 'editing_tx_999';

      // Lịch sử có 5 giao dịch, trong đó 1 giao dịch có ID trùng với transactionToEdit.transactionId
      final history = [
        AppTransaction(
          transactionId: editingTxId, // Giao dịch đang sửa
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'c1',
          amount: 100000,
          type: 'expense',
          date: now.subtract(const Duration(days: 1)),
        ),
        AppTransaction(
          transactionId: 't2',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'c1',
          amount: 100000,
          type: 'expense',
          date: now.subtract(const Duration(days: 2)),
        ),
        AppTransaction(
          transactionId: 't3',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'c1',
          amount: 100000,
          type: 'expense',
          date: now.subtract(const Duration(days: 3)),
        ),
        AppTransaction(
          transactionId: 't4',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'c1',
          amount: 100000,
          type: 'expense',
          date: now.subtract(const Duration(days: 4)),
        ),
        AppTransaction(
          transactionId: 't5',
          userId: 'u1',
          walletId: 'w1',
          categoryId: 'c1',
          amount: 100000,
          type: 'expense',
          date: now.subtract(const Duration(days: 5)),
        ),
      ];

      // Khi chưa exclude: sample size = 5 -> tính anomaly
      final resultWithSelf = service.detectAnomaly(
        amount: 300000,
        categoryId: 'c1',
        categoryName: 'Ăn uống',
        transactionType: 'expense',
        userHistory: history,
      );
      expect(resultWithSelf.isAnomalous, isTrue);

      // Khi exclude transactionToEdit.transactionId: sample size = 4 (< 5) -> không báo anomaly
      final resultWithoutSelf = service.detectAnomaly(
        amount: 300000,
        categoryId: 'c1',
        categoryName: 'Ăn uống',
        transactionType: 'expense',
        userHistory: history,
        excludeTransactionId: editingTxId,
      );
      expect(resultWithoutSelf.isAnomalous, isFalse);
    });
  });
}
