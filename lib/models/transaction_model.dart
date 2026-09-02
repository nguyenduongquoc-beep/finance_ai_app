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
  final String? note;
  final String? image; // Path/URL ảnh hóa đơn
  final String? location;
  final DateTime date;

  AppTransaction({
    required this.transactionId,
    required this.userId,
    required this.walletId,
    required this.categoryId,
    required this.amount,
    required this.type,
    this.toWalletId,
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
      toWalletId: map['toWalletId'],
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
      'toWalletId': toWalletId,
      'note': note,
      'image': image,
      'location': location,
      'date': date.toIso8601String(),
    };
  }
}
