import 'package:flutter/material.dart';
import 'package:percent_indicator/percent_indicator.dart';
import '../models/budget_model.dart';
import '../models/category_model.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';

/// Widget hiển thị hạn mức chi tiêu chi tiết theo danh mục (khớp mockup Figma)
class BudgetProgressCard extends StatelessWidget {
  final Budget budget;
  final double spentAmount;
  final Category? category;
  final VoidCallback? onTap;

  const BudgetProgressCard({
    super.key,
    required this.budget,
    required this.spentAmount,
    this.category,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isOver = budget.isOverBudget(spentAmount);
    final isNear = budget.isNearLimit(spentAmount);
    final percent = budget.percentUsed(spentAmount);

    final Color barColor = isOver
        ? AppColors.expense
        : isNear
            ? const Color(0xFFF59E0B)
            : const Color(0xFF10B981);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOver
              ? AppColors.expense.withValues(alpha: 0.3)
              : isNear
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.3)
                  : Colors.grey.shade200,
          width: isOver || isNear ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      category?.name ?? 'Danh mục',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${AppFormatters.number(spentAmount)} VNĐ/ ${AppFormatters.number(budget.limit)} VNĐ',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearPercentIndicator(
                lineHeight: 8,
                percent: percent.clamp(0.0, 1.0),
                backgroundColor: Colors.grey.shade100,
                progressColor: barColor,
                barRadius: const Radius.circular(4),
                padding: EdgeInsets.zero,
                animation: true,
                animationDuration: 600,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Đã dùng ${(percent * 100).round()}%',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (isOver)
                    Text(
                      'Đã vượt ${AppFormatters.currency(spentAmount - budget.limit)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.expense,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
