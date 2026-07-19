/// ============================================================
/// CATEGORY MODEL
/// Firestore collection: categories/{categoryId}
/// ============================================================
class Category {
  final String categoryId;
  final String userId;
  final String name;
  final String type; // income | expense
  final String icon; // tên icon (map sang IconData ở UI layer)
  final int color; // giá trị màu ARGB

  Category({
    required this.categoryId,
    required this.userId,
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
  });

  factory Category.fromMap(Map<String, dynamic> map, String id) {
    return Category(
      categoryId: id,
      userId: map['userId'] ?? '',
      name: map['name'] ?? '',
      type: map['type'] ?? 'expense',
      icon: map['icon'] ?? 'category',
      color: map['color'] ?? 0xFF9E9E9E,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'name': name,
      'type': type,
      'icon': icon,
      'color': color,
    };
  }
}
