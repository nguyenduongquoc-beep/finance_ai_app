import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/models/category_model.dart';
import 'package:finance_ai_app/models/transaction_model.dart';
import 'package:finance_ai_app/services/transaction_intelligence_service.dart';
import 'package:finance_ai_app/utils/category_utils.dart';

void main() {
  group('areCategoryListsEqual (shared production helper)', () {
    Category makeCat(String id, String name, String type) => Category(
          categoryId: id,
          userId: 'u1',
          name: name,
          type: type,
          icon: 'icon',
          color: 0,
        );

    test('1. Returns true for identical lists – StreamBuilder should NOT re-trigger intelligence check', () {
      final list1 = [makeCat('c1', 'Ăn uống', 'expense'), makeCat('c2', 'Di chuyển', 'expense')];
      final list2 = [makeCat('c1', 'Ăn uống', 'expense'), makeCat('c2', 'Di chuyển', 'expense')];
      expect(areCategoryListsEqual(list1, list2), isTrue);
    });

    test('2. Returns false when a category name changes – StreamBuilder SHOULD re-trigger intelligence check', () {
      final list1 = [makeCat('c1', 'Ăn uống', 'expense'), makeCat('c2', 'Di chuyển', 'expense')];
      final list2 = [makeCat('c1', 'Ăn uống', 'expense'), makeCat('c2', 'Giao thông', 'expense')];
      expect(areCategoryListsEqual(list1, list2), isFalse);
    });

    test('3. Returns false when list lengths differ', () {
      final list1 = [makeCat('c1', 'Ăn uống', 'expense'), makeCat('c2', 'Di chuyển', 'expense')];
      final list2 = [makeCat('c1', 'Ăn uống', 'expense')];
      expect(areCategoryListsEqual(list1, list2), isFalse);
    });

    test('4. Returns false when a category ID changes', () {
      final list1 = [makeCat('c1', 'Ăn uống', 'expense')];
      final list2 = [makeCat('c99', 'Ăn uống', 'expense')];
      expect(areCategoryListsEqual(list1, list2), isFalse);
    });

    test('5. Returns false when category type changes', () {
      final list1 = [makeCat('c1', 'Lương', 'income')];
      final list2 = [makeCat('c1', 'Lương', 'expense')];
      expect(areCategoryListsEqual(list1, list2), isFalse);
    });

    test('6. Returns true for two empty lists', () {
      expect(areCategoryListsEqual([], []), isTrue);
    });

    test('7. Returns false when a new category is appended (simulates Firestore stream adding category)', () {
      final list1 = [makeCat('c1', 'Ăn uống', 'expense')];
      final list2 = [makeCat('c1', 'Ăn uống', 'expense'), makeCat('c2', 'Mua sắm', 'expense')];
      expect(areCategoryListsEqual(list1, list2), isFalse);
    });

    test('8. Returns false when order changes (same items, different order)', () {
      final list1 = [makeCat('c1', 'Ăn uống', 'expense'), makeCat('c2', 'Di chuyển', 'expense')];
      final list2 = [makeCat('c2', 'Di chuyển', 'expense'), makeCat('c1', 'Ăn uống', 'expense')];
      expect(areCategoryListsEqual(list1, list2), isFalse);
    });


    test('9. Guard logic: unchanged emit does not trigger, changed emit triggers exactly once', () {
      // Simulate the StreamBuilder guard logic from AddTransactionScreen:
      //   if (!areCategoryListsEqual(_allCategories, newCategories)) {
      //     _allCategories = newCategories;
      //     // schedule _runIntelligenceCheck
      //   }
      var cachedCategories = <Category>[];
      int intelligenceCheckCount = 0;

      void simulateStreamEmit(List<Category> newCategories) {
        if (!areCategoryListsEqual(cachedCategories, newCategories)) {
          cachedCategories = newCategories;
          intelligenceCheckCount++;
        }
      }

      final cats1 = [makeCat('c1', 'Ăn uống', 'expense')];
      final cats1Clone = [makeCat('c1', 'Ăn uống', 'expense')];
      final cats2 = [makeCat('c1', 'Ăn uống', 'expense'), makeCat('c2', 'Mua sắm', 'expense')];

      // First emit – new data – should trigger
      simulateStreamEmit(cats1);
      expect(intelligenceCheckCount, 1);

      // Same data re-emitted – should NOT trigger (no infinite rebuild loop)
      simulateStreamEmit(cats1Clone);
      expect(intelligenceCheckCount, 1);

      // Actually changed data – should trigger exactly once more
      simulateStreamEmit(cats2);
      expect(intelligenceCheckCount, 2);

      // Same changed data re-emitted – should NOT trigger
      simulateStreamEmit([makeCat('c1', 'Ăn uống', 'expense'), makeCat('c2', 'Mua sắm', 'expense')]);
      expect(intelligenceCheckCount, 2);
    });
  });

  group('detectAnomaly excludeTransactionId', () {
    final service = TransactionIntelligenceService();

    test('10. Excludes transactionToEdit.transactionId from history median sample', () {
      final now = DateTime.now();
      const editingTxId = 'editing_tx_999';

      final history = [
        AppTransaction(
          transactionId: editingTxId,
          userId: 'u1', walletId: 'w1', categoryId: 'c1',
          amount: 100000, type: 'expense',
          date: now.subtract(const Duration(days: 1)),
        ),
        AppTransaction(
          transactionId: 't2',
          userId: 'u1', walletId: 'w1', categoryId: 'c1',
          amount: 100000, type: 'expense',
          date: now.subtract(const Duration(days: 2)),
        ),
        AppTransaction(
          transactionId: 't3',
          userId: 'u1', walletId: 'w1', categoryId: 'c1',
          amount: 100000, type: 'expense',
          date: now.subtract(const Duration(days: 3)),
        ),
        AppTransaction(
          transactionId: 't4',
          userId: 'u1', walletId: 'w1', categoryId: 'c1',
          amount: 100000, type: 'expense',
          date: now.subtract(const Duration(days: 4)),
        ),
        AppTransaction(
          transactionId: 't5',
          userId: 'u1', walletId: 'w1', categoryId: 'c1',
          amount: 100000, type: 'expense',
          date: now.subtract(const Duration(days: 5)),
        ),
      ];

      // Without exclusion: sample size = 5 → anomaly detected
      final resultWithSelf = service.detectAnomaly(
        amount: 300000,
        categoryId: 'c1',
        categoryName: 'Ăn uống',
        transactionType: 'expense',
        userHistory: history,
      );
      expect(resultWithSelf.isAnomalous, isTrue);

      // With exclusion: sample size = 4 (< 5) → no anomaly
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
