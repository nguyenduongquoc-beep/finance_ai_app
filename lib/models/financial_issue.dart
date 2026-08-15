/// ============================================================
/// FINANCIAL ISSUE MODEL
/// Một "vấn đề tài chính" đã phát hiện bằng ngưỡng (Dart thuần).
/// Dùng cho FinancialAnalyticsService — không lưu Firestore,
/// tính lại from scratch mỗi lần mở AiInsightScreen.
/// ============================================================
enum IssueSeverity { warning, critical } // vàng / đỏ

class FinancialIssue {
  final String title;           // VD: "Ăn uống tăng 32% so với tháng trước"
  final String description;     // câu mô tả ngắn, không cần AI viết
  final IssueSeverity severity;
  final String? categoryName;   // null nếu vấn đề không gắn 1 danh mục cụ thể (VD tỷ lệ tiết kiệm)
  final double? currentValue;   // giá trị hiện tại (số tiền hoặc %)
  final double? thresholdValue; // ngưỡng đã vi phạm

  FinancialIssue({
    required this.title,
    required this.description,
    required this.severity,
    this.categoryName,
    this.currentValue,
    this.thresholdValue,
  });
}
