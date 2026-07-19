import 'package:flutter/material.dart';
import '../models/quick_template.dart';
import '../utils/formatters.dart';

/// A selectable chip displaying a quick transaction template.
/// Calls [onSelect] with the chosen [QuickTemplate] when tapped.
class QuickTemplateChip extends StatelessWidget {
  final QuickTemplate template;
  final void Function(QuickTemplate) onSelect;

  const QuickTemplateChip({
    super.key,
    required this.template,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final isIncome = template.type == 'income';
    final color = isIncome ? const Color(0xFF2ECC71) : const Color(0xFFE74C3C);

    return GestureDetector(
      onTap: () => onSelect(template),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          border: Border.all(color: color.withOpacity(0.40)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isIncome ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  template.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                Text(
                  AppFormatters.currency(template.amount),
                  style: TextStyle(
                    fontSize: 11,
                    color: color.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
