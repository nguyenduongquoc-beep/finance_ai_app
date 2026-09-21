/// ============================================================
/// RECURRING TRANSACTION MODEL
/// Firestore collection: recurringTransactions/{scheduleId}
/// ============================================================
class RecurringTransactionSchedule {
  final String scheduleId;
  final String userId;
  final String type; // income | expense
  final String walletId;
  final String
      categoryId; // Bắt buộc cho expense, rỗng '' cho income nếu không áp dụng
  final double amount;
  final String? note;
  final String frequency; // weekly | monthly
  final DateTime startDate;
  final DateTime nextDueDate;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? lastProcessedKey; // VD: "2026-09-20"

  RecurringTransactionSchedule({
    required this.scheduleId,
    required this.userId,
    required this.type,
    required this.walletId,
    required this.categoryId,
    required this.amount,
    this.note,
    required this.frequency,
    required this.startDate,
    required this.nextDueDate,
    this.isActive = true,
    required this.createdAt,
    this.updatedAt,
    this.lastProcessedKey,
  }) {
    validateAmount(amount);
  }

  static void validateAmount(double amount) {
    if (amount <= 0 || amount.isNaN || amount.isInfinite) {
      throw ArgumentError(
          'Số tiền lặp định kỳ phải lớn hơn 0 và là số hợp lệ.');
    }
  }

  factory RecurringTransactionSchedule.fromMap(
      Map<String, dynamic> map, String id) {
    return RecurringTransactionSchedule(
      scheduleId: id,
      userId: map['userId'] ?? '',
      type: map['type'] ?? 'expense',
      walletId: map['walletId'] ?? '',
      categoryId: map['categoryId'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      note: map['note'],
      frequency: map['frequency'] ?? 'monthly',
      startDate: map['startDate'] != null
          ? DateTime.parse(map['startDate'])
          : DateTime.now(),
      nextDueDate: map['nextDueDate'] != null
          ? DateTime.parse(map['nextDueDate'])
          : DateTime.now(),
      isActive: map['isActive'] ?? true,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      updatedAt:
          map['updatedAt'] != null ? DateTime.parse(map['updatedAt']) : null,
      lastProcessedKey: map['lastProcessedKey'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'type': type,
      'walletId': walletId,
      'categoryId': categoryId,
      'amount': amount,
      'note': note,
      'frequency': frequency,
      'startDate': startDate.toIso8601String(),
      'nextDueDate': nextDueDate.toIso8601String(),
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
      'lastProcessedKey': lastProcessedKey,
    };
  }

  RecurringTransactionSchedule copyWith({
    String? type,
    String? walletId,
    String? categoryId,
    double? amount,
    String? note,
    String? frequency,
    DateTime? startDate,
    DateTime? nextDueDate,
    bool? isActive,
    DateTime? updatedAt,
    String? lastProcessedKey,
  }) {
    return RecurringTransactionSchedule(
      scheduleId: scheduleId,
      userId: userId,
      type: type ?? this.type,
      walletId: walletId ?? this.walletId,
      categoryId: categoryId ?? this.categoryId,
      amount: amount ?? this.amount,
      note: note ?? this.note,
      frequency: frequency ?? this.frequency,
      startDate: startDate ?? this.startDate,
      nextDueDate: nextDueDate ?? this.nextDueDate,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      lastProcessedKey: lastProcessedKey ?? this.lastProcessedKey,
    );
  }
}
