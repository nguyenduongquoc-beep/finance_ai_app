/// ============================================================
/// SAVING GOAL MODEL
/// Firestore collection: savingGoals/{goalId}
/// (Mở rộng từ mục tiêu tiết kiệm trong hồ sơ người dùng)
/// ============================================================
class SavingGoal {
  final String goalId;
  final String userId;
  final String name; // vd: "Laptop"
  final double targetAmount; // vd: 25.000.000
  final double savedAmount; // vd: 8.000.000
  final int months; // số tháng để đạt mục tiêu
  final DateTime createdAt;

  SavingGoal({
    required this.goalId,
    required this.userId,
    required this.name,
    required this.targetAmount,
    this.savedAmount = 0,
    required this.months,
    required this.createdAt,
  });

  double get percentComplete =>
      targetAmount == 0 ? 0 : (savedAmount / targetAmount).clamp(0, 1);

  double get monthlyRequired =>
      months == 0 ? 0 : (targetAmount - savedAmount) / months;

  double get dailyRequired => monthlyRequired / 30;

  factory SavingGoal.fromMap(Map<String, dynamic> map, String id) {
    return SavingGoal(
      goalId: id,
      userId: map['userId'] ?? '',
      name: map['name'] ?? '',
      targetAmount: (map['targetAmount'] ?? 0).toDouble(),
      savedAmount: (map['savedAmount'] ?? 0).toDouble(),
      months: map['months'] ?? 1,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'targetAmount': targetAmount,
      'savedAmount': savedAmount,
      'months': months,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
