/// ============================================================
/// TRANSACTION MODEL
/// Firestore collection: transactions/{transactionId}
/// ============================================================
class AppTransaction {
  final String transactionId;
  final String userId;
  final String walletId;
  final String categoryId;
  final double amount;
  final String type; // income | expense
  final String? note;
  final String? image; // URL ảnh hóa đơn trên Firebase Storage
  final String? location;
  final DateTime date;

  AppTransaction({
    required this.transactionId,
    required this.userId,
    required this.walletId,
    required this.categoryId,
    required this.amount,
    required this.type,
    this.note,
    this.image,
    this.location,
    required this.date,
  });

  factory AppTransaction.fromMap(Map<String, dynamic> map, String id) {
    return AppTransaction(
      transactionId: id,
      userId: map['userId'] ?? '',
      walletId: map['walletId'] ?? '',
      categoryId: map['categoryId'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      type: map['type'] ?? 'expense',
      note: map['note'],
      image: map['image'],
      location: map['location'],
      date: map['date'] != null ? DateTime.parse(map['date']) : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'walletId': walletId,
      'categoryId': categoryId,
      'amount': amount,
      'type': type,
      'note': note,
      'image': image,
      'location': location,
      'date': date.toIso8601String(),
    };
  }
}
