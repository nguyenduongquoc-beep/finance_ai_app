import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/category_model.dart';
import '../../services/firestore_service.dart';
import '../../services/theme_controller.dart';
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
  bool _showExpenses = true; // Tab toggle: true = Chi tiêu (Expense), false = Thu nhập (Income)

  late final List<bool> _incomeSelected =
      List.filled(DefaultIncomeCategories.categories.length, true);
  late final List<bool> _expenseSelected =
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

  // Icon mapping helper
  IconData _getIconData(String name) {
    switch (name) {
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
        return Icons.category_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, _, __) {
        final categories = _showExpenses
            ? DefaultExpenseCategories.categories
            : DefaultIncomeCategories.categories;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            automaticallyImplyLeading: false,
          ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Head section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Step indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'BƯỚC 3/3',
                      style: GoogleFonts.inter(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Title
                  Text(
                    'Chọn danh mục',
                    style: GoogleFonts.inter(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Chọn danh mục thu/chi mặc định phù hợp với bạn để AI tự động phân loại.',
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Custom Segmented Control Tab bar
                  Container(
                    width: double.infinity,
                    height: 48,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _showExpenses = true),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _showExpenses ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: _showExpenses
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        )
                                      ]
                                    : null,
                              ),
                              child: Text(
                                'Chi tiêu',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: _showExpenses ? AppColors.primary : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _showExpenses = false),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: !_showExpenses ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: !_showExpenses
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        )
                                      ]
                                    : null,
                              ),
                              child: Text(
                                'Thu nhập',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: !_showExpenses ? AppColors.primary : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),

            // Grid content
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: categories.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 2.2,
                ),
                itemBuilder: (context, i) {
                  final c = categories[i];
                  final isSelected = _showExpenses ? _expenseSelected[i] : _incomeSelected[i];
                  final color = Color(c['color']);

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (_showExpenses) {
                          _expenseSelected[i] = !_expenseSelected[i];
                        } else {
                          _incomeSelected[i] = !_incomeSelected[i];
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : Colors.grey.shade200,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.06),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                )
                              ]
                            : null,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: color.withOpacity(0.12),
                            child: Icon(_getIconData(c['icon']), color: color, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  c['name'],
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.primary,
                              size: 18,
                            )
                          else
                            Icon(
                              Icons.circle_outlined,
                              color: Colors.grey.shade300,
                              size: 18,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Finish CTA button
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isLoading ? null : _handleFinish,
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          'Hoàn tất thiết lập',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  },
);
  }
}
