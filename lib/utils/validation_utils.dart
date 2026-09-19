import '../services/firestore_service.dart';

enum BudgetValidationStatus {
  ok,
  nearLimit,
  exceeded,
}

class CategoryBudgetValidationResult {
  final BudgetValidationStatus status;
  final int percent;

  const CategoryBudgetValidationResult({
    required this.status,
    required this.percent,
  });
}

class ValidationUtils {
  /// Returns true if the [amount] exceeds the balance of the given [walletId].
  static Future<bool> exceedsWalletBalance({
    required String walletId,
    required double amount,
    required FirestoreService firestoreService,
  }) async {
    final balance = await firestoreService.getWalletBalance(walletId);
    return amount > balance;
  }

  /// Checks the budget status for a category based on projected spend (currentSpent + amount).
  /// Returns nearLimit if 80% <= projectedSpent <= limit, exceeded if projectedSpent > limit, or ok otherwise.
  static Future<CategoryBudgetValidationResult> checkCategoryBudgetStatus({
    required String userId,
    required String categoryId,
    required double amount,
    required FirestoreService firestoreService,
  }) async {
    final budget = await firestoreService.getCategoryBudget(userId, categoryId);
    if (budget == null || budget.limit <= 0) {
      return const CategoryBudgetValidationResult(
        status: BudgetValidationStatus.ok,
        percent: 0,
      );
    }
    final currentSpent = await firestoreService.getCategorySpentThisMonth(userId, categoryId);
    final projectedSpent = currentSpent + amount;
    final percent = (projectedSpent / budget.limit * 100).round();

    if (projectedSpent > budget.limit) {
      return CategoryBudgetValidationResult(
        status: BudgetValidationStatus.exceeded,
        percent: percent,
      );
    } else if (projectedSpent >= budget.limit * 0.8) {
      return CategoryBudgetValidationResult(
        status: BudgetValidationStatus.nearLimit,
        percent: percent,
      );
    }
    return CategoryBudgetValidationResult(
      status: BudgetValidationStatus.ok,
      percent: percent,
    );
  }

  /// Returns true if adding [amount] to the spent amount of the budget for
  /// [categoryId] would exceed the budget limit.
  static Future<bool> exceedsCategoryBudget({
    required String userId,
    required String categoryId,
    required double amount,
    required FirestoreService firestoreService,
  }) async {
    final result = await checkCategoryBudgetStatus(
      userId: userId,
      categoryId: categoryId,
      amount: amount,
      firestoreService: firestoreService,
    );
    return result.status == BudgetValidationStatus.exceeded;
  }
}
