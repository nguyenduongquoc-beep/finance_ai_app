import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/category_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../widgets/stream_error_widget.dart';

/// 14. Quản lý danh mục - Đổi icon, Đổi màu, Tạo mới
class CategoryManagementScreen extends StatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  State<CategoryManagementScreen> createState() => _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _firestoreService = FirestoreService();

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Quản lý danh mục'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          tabs: const [Tab(text: 'Chi tiêu'), Tab(text: 'Thu nhập')],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: () => _showCategoryDialog(context, uid),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCategoryList(uid, 'expense'),
          _buildCategoryList(uid, 'income'),
        ],
      ),
    );
  }

  Widget _buildCategoryList(String uid, String type) {
    return StreamBuilder<List<Category>>(
      stream: _firestoreService.streamCategories(uid, type: type),
      builder: (context, snap) {
        if (snap.hasError) return StreamErrorWidget(error: snap.error.toString());
        final categories = snap.data ?? [];
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.9,
          ),
          itemCount: categories.length,
          itemBuilder: (context, i) {
            final c = categories[i];
            return GestureDetector(
              onTap: () => _showCategoryDialog(context, uid, category: c),
              onLongPress: () async {
                final inUse = await _firestoreService.checkCategoryInUse(c.categoryId);
                if (!inUse) {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Xóa danh mục?'),
                      content: const Text('Bạn có chắc chắn muốn xóa danh mục này? Hành động này không thể hoàn tác.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa', style: TextStyle(color: AppColors.expense))),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await _firestoreService.deleteCategory(c.categoryId);
                  }
                  return;
                }
                
                final defaultCategory = categories.firstWhere((cat) => cat.categoryId != c.categoryId, orElse: () => c);
                if (defaultCategory.categoryId == c.categoryId) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể xóa danh mục duy nhất đang chứa giao dịch/ngân sách.')));
                  return;
                }
                
                String? selectedCategoryId = defaultCategory.categoryId;
                final confirmReassign = await showDialog<bool>(
                  context: context,
                  builder: (ctx) {
                    return StatefulBuilder(
                      builder: (context, setState) => AlertDialog(
                        title: const Text('Danh mục đang được sử dụng'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Danh mục này đang chứa giao dịch hoặc ngân sách. Vui lòng chọn danh mục để chuyển các dữ liệu này sang trước khi xóa:'),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              value: selectedCategoryId,
                              decoration: const InputDecoration(labelText: 'Chuyển sang', border: OutlineInputBorder()),
                              items: categories
                                  .where((cat) => cat.categoryId != c.categoryId)
                                  .map((cat) => DropdownMenuItem(value: cat.categoryId, child: Text(cat.name)))
                                  .toList(),
                              onChanged: (v) => setState(() => selectedCategoryId = v),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa & Chuyển', style: TextStyle(color: AppColors.expense))),
                        ],
                      )
                    );
                  }
                );
                
                if (confirmReassign == true && selectedCategoryId != null) {
                  await _firestoreService.reassignAndDeleteCategory(c.categoryId, selectedCategoryId!);
                }
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Color(c.color).withOpacity(0.15),
                    child: Icon(Icons.category, color: Color(c.color)),
                  ),
                  const SizedBox(height: 6),
                  Text(c.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showCategoryDialog(BuildContext context, String uid, {Category? category}) {
    final nameController = TextEditingController(text: category?.name ?? '');
    String type = category?.type ?? (_tabController.index == 0 ? 'expense' : 'income');
    Color selectedColor = category != null ? Color(category.color) : _colorOptions.first;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(category == null ? 'Danh mục mới' : 'Sửa danh mục'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Tên danh mục'),
              ),
              const SizedBox(height: 16),
              const Align(alignment: Alignment.centerLeft, child: Text('Chọn màu')),
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
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            TextButton(
              onPressed: () async {
                if (category == null) {
                  await _firestoreService.createCategory(Category(
                    categoryId: '',
                    userId: uid,
                    name: nameController.text.trim(),
                    type: type,
                    icon: 'category',
                    color: selectedColor.value,
                  ));
                } else {
                  await _firestoreService.updateCategory(category.categoryId, {
                    'name': nameController.text.trim(),
                    'color': selectedColor.value,
                  });
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
