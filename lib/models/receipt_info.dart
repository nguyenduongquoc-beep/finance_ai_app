class ReceiptInfo {
  final String merchant;
  final double total;
  final DateTime? date;
  final String? taxId;
  final List<ReceiptItem>? items;

  ReceiptInfo({
    required this.merchant,
    required this.total,
    this.date,
    this.taxId,
    this.items,
  });

  factory ReceiptInfo.fromJson(Map<String, dynamic> json) {
    return ReceiptInfo(
      merchant: json['merchant'] as String? ?? '',
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      date: json['date'] != null ? DateTime.parse(json['date'] as String) : null,
      taxId: json['taxId'] as String?,
      items: json['items'] != null
          ? (json['items'] as List)
              .map((e) => ReceiptItem.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'merchant': merchant,
      'total': total,
      'date': date?.toIso8601String(),
      'taxId': taxId,
      'items': items?.map((e) => e.toJson()).toList(),
    };
  }
}

class ReceiptItem {
  final String description;
  final double amount;

  ReceiptItem({required this.description, required this.amount});

  factory ReceiptItem.fromJson(Map<String, dynamic> json) {
    return ReceiptItem(
      description: json['description'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'description': description,
      'amount': amount,
    };
  }
}
