/// ============================================================
/// TRANSACTION MODEL
/// Firestore collection: transactions/{transactionId}
/// ============================================================
class AppTransaction {
  final String transactionId;
  final String userId;
  final String walletId; // Với type='transfer': VÍ NGUỒN
  final String categoryId; // Với type='transfer': để rỗng '' (không áp dụng)
  final double amount;
  final String type; // income | expense | transfer
  final String? toWalletId; // Chỉ có giá trị khi type == 'transfer' (VÍ ĐÍCH)
  final String?
      goalId; // MỚI — chỉ dùng khi type == 'goal_deposit' hoặc 'goal_withdraw'
  final String? note;
  final String? image; // Path/URL ảnh hóa đơn
  final String? location;
  final DateTime date;
  final String? recurringScheduleId; // MỚI — ID lịch giao dịch định kỳ (nếu có)
  final String? recurringOccurrenceKey; // MỚI — Khóa kỳ hạn, VD "2026-09-30"

  AppTransaction({
    required this.transactionId,
    required this.userId,
    required this.walletId,
    required this.categoryId,
    required this.amount,
    required this.type,
    this.toWalletId,
    this.goalId,
    this.note,
    this.image,
    this.location,
    required this.date,
    this.recurringScheduleId,
    this.recurringOccurrenceKey,
  });

  factory AppTransaction.fromMap(Map<String, dynamic> map, String id) {
    return AppTransaction(
      transactionId: id,
      userId: map['userId'] ?? '',
      walletId: map['walletId'] ?? '',
      categoryId: map['categoryId'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      type: map['type'] ?? 'expense',
      toWalletId: map['toWalletId'],
      goalId: map['goalId'],
      note: map['note'],
      image: map['image'],
      location: map['location'],
      date: map['date'] != null ? DateTime.parse(map['date']) : DateTime.now(),
      recurringScheduleId: map['recurringScheduleId'],
      recurringOccurrenceKey: map['recurringOccurrenceKey'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'walletId': walletId,
      'categoryId': categoryId,
      'amount': amount,
      'type': type,
      'toWalletId': toWalletId,
      'goalId': goalId,
      'note': note,
      'image': image,
      'location': location,
      'date': date.toIso8601String(),
      'recurringScheduleId': recurringScheduleId,
      'recurringOccurrenceKey': recurringOccurrenceKey,
    };
  }
}
