import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

  IconData _getCategoryIcon(String? iconName) {
    switch (iconName) {
      case 'work':
        return Icons.work_outline_rounded;
      case 'card_giftcard':
        return Icons.card_giftcard_rounded;
      case 'storefront':
        return Icons.storefront_rounded;
      case 'restaurant':
        return Icons.restaurant_rounded;
      case 'shopping_bag':
        return Icons.shopping_bag_outlined;
      case 'local_gas_station':
        return Icons.local_gas_station_rounded;
      case 'school':
        return Icons.school_outlined;
      case 'movie':
        return Icons.movie_outlined;
      case 'flight':
        return Icons.flight_takeoff_rounded;
      case 'local_hospital':
        return Icons.local_hospital_outlined;
      default:
        return Icons.receipt_long;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = transaction.type == 'income';
    final color = isIncome ? AppColors.income : AppColors.expense;
    final hasNote = transaction.note != null && transaction.note!.trim().isNotEmpty;
    final titleText = hasNote ? transaction.note! : (category?.name ?? 'Không rõ danh mục');
    final subtitleText = hasNote ? (category?.name ?? 'Không rõ danh mục') : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 0,
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade100, width: 1),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _getCategoryIcon(category?.icon),
            color: AppColors.primary,
            size: 22,
          ),
        ),
        title: Text(
          titleText,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: AppColors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: subtitleText != null
            ? Text(
                subtitleText,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: Text(
          '${isIncome ? '+' : '-'}${AppFormatters.number(transaction.amount)} VNĐ',
          style: GoogleFonts.inter(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
