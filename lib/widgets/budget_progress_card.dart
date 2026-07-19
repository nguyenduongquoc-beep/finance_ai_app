import 'package:flutter/material.dart';
import 'package:percent_indicator/percent_indicator.dart';
import '../models/budget_model.dart';
import '../models/category_model.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';

/// Widget hiển thị tiến độ ngân sách theo danh mục (thanh progress bar)
/// Cảnh báo màu đỏ khi vượt 90% (isNearLimit) hoặc vượt hạn mức (isOverBudget)
class BudgetProgressCard extends StatelessWidget {
  final Budget budget;
  final Category? category;
  final VoidCallback? onTap;

  const BudgetProgressCard({
    super.key,
    required this.budget,
    this.category,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isOver = budget.isOverBudget;
    final isNear = budget.isNearLimit;

    final Color barColor = isOver
        ? AppColors.expense
        : isNear
            ? AppColors.warning
            : AppColors.primary;

    final Color bgColor = isOver
        ? AppColors.expense.withOpacity(0.06)
        : isNear
            ? AppColors.warning.withOpacity(0.06)
            : Colors.white;

    final Border? cardBorder = isOver
        ? Border.all(color: AppColors.expense.withOpacity(0.4), width: 1.5)
        : isNear
            ? Border.all(color: AppColors.warning.withOpacity(0.4), width: 1.5)
            : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: cardBorder,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Category icon or initial
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: barColor.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        (category?.name ?? 'K').substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: barColor,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                category?.name ?? 'Danh mục',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 15),
                              ),
                            ),
                            if (isOver)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.expense,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('Vượt hạn mức!',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold)),
                              )
                            else if (isNear)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.warning,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text('Sắp vượt!',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${AppFormatters.currency(budget.spent)} / ${AppFormatters.currency(budget.limit)}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearPercentIndicator(
                lineHeight: 10,
                percent: budget.percentUsed.clamp(0.0, 1.0),
                backgroundColor: Colors.grey.shade200,
                progressColor: barColor,
                barRadius: const Radius.circular(6),
                padding: EdgeInsets.zero,
                animation: true,
                animationDuration: 600,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${(budget.percentUsed * 100).round()}% đã sử dụng',
                    style: TextStyle(
                        fontSize: 12,
                        color: barColor,
                        fontWeight: isNear || isOver ? FontWeight.w600 : FontWeight.normal),
                  ),
                  Text(
                    'Còn lại: ${AppFormatters.currency((budget.limit - budget.spent).clamp(0, double.infinity))}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
              if (isOver || isNear) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      isOver ? Icons.error_outline : Icons.warning_amber_outlined,
                      size: 14,
                      color: barColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isOver
                          ? 'Đã vượt hạn mức ${AppFormatters.currency(budget.spent - budget.limit)}'
                          : 'Hãy cẩn thận — chỉ còn ${AppFormatters.currency(budget.limit - budget.spent)} trong ngân sách',
                      style: TextStyle(fontSize: 11, color: barColor),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
