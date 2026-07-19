import 'package:flutter/material.dart';
import '../../models/transaction_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';

/// 12. Chi tiết giao dịch - cho phép Sửa / Xóa / Xem ảnh đính kèm
class TransactionDetailScreen extends StatelessWidget {
  final AppTransaction transaction;

  const TransactionDetailScreen({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();
    final isIncome = transaction.type == 'income';
    final color = isIncome ? AppColors.income : AppColors.expense;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Chi tiết giao dịch'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Xóa giao dịch?'),
                  content: const Text('Hành động này không thể hoàn tác.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Xóa', style: TextStyle(color: AppColors.expense))),
                  ],
                ),
              );
              if (confirm == true) {
                await firestoreService.deleteTransaction(transaction);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Column(
                children: [
                  Text(
                    '${isIncome ? '+' : '-'}${AppFormatters.currency(transaction.amount)}',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: color),
                  ),
                  Text(isIncome ? 'Thu nhập' : 'Chi tiêu',
                      style: const TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _buildInfoRow(Icons.calendar_today_outlined, 'Ngày', AppFormatters.date(transaction.date)),
            if (transaction.note != null && transaction.note!.isNotEmpty)
              _buildInfoRow(Icons.notes_outlined, 'Ghi chú', transaction.note!),
            if (transaction.location != null && transaction.location!.isNotEmpty)
              _buildInfoRow(Icons.location_on_outlined, 'Địa điểm', transaction.location!),
            if (transaction.image != null) ...[
              const SizedBox(height: 12),
              const Text('Ảnh hóa đơn', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(transaction.image!, height: 200, fit: BoxFit.cover),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          const Spacer(),
          Flexible(child: Text(value, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}
