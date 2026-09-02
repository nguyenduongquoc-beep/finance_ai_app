import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/budget_model.dart';
import '../../models/category_model.dart';
import '../../services/firestore_service.dart';
import '../../services/theme_controller.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/app_snackbar.dart';

class _BudgetItemDraft {
  final String? budgetId; // null nếu là item mới chưa tạo trên Firestore
  final String categoryId;
  final String categoryName;
  final TextEditingController controller;

  _BudgetItemDraft({
    this.budgetId,
    required this.categoryId,
    required this.categoryName,
    required double limit,
  }) : controller = TextEditingController(
          text: limit > 0 ? AppFormatters.number(limit) : '',
        );
}

/// Màn hình Thiết lập ngân sách (Ticket 025)
class BudgetSetupScreen extends StatefulWidget {
  final DateTime initialMonth;

  const BudgetSetupScreen({
    super.key,
    required this.initialMonth,
  });

  @override
  State<BudgetSetupScreen> createState() => _BudgetSetupScreenState();
}

class _BudgetSetupScreenState extends State<BudgetSetupScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  late DateTime _selectedMonth;
  bool _isLoading = true;
  bool _isSaving = false;

  List<Category> _allExpenseCategories = [];
  final List<_BudgetItemDraft> _drafts = [];
  final Set<String> _deletedBudgetIds = {};

  @override
  void initState() {
    super.initState();
    _selectedMonth = DateTime(widget.initialMonth.year, widget.initialMonth.month, 1);
    _loadData();
  }

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    try {
      // Clear draft cũ
      for (final draft in _drafts) {
        draft.controller.dispose();
      }
      _drafts.clear();
      _deletedBudgetIds.clear();

      final monthKey = AppFormatters.month(_selectedMonth);
      final catList = await _firestoreService.streamCategories(uid, type: 'expense').first;
      final budgetList = await _firestoreService.streamBudgets(uid, month: monthKey).first;

      _allExpenseCategories = catList;

      for (final b in budgetList) {
        final cat = catList.where((c) => c.categoryId == b.categoryId).firstOrNull;
        _drafts.add(_BudgetItemDraft(
          budgetId: b.budgetId,
          categoryId: b.categoryId,
          categoryName: cat?.name ?? 'Danh mục',
          limit: b.limit,
        ));
      }
    } catch (e) {
      debugPrint('❌ Lỗi khi tải dữ liệu thiết lập ngân sách: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showMonthPicker() {
    int selectedM = _selectedMonth.month;
    int selectedY = _selectedMonth.year;
    final nowY = DateTime.now().year;
    final years = List.generate(5, (i) => nowY - 2 + i);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            title: const Text('Chọn tháng/năm'),
            content: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DropdownButton<int>(
                  value: selectedM,
                  items: List.generate(12, (i) => i + 1)
                      .map((m) => DropdownMenuItem(value: m, child: Text('Tháng $m')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDlgState(() => selectedM = v);
                  },
                ),
                const SizedBox(width: 20),
                DropdownButton<int>(
                  value: selectedY,
                  items: years
                      .map((y) => DropdownMenuItem(value: y, child: Text('Năm $y')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDlgState(() => selectedY = v);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _selectedMonth = DateTime(selectedY, selectedM, 1);
                  });
                  _loadData();
                },
                child: const Text('Chọn', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _addCategoryDialog() {
    final existingCatIds = _drafts.map((d) => d.categoryId).toSet();
    final availableCategories =
        _allExpenseCategories.where((c) => !existingCatIds.contains(c.categoryId)).toList();

    if (availableCategories.isEmpty) {
      AppSnackbar.show(context, 'Tất cả danh mục chi tiêu đã được thêm ngân sách.', isError: true);
      return;
    }

    Category? selectedCat = availableCategories.first;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            title: const Text('Thêm danh mục ngân sách'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<Category>(
                  initialValue: selectedCat,
                  decoration: const InputDecoration(
                    labelText: 'Danh mục',
                    border: OutlineInputBorder(),
                  ),
                  items: availableCategories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                      .toList(),
                  onChanged: (v) => setDlgState(() => selectedCat = v),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
              TextButton(
                onPressed: () {
                  if (selectedCat != null) {
                    Navigator.pop(ctx);
                    setState(() {
                      _drafts.add(_BudgetItemDraft(
                        categoryId: selectedCat!.categoryId,
                        categoryName: selectedCat!.name,
                        limit: 0,
                      ));
                    });
                  }
                },
                child: const Text('Thêm', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _copyPreviousMonthBudgets() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final prevMonthDate = DateTime(_selectedMonth.year, _selectedMonth.month - 1, 1);
    final prevMonthKey = AppFormatters.month(prevMonthDate);

    try {
      final prevBudgets = await _firestoreService.streamBudgets(uid, month: prevMonthKey).first;
      if (prevBudgets.isEmpty) {
        if (mounted) {
          AppSnackbar.show(context, 'Tháng trước ($prevMonthKey) chưa có ngân sách nào.', isError: true);
        }
        return;
      }

      final existingCatIds = _drafts.map((d) => d.categoryId).toSet();
      int addedCount = 0;

      for (final pb in prevBudgets) {
        if (!existingCatIds.contains(pb.categoryId)) {
          final cat = _allExpenseCategories.where((c) => c.categoryId == pb.categoryId).firstOrNull;
          _drafts.add(_BudgetItemDraft(
            categoryId: pb.categoryId,
            categoryName: cat?.name ?? 'Danh mục',
            limit: pb.limit,
          ));
          addedCount++;
        }
      }

      if (mounted) {
        if (addedCount > 0) {
          setState(() {});
          AppSnackbar.show(context, 'Đã sao chép $addedCount danh mục từ tháng $prevMonthKey.');
        } else {
          AppSnackbar.show(context, 'Tất cả danh mục từ tháng trước đã có trong danh sách hiện tại.');
        }
      }
    } catch (e) {
      debugPrint('❌ Lỗi khi sao chép ngân sách tháng trước: $e');
    }
  }

  Future<void> _saveBudgets() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final monthKey = AppFormatters.month(_selectedMonth);

    setState(() => _isSaving = true);
    try {
      final futures = <Future<void>>[];

      // 1. Xóa các budget bị xóa
      for (final id in _deletedBudgetIds) {
        futures.add(_firestoreService.deleteBudget(id));
      }

      // 2. Thêm mới / Cập nhật
      for (final draft in _drafts) {
        final limit = AppFormatters.parseCurrencyInput(draft.controller.text);
        if (draft.budgetId != null) {
          futures.add(_firestoreService.updateBudget(draft.budgetId!, {'limit': limit}));
        } else {
          futures.add(_firestoreService.createBudget(Budget(
            budgetId: '',
            userId: uid,
            categoryId: draft.categoryId,
            limit: limit,
            month: monthKey,
          )));
        }
      }

      await Future.wait(futures);

      if (mounted) {
        AppSnackbar.show(context, 'Lưu thiết lập ngân sách thành công!');
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('❌ Lỗi khi lưu ngân sách: $e');
      if (mounted) {
        AppSnackbar.show(context, 'Không thể lưu ngân sách. Vui lòng thử lại.', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final capitalizedMonth = 'Tháng ${_selectedMonth.month}, ${_selectedMonth.year}';

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Thiết lập ngân sách'),
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.copy_rounded),
                tooltip: 'Sao chép tháng trước',
                onPressed: _isSaving ? null : _copyPreviousMonthBudgets,
              ),
            ],
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    // Hàng chọn tháng
                    Container(
                      color: AppColors.card,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Thời gian áp dụng',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          InkWell(
                            onTap: _showMonthPicker,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              child: Row(
                                children: [
                                  Text(
                                    capitalizedMonth,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.calendar_month_rounded,
                                      size: 18, color: AppColors.primary),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    // Danh sách thiết lập hạn mức
                    Expanded(
                      child: _drafts.isEmpty
                          ? Center(
                              child: Text(
                                'Chưa có hạn mức nào. Bấm "+ Thêm danh mục" ở bên dưới.',
                                style: TextStyle(color: AppColors.textSecondary),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(20),
                              itemCount: _drafts.length,
                              itemBuilder: (context, index) {
                                final draft = _drafts[index];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: AppColors.card,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          draft.categoryName,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 3,
                                        child: TextField(
                                          controller: draft.controller,
                                          keyboardType: TextInputType.number,
                                          textAlign: TextAlign.end,
                                          decoration: InputDecoration(
                                            hintText: 'Hạn mức',
                                            suffixText: ' VNĐ',
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 10),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded,
                                            color: AppColors.expense),
                                        onPressed: () {
                                          setState(() {
                                            if (draft.budgetId != null) {
                                              _deletedBudgetIds.add(draft.budgetId!);
                                            }
                                            _drafts.removeAt(index);
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),

                    // Bottom Bar
                    SafeArea(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        color: AppColors.card,
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                  side: BorderSide(color: Colors.grey.shade300),
                                ),
                                onPressed: _addCategoryDialog,
                                icon: const Icon(Icons.add, color: AppColors.primary),
                                label: const Text(
                                  'Thêm danh mục',
                                  style: TextStyle(
                                      color: AppColors.primary, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF16283A),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                  elevation: 0,
                                ),
                                onPressed: _isSaving ? null : _saveBudgets,
                                child: _isSaving
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Text(
                                        'Lưu',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
