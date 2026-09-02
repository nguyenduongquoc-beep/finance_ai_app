import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/category_model.dart';
import '../../models/transaction_model.dart';
import '../../services/firestore_service.dart';
import '../../services/theme_controller.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/stream_error_widget.dart';
import '../../widgets/app_snackbar.dart';

/// 14. Quản lý danh mục — Dạng List, icon theo loại, tổng tiền tháng này, chặn trùng tên
class CategoryManagementScreen extends StatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  State<CategoryManagementScreen> createState() => _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen> {
  final _firestoreService = FirestoreService();
  String _selectedType = 'expense'; // 'expense' | 'income'

  final List<Color> _colorOptions = [
    AppColors.expense,
    AppColors.income,
    AppColors.warning,
    AppColors.primary,
    AppColors.aiAccent,
    Colors.brown,
    Colors.teal,
    Colors.indigo,
  ];

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
      case 'receipt':
      case 'receipt_long':
        return Icons.receipt_long_outlined;
      default:
        return Icons.category_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, _, __) {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Danh mục'),
            elevation: 0,
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
          floatingActionButton: FloatingActionButton(
            backgroundColor: AppColors.primary,
            onPressed: () => _showCategoryDialog(context, uid),
            child: const Icon(Icons.add, color: Colors.white),
          ),
          body: Column(
            children: [
              // Segmented Control Pill Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Container(
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
                          onTap: () => setState(() => _selectedType = 'expense'),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _selectedType == 'expense' ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: _selectedType == 'expense'
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              'Chi tiêu',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _selectedType == 'expense'
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedType = 'income'),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _selectedType == 'income' ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: _selectedType == 'income'
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              'Thu nhập',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _selectedType == 'income'
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Category List View
              Expanded(
                child: _buildCategoryList(uid, _selectedType),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryList(String uid, String type) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);

    return StreamBuilder<List<Category>>(
      stream: _firestoreService.streamCategories(uid, type: type),
      builder: (context, snap) {
        if (snap.hasError) return StreamErrorWidget(error: snap.error.toString());
        final categories = snap.data ?? [];
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());

        if (categories.isEmpty) {
          return Center(
            child: Text(
              'Chưa có danh mục ${type == 'expense' ? 'chi tiêu' : 'thu nhập'} nào.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          );
        }

        return StreamBuilder<List<AppTransaction>>(
          stream: _firestoreService.streamTransactions(uid, from: monthStart),
          builder: (context, txSnap) {
            final monthTx = txSnap.data ?? [];
            final Map<String, double> totalsByCategory = {};
            for (final tx in monthTx.where((t) => t.type == type)) {
              totalsByCategory[tx.categoryId] = (totalsByCategory[tx.categoryId] ?? 0) + tx.amount;
            }

            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 80, top: 4),
              itemCount: categories.length,
              itemBuilder: (context, i) {
                final c = categories[i];
                final monthlyTotal = totalsByCategory[c.categoryId] ?? 0.0;
                final catColor = Color(c.color);
                final label = type == 'expense' ? 'Chi tiêu' : 'Thu nhập';

                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _showCategoryDialog(context, uid, category: c),
                      onLongPress: () => _handleDeleteCategory(context, uid, c, categories),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: catColor.withOpacity(0.15),
                              child: Icon(
                                _getCategoryIcon(c.icon),
                                color: catColor,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: AppColors.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$label trong tháng: ${AppFormatters.currency(monthlyTotal)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _handleDeleteCategory(
    BuildContext context,
    String uid,
    Category c,
    List<Category> categories,
  ) async {
    try {
      final inUse = await _firestoreService.checkCategoryInUse(uid, c.categoryId);
      if (!inUse) {
        if (!context.mounted) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Xóa danh mục?'),
            content: Text(
              'Bạn có chắc chắn muốn xóa danh mục "${c.name}"? Hành động này không thể hoàn tác, dữ liệu sẽ mất vĩnh viễn.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Hủy'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Xóa',
                  style: TextStyle(color: AppColors.expense),
                ),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await _firestoreService.deleteCategory(c.categoryId);
        }
        return;
      }

      final defaultCategory = categories.firstWhere(
        (cat) => cat.categoryId != c.categoryId,
        orElse: () => c,
      );
      if (defaultCategory.categoryId == c.categoryId) {
        if (context.mounted) {
          AppSnackbar.show(
            context,
            'Không thể xóa danh mục duy nhất đang chứa giao dịch/ngân sách.',
            isError: true,
          );
        }
        return;
      }

      String? selectedCategoryId = defaultCategory.categoryId;
      if (!context.mounted) return;
      final confirmReassign = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: const Text('Danh mục đang được sử dụng'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Danh mục này đang chứa giao dịch hoặc ngân sách. Vui lòng chọn danh mục để chuyển các dữ liệu này sang trước khi xóa:',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategoryId,
                    decoration: const InputDecoration(
                      labelText: 'Chuyển sang',
                      border: OutlineInputBorder(),
                    ),
                    items: categories
                        .where((cat) => cat.categoryId != c.categoryId)
                        .map(
                          (cat) => DropdownMenuItem(
                            value: cat.categoryId,
                            child: Text(cat.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => selectedCategoryId = v),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Hủy'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text(
                    'Xóa & Chuyển',
                    style: TextStyle(color: AppColors.expense),
                  ),
                ),
              ],
            ),
          );
        },
      );

      if (confirmReassign == true && selectedCategoryId != null) {
        await _firestoreService.reassignAndDeleteCategory(
          uid,
          c.categoryId,
          selectedCategoryId!,
        );
      }
    } catch (e) {
      debugPrint('❌ Lỗi khi kiểm tra/xóa danh mục: $e');
      if (context.mounted) {
        AppSnackbar.show(
          context,
          'Không thể xóa danh mục. Vui lòng kiểm tra kết nối và thử lại.',
          isError: true,
        );
      }
    }
  }

  void _showCategoryDialog(BuildContext context, String uid, {Category? category}) {
    final nameController = TextEditingController(text: category?.name ?? '');
    String type = category?.type ?? _selectedType;
    Color selectedColor = category != null ? Color(category.color) : _colorOptions.first;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: Text(category == null ? 'Danh mục mới' : 'Sửa danh mục'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Tên danh mục'),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Chọn màu'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _colorOptions.map((c) {
                  return GestureDetector(
                    onTap: () => setDialogState(() => selectedColor = c),
                    child: CircleAvatar(
                      backgroundColor: c,
                      radius: 16,
                      child: selectedColor == c
                          ? const Icon(Icons.check, color: Colors.white, size: 16)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Hủy'),
            ),
            TextButton(
              onPressed: () async {
                final newName = nameController.text.trim();
                if (newName.isEmpty) return;

                try {
                  final categoriesInType = await _firestoreService
                      .streamCategories(uid, type: type)
                      .first;
                  final isDuplicate = categoriesInType.any((existing) =>
                      existing.categoryId != category?.categoryId &&
                      existing.name.trim().toLowerCase() == newName.toLowerCase());

                  if (isDuplicate) {
                    if (dialogCtx.mounted) {
                      AppSnackbar.show(
                        context,
                        'Danh mục "$newName" đã tồn tại, vui lòng đặt tên khác.',
                        isError: true,
                      );
                    }
                    return;
                  }

                  if (category == null) {
                    await _firestoreService.createCategory(Category(
                      categoryId: '',
                      userId: uid,
                      name: newName,
                      type: type,
                      icon: 'category',
                      color: selectedColor.toARGB32(),
                    ));
                  } else {
                    await _firestoreService.updateCategory(category.categoryId, {
                      'name': newName,
                      'color': selectedColor.toARGB32(),
                    });
                  }
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                } catch (e) {
                  debugPrint('❌ Lỗi khi lưu danh mục: $e');
                  if (dialogCtx.mounted) {
                    AppSnackbar.show(
                      context,
                      'Không thể lưu danh mục. Vui lòng thử lại.',
                      isError: true,
                    );
                  }
                }
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }
}
