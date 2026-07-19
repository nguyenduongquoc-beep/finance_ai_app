import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../utils/constants.dart';

/// Biểu đồ cột: Thu / Chi theo tháng
class IncomeExpenseBarChart extends StatelessWidget {
  final List<double> incomeByMonth; // 6 tháng gần nhất
  final List<double> expenseByMonth;
  final List<String> monthLabels;

  const IncomeExpenseBarChart({
    super.key,
    required this.incomeByMonth,
    required this.expenseByMonth,
    required this.monthLabels,
  });

  @override
  Widget build(BuildContext context) {
    final maxVal = [...incomeByMonth, ...expenseByMonth].fold<double>(0, (a, b) => a > b ? a : b);
    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          maxY: maxVal == 0 ? 1 : maxVal * 1.2,
          barGroups: List.generate(monthLabels.length, (i) {
            return BarChartGroupData(x: i, barRods: [
              BarChartRodData(toY: incomeByMonth[i], color: AppColors.income, width: 8),
              BarChartRodData(toY: expenseByMonth[i], color: AppColors.expense, width: 8),
            ]);
          }),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= monthLabels.length) return const SizedBox();
                  return Text(monthLabels[i], style: const TextStyle(fontSize: 11));
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),

          gridData: const FlGridData(show: false),
        ),
      ),
    );
  }
}

/// Biểu đồ tròn: Tỷ lệ chi tiêu theo danh mục
class CategoryPieChart extends StatelessWidget {
  final Map<String, double> categoryTotals; // tên danh mục -> tổng tiền
  final List<Color> colors;

  const CategoryPieChart({super.key, required this.categoryTotals, required this.colors});

  @override
  Widget build(BuildContext context) {
    final total = categoryTotals.values.fold<double>(0, (a, b) => a + b);
    final entries = categoryTotals.entries.toList();

    return SizedBox(
      height: 220,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: List.generate(entries.length, (i) {
                  final percent = total == 0 ? 0 : (entries[i].value / total * 100);
                  return PieChartSectionData(
                    value: entries[i].value,
                    color: colors[i % colors.length],
                    title: '${percent.round()}%',
                    radius: 55,
                    titleStyle: const TextStyle(
                        fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, i) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(width: 10, height: 10, color: colors[i % colors.length]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(entries[i].key,
                            style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
