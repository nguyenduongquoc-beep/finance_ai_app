import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../models/transaction_model.dart';
import '../../services/firestore_service.dart';
import '../../services/theme_controller.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import 'dart:io';
import 'add_transaction_screen.dart';

/// 12. Chi tiết giao dịch - cho phép Sửa / Xóa / Xem ảnh đính kèm
class TransactionDetailScreen extends StatelessWidget {
  final AppTransaction transaction;

  const TransactionDetailScreen({super.key, required this.transaction});

  IconData getCategoryIcon(String? iconName, String type) {
    if (iconName == null) {
      return type == 'income' ? Icons.arrow_downward : Icons.arrow_upward;
    }
    switch (iconName) {
      case 'restaurant':
        return Icons.restaurant;
      case 'shopping_bag':
        return Icons.shopping_bag;
      case 'local_gas_station':
        return Icons.local_gas_station;
      case 'school':
        return Icons.school;
      case 'movie':
        return Icons.movie;
      case 'flight':
        return Icons.flight;
      case 'local_hospital':
        return Icons.local_hospital;
      case 'work':
        return Icons.work;
      case 'card_giftcard':
        return Icons.card_giftcard;
      case 'storefront':
        return Icons.storefront;
      default:
        return Icons.category;
    }
  }

  String getFormattedDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final txDate = DateTime(date.year, date.month, date.day);
    final dateStr = DateFormat('dd/MM/yyyy').format(date);
    if (txDate == today) {
      return 'Hôm nay, $dateStr';
    } else if (txDate == yesterday) {
      return 'Hôm qua, $dateStr';
    } else {
      return dateStr;
    }
  }

  Future<Map<String, dynamic>> _loadDetails() async {
    final walletDoc = await FirebaseFirestore.instance.collection('wallets').doc(transaction.walletId).get();
    final categoryDoc = await FirebaseFirestore.instance.collection('categories').doc(transaction.categoryId).get();

    String? toWalletName;
    if (transaction.type == 'transfer' && transaction.toWalletId != null && transaction.toWalletId!.isNotEmpty) {
      final toWalletDoc = await FirebaseFirestore.instance.collection('wallets').doc(transaction.toWalletId).get();
      toWalletName = toWalletDoc.exists ? (toWalletDoc.data()?['walletName'] ?? 'Không rõ') : 'Không rõ';
    }

    return {
      'walletName': walletDoc.exists ? (walletDoc.data()?['walletName'] ?? 'Không rõ') : 'Không rõ',
      'categoryName': categoryDoc.exists ? (categoryDoc.data()?['name'] ?? 'Không rõ') : 'Không rõ',
      'categoryColor': categoryDoc.exists ? (categoryDoc.data()?['color'] as int?) : null,
      'categoryIcon': categoryDoc.exists ? (categoryDoc.data()?['icon'] as String?) : null,
      'toWalletName': toWalletName,
    };
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, _, __) {
        final firestoreService = FirestoreService();
        final isTransfer = transaction.type == 'transfer';
        final isIncome = transaction.type == 'income';
        final color = isTransfer
            ? AppColors.textSecondary
            : (isIncome ? AppColors.income : AppColors.expense);

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Chi tiết giao dịch'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
            elevation: 0,
          ),
          body: FutureBuilder<Map<String, dynamic>>(
            future: _loadDetails(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final details = snapshot.data ?? {};
              final walletName = details['walletName'] ?? 'Không rõ';
              final categoryName = details['categoryName'] ?? 'Không rõ';
              final categoryIcon = details['categoryIcon'];
              final toWalletName = details['toWalletName'];

              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isTransfer
                                  ? Icons.swap_horiz
                                  : getCategoryIcon(categoryIcon, transaction.type),
                              color: color,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            isTransfer
                                ? 'Số tiền đã chuyển'
                                : (isIncome ? 'Số tiền đã thu' : 'Số tiền đã chi'),
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isTransfer
                                ? AppFormatters.currency(transaction.amount)
                                : '${isIncome ? '+' : '-'}${AppFormatters.currency(transaction.amount)}',
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isTransfer ? 'Chuyển tiền' : (isIncome ? 'Thu nhập' : 'Chi tiêu'),
                              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Card(
                      margin: EdgeInsets.zero,
                      elevation: 0,
                      color: AppColors.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.grey.shade200, width: 1),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isTransfer) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Danh mục',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                              ),
                              Text(
                                categoryName,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24, thickness: 0.5),
                        ],
                        if (isTransfer) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Từ ví',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                              ),
                              Text(
                                walletName,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24, thickness: 0.5),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Đến ví',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                              ),
                              Text(
                                toWalletName ?? 'Không rõ',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24, thickness: 0.5),
                        ] else ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Ví thanh toán',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                              ),
                              Text(
                                walletName,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24, thickness: 0.5),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Thời gian',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                            ),
                            Text(
                              getFormattedDate(transaction.date),
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if (transaction.note != null && transaction.note!.isNotEmpty) ...[
                          const Divider(height: 24, thickness: 0.5),
                          Text(
                            'Ghi chú',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            transaction.note!,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                              fontSize: 15,
                            ),
                          ),
                        ],
                        if (transaction.location != null && transaction.location!.isNotEmpty) ...[
                          const Divider(height: 24, thickness: 0.5),
                          Text(
                            'Địa điểm',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            transaction.location!,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                              fontSize: 15,
                            ),
                          ),
                        ],
                        if (transaction.image != null && transaction.image!.isNotEmpty) ...[
                          const Divider(height: 24, thickness: 0.5),
                          Text(
                            'Ảnh hóa đơn',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FullscreenImageScreen(imagePath: transaction.image!),
                                ),
                              );
                            },
                            child: Container(
                              constraints: const BoxConstraints(
                                maxHeight: 250,
                              ),
                              width: double.infinity,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  File(transaction.image!),
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    height: 200,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.broken_image_outlined, color: Colors.grey, size: 40),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Xóa giao dịch?'),
                        content: const Text('Hành động này không thể hoàn tác.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Hủy'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Xóa', style: TextStyle(color: AppColors.expense)),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await firestoreService.deleteTransaction(transaction);
                      if (context.mounted) Navigator.of(context).pop();
                    }
                  },
                  child: Text(
                    'Xóa',
                    style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AddTransactionScreen(transactionToEdit: transaction),
                      ),
                    );
                    if (result == true) {
                      if (context.mounted) {
                        Navigator.of(context).pop(); // Quay lại màn hình danh sách sau khi sửa thành công
                      }
                    }
                  },
                  child: const Text(
                    'Sửa',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  },
);
  }
}

class FullscreenImageScreen extends StatelessWidget {
  final String imagePath;
  const FullscreenImageScreen({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Ảnh hóa đơn', style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: InteractiveViewer(
          panEnabled: true,
          boundaryMargin: const EdgeInsets.all(20),
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.file(
            File(imagePath),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Center(
              child: Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
            ),
          ),
        ),
      ),
    );
  }
}

