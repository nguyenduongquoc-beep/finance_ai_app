import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// Biểu đồ cột đơn giản hiển thị xu hướng chi tiêu 3 tháng gần nhất
class SpendingTrendBarChart extends StatelessWidget {
  final List<double> amounts; // 3 tháng (cũ -> mới)
  final List<String> monthLabels; // VD: ['Tháng 8', 'Tháng 9', 'Tháng 10']

  const SpendingTrendBarChart({
    super.key,
    required this.amounts,
    required this.monthLabels,
  });

  String _compact(double v) {
    if (v <= 0) return '0';
    if (v >= 1000000) {
      final m = v / 1000000;
      return m % 1 == 0 ? '${m.toInt()}M' : '${m.toStringAsFixed(1)}M';
    }
    if (v >= 1000) {
      final k = v / 1000;
      return k % 1 == 0 ? '${k.toInt()}K' : '${k.toStringAsFixed(1)}K';
    }
    return v.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    if (amounts.isEmpty || monthLabels.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(child: Text('Chưa có dữ liệu xu hướng')),
      );
    }

    final maxVal = amounts.reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(amounts.length, (i) {
          final isCurrent = i == amounts.length - 1;
          final heightFactor = maxVal <= 0 ? 0.1 : (amounts[i] / maxVal).clamp(0.12, 1.0);

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _compact(amounts[i]),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                  color: isCurrent ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 48,
                height: 90 * heightFactor,
                decoration: BoxDecoration(
                  color: isCurrent ? AppColors.accentGreen : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                monthLabels[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  color: isCurrent ? AppColors.textPrimary : AppColors.textSecondary,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}
