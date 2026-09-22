/// ============================================================
/// CATEGORY SUGGESTION MODEL
/// Chứa thông tin gợi ý danh mục từ pure Dart matching
/// ============================================================
class CategorySuggestion {
  final String categoryId;
  final String categoryName;
  final int confidence; // 0–100
  final String reason;
  final String source; // keyword | history | ocr | none

  const CategorySuggestion({
    required this.categoryId,
    required this.categoryName,
    required this.confidence,
    required this.reason,
    required this.source,
  });

  factory CategorySuggestion.none() {
    return const CategorySuggestion(
      categoryId: '',
      categoryName: '',
      confidence: 0,
      reason: '',
      source: 'none',
    );
  }

  @override
  String toString() {
    return 'CategorySuggestion(categoryId: $categoryId, categoryName: $categoryName, confidence: $confidence, reason: $reason, source: $source)';
  }
}
