class TrendResult {
  final List<double> monthlyAmounts; // order: oldest -> newest
  final String insight;
  final double? percentChange; // overall percent change from first to last month

  TrendResult({
    required this.monthlyAmounts,
    required this.insight,
    this.percentChange,
  });
}
