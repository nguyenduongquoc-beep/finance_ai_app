/// ============================================================
/// BUDGET MODEL
/// Firestore collection: budgets/{budgetId}
/// ============================================================
class Budget {
  final String budgetId;
  final String userId;
  final String categoryId;
  final double limit;
  final String month; // định dạng "MM/yyyy"
  final double spent; // tính toán tại client hoặc lưu cache

  Budget({
    required this.budgetId,
    required this.userId,
    required this.categoryId,
    required this.limit,
    required this.month,
    this.spent = 0,
  });

  double get percentUsed => limit == 0 ? 0 : (spent / limit).clamp(0, 1.5);
  bool get isOverBudget => spent > limit;
  bool get isNearLimit => percentUsed >= 0.9 && !isOverBudget;

  factory Budget.fromMap(Map<String, dynamic> map, String id) {
    return Budget(
      budgetId: id,
      userId: map['userId'] ?? '',
      categoryId: map['categoryId'] ?? '',
      limit: (map['limit'] ?? 0).toDouble(),
      month: map['month'] ?? '',
      spent: (map['spent'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'categoryId': categoryId,
      'limit': limit,
      'month': month,
      'spent': spent,
    };
  }
}
