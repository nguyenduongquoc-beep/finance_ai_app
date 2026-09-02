import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/budget_model.dart';
import '../../models/category_model.dart';
import '../../models/transaction_model.dart';
import '../../services/firestore_service.dart';
import '../../services/theme_controller.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/budget_progress_card.dart';
import '../../widgets/stream_error_widget.dart';
import 'budget_setup_screen.dart';

/// Màn hình Ngân sách (Redesign Ticket 025 khớp 100% mockup Figma)
class BudgetManagementScreen extends StatefulWidget {
  const BudgetManagementScreen({super.key});

  @override
  State<BudgetManagementScreen> createState() => _BudgetManagementScreenState();
}

class _BudgetManagementScreenState extends State<BudgetManagementScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

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
                },
                child: const Text('Chọn', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPercentCircle(double totalSpent, double totalLimit) {
    final ratio = totalLimit <= 0 ? 0.0 : (totalSpent / totalLimit);
    final percentInt = (ratio * 100).round();
    const accentColor = Color(0xFF10B981); // Emerald Green matching mockup

    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              strokeWidth: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              color: accentColor,
            ),
          ),
          Text(
            '$percentInt%',
            style: const TextStyle(
              color: accentColor,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final monthKey = AppFormatters.month(_selectedMonth);
    final monthStart = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final monthEnd = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1)
        .subtract(const Duration(seconds: 1));

    final capitalizedMonth = 'Tháng ${_selectedMonth.month}, ${_selectedMonth.year}';

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('Ngân sách'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
            elevation: 0,
          ),
          body: StreamBuilder<List<Category>>(
            stream: _firestoreService.streamCategories(uid, type: 'expense'),
            builder: (context, catSnap) {
              if (catSnap.hasError) return StreamErrorWidget(error: catSnap.error.toString());
              final categories = catSnap.data ?? [];

              return StreamBuilder<List<Budget>>(
                stream: _firestoreService.streamBudgets(uid, month: monthKey),
                builder: (context, budgetSnap) {
                  if (budgetSnap.hasError) {
                    return StreamErrorWidget(error: budgetSnap.error.toString());
                  }
                  final budgets = budgetSnap.data ?? [];

                  return StreamBuilder<List<AppTransaction>>(
                    stream: _firestoreService.streamTransactions(uid, from: monthStart, to: monthEnd),
                    builder: (context, txSnap) {
                      if (txSnap.hasError) {
                        return StreamErrorWidget(error: txSnap.error.toString());
                      }
                      if (!budgetSnap.hasData || !txSnap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final monthTx = txSnap.data ?? [];
                      final Map<String, double> spentByCategory = {};
                      for (final tx in monthTx.where((t) => t.type == 'expense')) {
                        spentByCategory[tx.categoryId] =
                            (spentByCategory[tx.categoryId] ?? 0) + tx.amount;
                      }

                      // Tính tổng limit & tổng spent cho các category ĐÃ CÓ BUDGET
                      double totalLimit = 0;
                      double totalSpent = 0;
                      for (final b in budgets) {
                        totalLimit += b.limit;
                        totalSpent += spentByCategory[b.categoryId] ?? 0;
                      }

                      return Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.only(bottom: 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Hàng "Thời gian áp dụng"
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
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
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            child: Text(
                                              capitalizedMonth,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF10B981),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Card tối "TỔNG NGÂN SÁCH" (khớp 100% mockup)
                                  Container(
                                    margin: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      // TODO: chuẩn hóa theo AppColors nếu có token màu tối chính thức
                                      color: const Color(0xFF16283A),
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'TỔNG NGÂN SÁCH',
                                                style: TextStyle(
                                                  color: Color(0xFF10B981),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                '${AppFormatters.currency(totalSpent)} / ${AppFormatters.currency(totalLimit)}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 18,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        _buildPercentCircle(totalSpent, totalLimit),
                                      ],
                                    ),
                                  ),

                                  // Tiêu đề Hạn mức chi tiêu chi tiết
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                                    child: Text(
                                      'Hạn mức chi tiêu chi tiết',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),

                                  // Danh sách card
                                  if (budgets.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.all(40),
                                      child: Center(
                                        child: Text(
                                          'Chưa thiết lập ngân sách nào cho tháng này',
                                          style: TextStyle(color: AppColors.textSecondary),
                                        ),
                                      ),
                                    )
                                  else
                                    ListView.builder(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: budgets.length,
                                      itemBuilder: (context, i) {
                                        final budget = budgets[i];
                                        final category = categories
                                            .where((c) => c.categoryId == budget.categoryId)
                                            .firstOrNull;
                                        final spentAmount = spentByCategory[budget.categoryId] ?? 0;
                                        return BudgetProgressCard(
                                          budget: budget,
                                          spentAmount: spentAmount,
                                          category: category,
                                          onTap: () async {
                                            final updated = await Navigator.push<bool>(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => BudgetSetupScreen(
                                                  initialMonth: _selectedMonth,
                                                ),
                                              ),
                                            );
                                            if (updated == true) setState(() {});
                                          },
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ),

                          // Nút Thiết lập ngân sách full-width ở bottom (khớp 100% mockup)
                          SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF16283A),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: 0,
                                  ),
                                  onPressed: () async {
                                    final updated = await Navigator.push<bool>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => BudgetSetupScreen(
                                          initialMonth: _selectedMonth,
                                        ),
                                      ),
                                    );
                                    if (updated == true) setState(() {});
                                  },
                                  child: const Text(
                                    'Thiết lập ngân sách',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}
