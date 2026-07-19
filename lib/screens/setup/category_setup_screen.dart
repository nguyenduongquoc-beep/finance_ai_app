import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/category_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../widgets/main_navigation.dart';

/// 8. Chọn danh mục mặc định (Ăn uống, Đi lại, Hóa đơn, Giải trí...)
class CategorySetupScreen extends StatefulWidget {
  const CategorySetupScreen({super.key});

  @override
  State<CategorySetupScreen> createState() => _CategorySetupScreenState();
}

class _CategorySetupScreenState extends State<CategorySetupScreen> {
  final _firestoreService = FirestoreService();
  bool _isLoading = false;

  late List<bool> _incomeSelected =
      List.filled(DefaultIncomeCategories.categories.length, true);
  late List<bool> _expenseSelected =
      List.filled(DefaultExpenseCategories.categories.length, true);

  Future<void> _handleFinish() async {
    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      for (int i = 0; i < DefaultIncomeCategories.categories.length; i++) {
        if (!_incomeSelected[i]) continue;
        final c = DefaultIncomeCategories.categories[i];
        await _firestoreService.createCategory(Category(
          categoryId: '',
          userId: uid,
          name: c['name'],
          type: 'income',
          icon: c['icon'],
          color: c['color'],
        ));
      }

      for (int i = 0; i < DefaultExpenseCategories.categories.length; i++) {
        if (!_expenseSelected[i]) continue;
        final c = DefaultExpenseCategories.categories[i];
        await _firestoreService.createCategory(Category(
          categoryId: '',
          userId: uid,
          name: c['name'],
          type: 'expense',
          icon: c['icon'],
          color: c['color'],
        ));
      }

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainNavigation()),
        (route) => false,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Chọn danh mục'), automaticallyImplyLeading: false),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStepIndicator(step: 3, total: 3),
                const SizedBox(height: 12),
                const Text('Chọn danh mục thu/chi phù hợp với bạn (có thể chỉnh sửa sau)',
                    style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                const Text('Danh mục Thu', style: TextStyle(fontWeight: FontWeight.bold)),
                ...List.generate(DefaultIncomeCategories.categories.length, (i) {
                  final c = DefaultIncomeCategories.categories[i];
                  return CheckboxListTile(
                    value: _incomeSelected[i],
                    onChanged: (v) => setState(() => _incomeSelected[i] = v ?? false),
                    title: Text(c['name']),
                    secondary: CircleAvatar(
                      backgroundColor: Color(c['color']).withOpacity(0.15),
                      child: Icon(Icons.category, color: Color(c['color'])),
                    ),
                  );
                }),
                const SizedBox(height: 12),
                const Text('Danh mục Chi', style: TextStyle(fontWeight: FontWeight.bold)),
                ...List.generate(DefaultExpenseCategories.categories.length, (i) {
                  final c = DefaultExpenseCategories.categories[i];
                  return CheckboxListTile(
                    value: _expenseSelected[i],
                    onChanged: (v) => setState(() => _expenseSelected[i] = v ?? false),
                    title: Text(c['name']),
                    secondary: CircleAvatar(
                      backgroundColor: Color(c['color']).withOpacity(0.15),
                      child: Icon(Icons.category, color: Color(c['color'])),
                    ),
                  );
                }),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _isLoading ? null : _handleFinish,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Hoàn tất', style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator({required int step, required int total}) {
    return Row(
      children: List.generate(total, (i) {
        final active = i < step;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == total - 1 ? 0 : 6),
            height: 5,
            decoration: BoxDecoration(
              color: active ? AppColors.primary : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }),
    );
  }
}
