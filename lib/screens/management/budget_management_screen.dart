import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/budget_model.dart';
import '../../models/category_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/budget_progress_card.dart';
import '../../widgets/stream_error_widget.dart';

/// 15. Quản lý ngân sách - vd: Ăn uống 3 triệu/tháng, cảnh báo khi vượt 90%
class BudgetManagementScreen extends StatelessWidget {
  const BudgetManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final firestoreService = FirestoreService();
    final currentMonth = AppFormatters.month(DateTime.now());

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Quản lý ngân sách')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: () => _showBudgetDialog(context, firestoreService, uid, currentMonth),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: StreamBuilder<List<Category>>(
        stream: firestoreService.streamCategories(uid, type: 'expense'),
        builder: (context, catSnap) {
          if (catSnap.hasError) return StreamErrorWidget(error: catSnap.error.toString());
          final categories = catSnap.data ?? [];
          return StreamBuilder<List<Budget>>(
            stream: firestoreService.streamBudgets(uid, month: currentMonth),
            builder: (context, budgetSnap) {
              if (budgetSnap.hasError) return StreamErrorWidget(error: budgetSnap.error.toString());
              final budgets = budgetSnap.data ?? [];
              if (!budgetSnap.hasData) return const Center(child: CircularProgressIndicator());
              if (budgets.isEmpty) {
                return const Center(
                  child: Text('Chưa thiết lập ngân sách nào cho tháng này',
                      style: TextStyle(color: AppColors.textSecondary)),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(top: 12, bottom: 80),
                itemCount: budgets.length,
                itemBuilder: (context, i) {
                  final budget = budgets[i];
                  final category = categories
                      .where((c) => c.categoryId == budget.categoryId)
                      .cast<Category?>()
                      .firstWhere((c) => true, orElse: () => null);
                  return BudgetProgressCard(
                    budget: budget,
                    category: category,
                    onTap: () => _showBudgetDialog(context, firestoreService, uid, currentMonth,
                        budget: budget),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  void _showBudgetDialog(
    BuildContext context,
    FirestoreService firestoreService,
    String uid,
    String month, {
    Budget? budget,
  }) {
    Category? selectedCategory;
    final limitController =
        TextEditingController(text: budget != null ? budget.limit.toStringAsFixed(0) : '');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(budget == null ? 'Thêm ngân sách' : 'Sửa ngân sách'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (budget == null)
                StreamBuilder<List<Category>>(
                  stream: firestoreService.streamCategories(uid, type: 'expense'),
                  builder: (context, snap) {
                    if (snap.hasError) return const Text('Lỗi tải danh mục');
                    final categories = snap.data ?? [];
                    return DropdownButtonFormField<Category>(
                      decoration: const InputDecoration(labelText: 'Danh mục'),
                      items: categories
                          .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                          .toList(),
                      onChanged: (v) => setDialogState(() => selectedCategory = v),
                    );
                  },
                ),
              const SizedBox(height: 12),
              TextField(
                controller: limitController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Hạn mức (đ/tháng)'),
              ),
            ],
          ),
          actions: [
            if (budget != null)
              TextButton(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Xóa ngân sách?'),
                      content: const Text('Bạn có chắc chắn muốn xóa ngân sách này?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa', style: TextStyle(color: AppColors.expense))),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await firestoreService.deleteBudget(budget.budgetId);
                    if (ctx.mounted) Navigator.pop(ctx);
                  }
                },
                child: const Text('Xóa', style: TextStyle(color: AppColors.expense)),
              ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            TextButton(
              onPressed: () async {
                final limit = AppFormatters.parseCurrencyInput(limitController.text);
                if (budget == null) {
                  if (selectedCategory == null) return;
                  
                  final existing = await firestoreService.getCategoryBudget(selectedCategory!.categoryId, month: month);
                  if (existing != null) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Ngân sách cho danh mục này trong tháng đã tồn tại. Đang chuyển sang chế độ sửa.'))
                      );
                      Navigator.pop(ctx);
                      _showBudgetDialog(context, firestoreService, uid, month, budget: existing);
                    }
                    return;
                  }
                  
                  await firestoreService.createBudget(Budget(
                    budgetId: '',
                    userId: uid,
                    categoryId: selectedCategory!.categoryId,
                    limit: limit,
                    month: month,
                  ));
                } else {
                  await firestoreService.updateBudget(budget.budgetId, {'limit': limit});
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }
}
