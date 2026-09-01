import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// ============================================================
/// WEEKLY HEATMAP CARD
/// Hiển thị tần suất chi tiêu theo tuần dạng lưới 7 cột (T2-CN)
/// × N hàng (danh mục), mỗi ô tô màu theo mức độ 0-4.
/// Dữ liệu tính bằng Dart thuần (FinancialAnalyticsService),
/// hiện ngay không cần chờ AI.
/// ============================================================
class WeeklyHeatmapCard extends StatelessWidget {
  final Map<String, List<int>> heatmapData;

  const WeeklyHeatmapCard({super.key, required this.heatmapData});

  static const List<String> _dayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

  /// Ánh xạ mức 0-4 về opacity của AppColors.primary
  Color _cellColor(int level) {
    switch (level) {
      case 0:
        return AppColors.primary.withOpacity(0.06);
      case 1:
        return AppColors.primary.withOpacity(0.20);
      case 2:
        return AppColors.primary.withOpacity(0.40);
      case 3:
        return AppColors.primary.withOpacity(0.65);
      case 4:
        return AppColors.primary.withOpacity(0.90);
      default:
        return AppColors.primary.withOpacity(0.06);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (heatmapData.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
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
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.calendar_view_week_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Tần suất chi tiêu theo tuần',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Day labels row
          Row(
            children: [
              // Khoảng trống cho cột tên danh mục
              const SizedBox(width: 80),
              ...List.generate(7, (i) => Expanded(
                child: Center(
                  child: Text(
                    _dayLabels[i],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              )),
            ],
          ),
          const SizedBox(height: 6),

          // Heatmap rows
          ...heatmapData.entries.map((entry) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                // Tên danh mục
                SizedBox(
                  width: 80,
                  child: Text(
                    entry.key,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                // 7 ô heatmap
                ...List.generate(7, (i) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _cellColor(entry.value[i]),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                )),
              ],
            ),
          )),

          const SizedBox(height: 8),
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Ít', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
              const SizedBox(width: 4),
              ...List.generate(5, (i) => Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: _cellColor(i),
                  borderRadius: BorderRadius.circular(3),
                ),
              )),
              const SizedBox(width: 4),
              Text('Nhiều', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }
}
