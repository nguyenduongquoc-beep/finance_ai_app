/// ============================================================
/// USER MODEL
/// Firestore collection: users/{uid}
/// ============================================================
class AppUser {
  final String uid;
  final String name;
  final String email;
  final String? avatar;
  final double monthlyIncome;
  final String? savingGoal;
  final String? occupation;
  final DateTime createdAt;

  AppUser({
    required this.uid,
    required this.name,
    required this.email,
    this.avatar,
    this.monthlyIncome = 0,
    this.savingGoal,
    this.occupation,
    required this.createdAt,
  });

  factory AppUser.fromMap(Map<String, dynamic> map, String uid) {
    return AppUser(
      uid: uid,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      avatar: map['avatar'],
      monthlyIncome: (map['monthlyIncome'] ?? 0).toDouble(),
      savingGoal: map['savingGoal'],
      occupation: map['occupation'],
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'avatar': avatar,
      'monthlyIncome': monthlyIncome,
      'savingGoal': savingGoal,
      'occupation': occupation,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  AppUser copyWith({
    String? name,
    String? avatar,
    double? monthlyIncome,
    String? savingGoal,
    String? occupation,
  }) {
    return AppUser(
      uid: uid,
      name: name ?? this.name,
      email: email,
      avatar: avatar ?? this.avatar,
      monthlyIncome: monthlyIncome ?? this.monthlyIncome,
      savingGoal: savingGoal ?? this.savingGoal,
      occupation: occupation ?? this.occupation,
      createdAt: createdAt,
    );
  }
}
