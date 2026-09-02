import '../services/firestore_service.dart';

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

  /// Returns true if adding [amount] to the spent amount of the budget for
  /// [categoryId] would exceed the budget limit.
  static Future<bool> exceedsCategoryBudget({
    required String userId,
    required String categoryId,
    required double amount,
    required FirestoreService firestoreService,
  }) async {
    final budget = await firestoreService.getCategoryBudget(userId, categoryId);
    if (budget == null) return false; // No budget defined for this category.
    final currentSpent = await firestoreService.getCategorySpentThisMonth(userId, categoryId);
    final projectedSpent = currentSpent + amount;
    return projectedSpent > budget.limit;
  }
}
