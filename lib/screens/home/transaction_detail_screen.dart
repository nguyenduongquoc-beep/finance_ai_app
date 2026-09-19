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
    final hasWallet = transaction.walletId.isNotEmpty;
    final hasCategory = transaction.categoryId.isNotEmpty;
    final isTransfer = transaction.type == 'transfer' &&
        transaction.toWalletId != null &&
        transaction.toWalletId!.isNotEmpty;
    final isGoalTx = (transaction.type == 'goal_deposit' || transaction.type == 'goal_withdraw') &&
        transaction.goalId != null &&
        transaction.goalId!.isNotEmpty;

    DocumentSnapshot? walletDoc;
    DocumentSnapshot? categoryDoc;
    DocumentSnapshot? toWalletDoc;
    DocumentSnapshot? goalDoc;

    try {
      final results = await Future.wait([
        hasWallet
            ? FirebaseFirestore.instance.collection('wallets').doc(transaction.walletId).get()
            : Future.value(null),
        hasCategory
            ? FirebaseFirestore.instance.collection('categories').doc(transaction.categoryId).get()
            : Future.value(null),
        isTransfer
            ? FirebaseFirestore.instance.collection('wallets').doc(transaction.toWalletId!).get()
            : Future.value(null),
        isGoalTx
            ? FirebaseFirestore.instance.collection('savingGoals').doc(transaction.goalId!).get()
            : Future.value(null),
      ]);

      walletDoc = results[0];
      categoryDoc = results[1];
      toWalletDoc = results[2];
      goalDoc = results[3];
    } catch (e) {
      debugPrint('❌ Error loading transaction details: $e');
    }

    String? goalName = (goalDoc != null && goalDoc.exists)
        ? ((goalDoc.data() as Map<String, dynamic>?)?['name'] as String?)
        : null;

    if ((goalName == null || goalName.isEmpty) && transaction.note != null) {
      final note = transaction.note!;
      if (note.contains(': ')) {
        goalName = note.split(': ').last;
      }
    }

    return {
      'walletName': (walletDoc != null && walletDoc.exists)
          ? ((walletDoc.data() as Map<String, dynamic>?)?['walletName'] ?? 'Không rõ')
          : 'Không rõ',
      'categoryName': (categoryDoc != null && categoryDoc.exists)
          ? ((categoryDoc.data() as Map<String, dynamic>?)?['name'] ?? 'Không rõ')
          : 'Không rõ',
      'categoryColor': (categoryDoc != null && categoryDoc.exists)
          ? ((categoryDoc.data() as Map<String, dynamic>?)?['color'] as int?)
          : null,
      'categoryIcon': (categoryDoc != null && categoryDoc.exists)
          ? ((categoryDoc.data() as Map<String, dynamic>?)?['icon'] as String?)
          : null,
      'toWalletName': (toWalletDoc != null && toWalletDoc.exists)
          ? ((toWalletDoc.data() as Map<String, dynamic>?)?['walletName'] ?? 'Không rõ')
          : null,
      'goalName': goalName ?? 'Không rõ',
    };
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, _, __) {
        final firestoreService = FirestoreService();
        final isGoalDeposit = transaction.type == 'goal_deposit';
        final isGoalWithdraw = transaction.type == 'goal_withdraw';
        final isGoalTx = isGoalDeposit || isGoalWithdraw;
        final isTransfer = transaction.type == 'transfer' || isGoalTx;
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
              final goalName = details['goalName'];

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
                              isGoalTx
                                  ? Icons.savings_outlined
                                  : (transaction.type == 'transfer'
                                      ? Icons.swap_horiz
                                      : getCategoryIcon(categoryIcon, transaction.type)),
                              color: color,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            isGoalDeposit
                                ? 'Số tiền đã nạp'
                                : (isGoalWithdraw
                                    ? 'Số tiền đã rút'
                                    : (transaction.type == 'transfer'
                                        ? 'Số tiền đã chuyển'
                                        : (isIncome ? 'Số tiền đã thu' : 'Số tiền đã chi'))),
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
                              isGoalDeposit
                                  ? 'Nạp tiết kiệm'
                                  : (isGoalWithdraw
                                      ? 'Rút tiết kiệm'
                                      : (transaction.type == 'transfer'
                                          ? 'Chuyển tiền'
                                          : (isIncome ? 'Thu nhập' : 'Chi tiêu'))),
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
                        if (isGoalTx) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Ví',
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
                                'Mục tiêu tiết kiệm',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                              ),
                              Text(
                                goalName ?? 'Không rõ',
                                style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24, thickness: 0.5),
                        ] else if (transaction.type == 'transfer') ...[
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
                        content: Text(
                          isGoalTx
                              ? 'Xóa giao dịch này sẽ hoàn tác cả số dư ví lẫn tiến độ mục tiêu tiết kiệm liên quan.'
                              : 'Hành động này không thể hoàn tác.',
                        ),
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
              if (!isGoalTx) ...[
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
                          Navigator.of(context).pop();
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

