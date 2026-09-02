/// ============================================================
/// WALLET MODEL
/// Firestore collection: wallets/{walletId}
/// ============================================================
class Wallet {
  final String walletId;
  final String userId;
  final String walletName;
  final double balance; // Số dư HIỆN TẠI — cache, đồng bộ qua Transaction
  final double initialBalance; // Số dư ban đầu lúc tạo ví, không đổi sau đó
  final String type; // cash | bank | eWallet | other
  final String? description; // Optional, VD "Chi tiêu sinh hoạt"
  final String currency; // TODO: chưa hỗ trợ đa tiền tệ, mặc định VND — chỉ lưu trữ, không có UI đọc/hiển thị
  final bool isActive; // Mặc định true; false = đã ẩn (soft-delete)
  final DateTime createdAt;
  final DateTime? updatedAt;

  Wallet({
    required this.walletId,
    required this.userId,
    required this.walletName,
    required this.balance,
    double? initialBalance,
    required this.type,
    this.description,
    this.currency = 'VND',
    this.isActive = true,
    required this.createdAt,
    this.updatedAt,
  }) : initialBalance = initialBalance ?? balance;

  factory Wallet.fromMap(Map<String, dynamic> map, String id) {
    return Wallet(
      walletId: id,
      userId: map['userId'] ?? '',
      walletName: map['walletName'] ?? '',
      balance: (map['balance'] ?? 0).toDouble(),
      initialBalance: (map['initialBalance'] ?? map['balance'] ?? 0).toDouble(),
      type: map['type'] ?? 'cash',
      description: map['description'],
      currency: map['currency'] ?? 'VND',
      isActive: map['isActive'] ?? true, // ví cũ chưa có field này -> mặc định active
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null ? DateTime.parse(map['updatedAt']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'walletName': walletName,
      'balance': balance,
      'initialBalance': initialBalance,
      'type': type,
      'description': description,
      'currency': currency,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  Wallet copyWith({
    String? walletName,
    double? balance,
    String? type,
    String? description,
    bool? isActive,
  }) {
    return Wallet(
      walletId: walletId,
      userId: userId,
      walletName: walletName ?? this.walletName,
      balance: balance ?? this.balance,
      initialBalance: initialBalance,
      type: type ?? this.type,
      description: description ?? this.description,
      currency: currency,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
