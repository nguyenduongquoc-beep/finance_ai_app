import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/trend_result.dart';
import '../utils/constants.dart';


class TrendChartCard extends StatelessWidget {
  final TrendResult trendResult;

  const TrendChartCard({Key? key, required this.trendResult}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (int i = 0; i < trendResult.monthlyAmounts.length; i++) {
      spots.add(FlSpot(i.toDouble(), trendResult.monthlyAmounts[i]));
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.show_chart, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Xu hướng chi tiêu 6 tháng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                lineTouchData: LineTouchData(enabled: false),
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: _calcYInterval(),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final month = value.toInt() + 1;
                        return Text('Th${month}', style: const TextStyle(fontSize: 10, color: Colors.black54));
                      },
                    ),
                  ),
                ),

                minX: 0,
                maxX: (trendResult.monthlyAmounts.length - 1).toDouble(),
                minY: 0,
                // maxY will be auto
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: AppColors.primary,
                    barWidth: 3,
                    dotData: FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(trendResult.insight, style: const TextStyle(height: 1.6, color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  double _calcYInterval() {
    final max = trendResult.monthlyAmounts.isEmpty ? 0 : trendResult.monthlyAmounts.reduce((a, b) => a > b ? a : b);
    final interval = (max / 4).ceilToDouble();
    return interval > 0 ? interval : 1;
  }
}
