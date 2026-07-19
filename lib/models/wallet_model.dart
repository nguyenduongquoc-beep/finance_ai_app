/// ============================================================
/// WALLET MODEL
/// Firestore collection: wallets/{walletId}
/// ============================================================
class Wallet {
  final String walletId;
  final String userId;
  final String walletName;
  final double balance;
  final String type; // cash, bank, eWallet, other
  final DateTime createdAt;

  Wallet({
    required this.walletId,
    required this.userId,
    required this.walletName,
    required this.balance,
    required this.type,
    required this.createdAt,
  });

  factory Wallet.fromMap(Map<String, dynamic> map, String id) {
    return Wallet(
      walletId: id,
      userId: map['userId'] ?? '',
      walletName: map['walletName'] ?? '',
      balance: (map['balance'] ?? 0).toDouble(),
      type: map['type'] ?? 'cash',
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'walletName': walletName,
      'balance': balance,
      'type': type,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  Wallet copyWith({String? walletName, double? balance, String? type}) {
    return Wallet(
      walletId: walletId,
      userId: userId,
      walletName: walletName ?? this.walletName,
      balance: balance ?? this.balance,
      type: type ?? this.type,
      createdAt: createdAt,
    );
  }
}
