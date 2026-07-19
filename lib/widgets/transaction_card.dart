import 'package:flutter/material.dart';
import '../models/transaction_model.dart';
import '../models/category_model.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';

/// Widget hiển thị một dòng giao dịch trong danh sách
class TransactionCard extends StatelessWidget {
  final AppTransaction transaction;
  final Category? category;
  final VoidCallback? onTap;

  const TransactionCard({
    super.key,
    required this.transaction,
    this.category,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isIncome = transaction.type == 'income';
    final color = isIncome ? AppColors.income : AppColors.expense;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(Icons.receipt_long, color: color),
        ),
        title: Text(
          category?.name ?? 'Không rõ danh mục',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: transaction.note != null && transaction.note!.isNotEmpty
            ? Text(transaction.note!, maxLines: 1, overflow: TextOverflow.ellipsis)
            : null,
        trailing: Text(
          '${isIncome ? '+' : '-'}${AppFormatters.number(transaction.amount)} đ',
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
