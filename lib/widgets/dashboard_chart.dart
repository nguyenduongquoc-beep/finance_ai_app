import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';

/// Biểu đồ cột: Thu / Chi theo tháng (hỗ trợ chạm chọn tháng)
class IncomeExpenseBarChart extends StatelessWidget {
  final List<double> incomeByMonth; // 6 tháng
  final List<double> expenseByMonth;
  final List<String> monthLabels;
  final int selectedIndex; // tháng đang được chọn
  final void Function(int monthIndex) onMonthTap; // callback khi chạm cột

  const IncomeExpenseBarChart({
    super.key,
    required this.incomeByMonth,
    required this.expenseByMonth,
    required this.monthLabels,
    required this.selectedIndex,
    required this.onMonthTap,
  });

  @override
  Widget build(BuildContext context) {
    final maxVal = [...incomeByMonth, ...expenseByMonth].fold<double>(0, (a, b) => a > b ? a : b);
    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          maxY: maxVal == 0 ? 1 : maxVal * 1.2,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              tooltipRoundedRadius: 8,
              tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final isIncome = rodIndex == 0;
                final rawValue = (isIncome ? incomeByMonth : expenseByMonth)[groupIndex] * 1e6;
                return BarTooltipItem(
                  AppFormatters.currency(rawValue),
                  TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                );
              },
            ),
            touchCallback: (event, response) {
              if (event is FlTapUpEvent && response?.spot != null) {
                onMonthTap(response!.spot!.touchedBarGroupIndex);
              }
            },
          ),
          barGroups: List.generate(monthLabels.length, (i) {
            final isSelected = i == selectedIndex;
            return BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: incomeByMonth[i],
                color: isSelected
                    ? AppColors.income
                    : AppColors.income.withOpacity(0.45),
                width: 10,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                borderSide: isSelected
                    ? const BorderSide(color: Colors.white, width: 1.5)
                    : BorderSide.none,
              ),
              BarChartRodData(
                toY: expenseByMonth[i],
                color: isSelected
                    ? AppColors.expense
                    : AppColors.expense.withOpacity(0.45),
                width: 10,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                borderSide: isSelected
                    ? const BorderSide(color: Colors.white, width: 1.5)
                    : BorderSide.none,
              ),
            ]);
          }),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= monthLabels.length) return const SizedBox();
                  final isSelected = i == selectedIndex;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      monthLabels[i],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
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

    // Sắp xếp các danh mục giảm dần theo giá trị chi tiêu
    entries.sort((a, b) => b.value.compareTo(a.value));

    // Tính phần trăm bằng thuật toán "Largest Remainder Method"
    final List<int> percentages = List.filled(entries.length, 0);
    if (total > 0) {
      final List<double> rawPercentages = entries.map((e) => (e.value / total) * 100).toList();
      final List<int> floors = rawPercentages.map((p) => p.floor()).toList();
      final List<double> remainders = List.generate(entries.length, (i) => rawPercentages[i] - floors[i]);

      final int sumFloors = floors.fold<int>(0, (a, b) => a + b);
      final int difference = 100 - sumFloors;

      // Sắp xếp index theo phần dư (remainder) giảm dần
      final List<int> indices = List.generate(entries.length, (i) => i);
      indices.sort((a, b) {
        // Nếu phần dư khác nhau thì sắp xếp theo phần dư giảm dần
        final cmp = remainders[b].compareTo(remainders[a]);
        if (cmp != 0) return cmp;
        // Nếu phần dư bằng nhau, ưu tiên danh mục có giá trị lớn hơn để có kết quả ổn định
        return entries[b].value.compareTo(entries[a].value);
      });

      // Cộng thêm 1% cho đúng số danh mục có phần dư lớn nhất
      for (int i = 0; i < difference; i++) {
        if (i < indices.length) {
          floors[indices[i]] += 1;
        }
      }

      for (int i = 0; i < entries.length; i++) {
        percentages[i] = floors[i];
      }
    }

    return SizedBox(
      height: 220,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 40,
                    sections: List.generate(entries.length, (i) {
                      return PieChartSectionData(
                        value: entries[i].value,
                        color: colors[i % colors.length],
                        title: '', // Bỏ hiển thị chữ/số % trên lát để gọn gàng
                        radius: 55,
                      );
                    }),
                  ),
                ),
                // Center text "Tổng 100%"
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Tổng', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    const Text('100%', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final percent = percentages[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colors[i % colors.length],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(entries[i].key,
                            style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$percent%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
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
