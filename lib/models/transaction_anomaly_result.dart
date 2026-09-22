/// ============================================================
/// TRANSACTION ANOMALY RESULT MODEL
/// Kết quả phát hiện khoản chi bất thường từ pure Dart statistics
/// ============================================================
class TransactionAnomalyResult {
  final bool isAnomalous;
  final String severity; // info | warning | critical
  final double currentAmount;
  final double expectedAmount;
  final double ratio;
  final double difference;
  final String categoryName;
  final int historySampleSize;
  final String reason;

  const TransactionAnomalyResult({
    required this.isAnomalous,
    required this.severity,
    required this.currentAmount,
    required this.expectedAmount,
    required this.ratio,
    required this.difference,
    required this.categoryName,
    required this.historySampleSize,
    required this.reason,
  });

  factory TransactionAnomalyResult.normal() {
    return const TransactionAnomalyResult(
      isAnomalous: false,
      severity: 'info',
      currentAmount: 0.0,
      expectedAmount: 0.0,
      ratio: 1.0,
      difference: 0.0,
      categoryName: '',
      historySampleSize: 0,
      reason: '',
    );
  }

  @override
  String toString() {
    return 'TransactionAnomalyResult(isAnomalous: $isAnomalous, severity: $severity, currentAmount: $currentAmount, expectedAmount: $expectedAmount, ratio: $ratio, difference: $difference, categoryName: $categoryName, sampleSize: $historySampleSize, reason: $reason)';
  }
}
