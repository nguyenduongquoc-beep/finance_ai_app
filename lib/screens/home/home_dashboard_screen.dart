import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/user_model.dart';
import '../../models/transaction_model.dart';
import '../../models/category_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/transaction_card.dart';
import '../../widgets/dashboard_chart.dart';
import '../../widgets/stream_error_widget.dart';
import '../ai/ai_insight_screen.dart';
import '../home/transaction_list_screen.dart';

/// 9. Home Dashboard
/// Hiển thị: Xin chào + tên | Số dư | Thu tháng này | Chi tháng này
/// Bên dưới: Biểu đồ thực 6 tháng -> Top danh mục -> Giao dịch gần đây -> AI Insight
class HomeDashboardScreen extends StatelessWidget {
  const HomeDashboardScreen({super.key});

  /// Tính dữ liệu thu/chi cho 6 tháng gần nhất
  Map<String, List<double>> _build6MonthData(List<AppTransaction> allTx) {
    final now = DateTime.now();
    final incomeByMonth = <double>[];
    final expenseByMonth = <double>[];

    for (int i = 5; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final nextMonth = DateTime(month.year, month.month + 1, 1);
      final monthTx = allTx.where((t) {
        final d = t.date;
        return !d.isBefore(month) && d.isBefore(nextMonth);
      });
      final income = monthTx
          .where((t) => t.type == 'income')
          .fold<double>(0, (a, t) => a + t.amount);
      final expense = monthTx
          .where((t) => t.type == 'expense')
          .fold<double>(0, (a, t) => a + t.amount);

      // Normalize to millions for chart readability
      incomeByMonth.add(income / 1e6);
      expenseByMonth.add(expense / 1e6);
    }
    return {'income': incomeByMonth, 'expense': expenseByMonth};
  }

  List<String> _build6MonthLabels() {
    final now = DateTime.now();
    const vi = ['T1', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'T8', 'T9', 'T10', 'T11', 'T12'];
    return [
      for (int i = 5; i >= 0; i--)
        vi[(DateTime(now.year, now.month - i).month - 1)]
    ];
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final firestoreService = FirestoreService();
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    // 6 months ago
    final sixMonthsAgo = DateTime(now.year, now.month - 5, 1);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: StreamBuilder<AppUser?>(
          stream: firestoreService.streamUserProfile(uid),
          builder: (context, userSnap) {
            if (userSnap.hasError) return StreamErrorWidget(error: userSnap.error.toString());
            final user = userSnap.data;
            // Load all 6-month transactions for chart + current month for stats
            return StreamBuilder<List<AppTransaction>>(
              stream: firestoreService.streamTransactions(uid, from: sixMonthsAgo),
              builder: (context, txSnap) {
                if (txSnap.hasError) return StreamErrorWidget(error: txSnap.error.toString());
                final allTx = txSnap.data ?? [];
                final monthTx = allTx.where((t) => !t.date.isBefore(monthStart)).toList();
                final income = monthTx
                    .where((t) => t.type == 'income')
                    .fold<double>(0, (a, t) => a + t.amount);
                final expense = monthTx
                    .where((t) => t.type == 'expense')
                    .fold<double>(0, (a, t) => a + t.amount);

                final chartData = _build6MonthData(allTx);
                final monthLabels = _build6MonthLabels();

                return StreamBuilder<List<Category>>(
                  stream: firestoreService.streamCategories(uid),
                  builder: (context, catSnap) {
                    if (catSnap.hasError) return StreamErrorWidget(error: catSnap.error.toString());
                    final categories = catSnap.data ?? [];
                    return ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        _buildHeader(context, user, income, expense),
                        const SizedBox(height: 16),
                        _buildSectionTitle('Thu / Chi 6 tháng gần đây (triệu đ)'),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: IncomeExpenseBarChart(
                            incomeByMonth: chartData['income']!,
                            expenseByMonth: chartData['expense']!,
                            monthLabels: monthLabels,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildSectionTitle('Top danh mục chi tiêu tháng này'),
                        _buildCategoryPie(monthTx, categories),
                        const SizedBox(height: 16),
                        _buildSectionTitle(
                          'Giao dịch gần đây',
                          actionLabel: 'Xem tất cả',
                          onAction: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const TransactionListScreen()),
                          ),
                        ),
                        if (monthTx.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text('Chưa có giao dịch nào tháng này',
                                style: TextStyle(color: AppColors.textSecondary)),
                          )
                        else
                          ...monthTx.take(5).map((tx) => TransactionCard(
                                transaction: tx,
                                category: categories
                                    .where((c) => c.categoryId == tx.categoryId)
                                    .firstOrNull,
                              )),
                        const SizedBox(height: 16),
                        _buildAiInsightCard(context),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppUser? user, double income, double expense) {
    final balance = income - expense;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1B5E47), Color(0xFF2E7D6B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Xin chào,',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.8), fontSize: 14)),
                    Text(
                      user?.name ?? 'Bạn',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.notifications_outlined,
                    color: Colors.white, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Số dư tháng này',
              style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            AppFormatters.currency(balance),
            style: const TextStyle(
                color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildStatChip(
                    'Thu tháng này', income, Icons.arrow_downward_rounded, AppColors.income),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatChip(
                    'Chi tháng này', expense, Icons.arrow_upward_rounded, AppColors.expense),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, double value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 13, color: Colors.white70),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ]),
          const SizedBox(height: 4),
          Text(
            AppFormatters.number(value),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, {String? actionLabel, VoidCallback? onAction}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              child: Text(actionLabel,
                  style: const TextStyle(color: AppColors.primary, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryPie(
      List<AppTransaction> transactions, List<Category> categories) {
    final Map<String, double> totals = {};
    for (final tx in transactions.where((t) => t.type == 'expense')) {
      final cat = categories.where((c) => c.categoryId == tx.categoryId).firstOrNull;
      final name = cat?.name ?? 'Khác';
      totals[name] = (totals[name] ?? 0) + tx.amount;
    }
    if (totals.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text('Chưa có dữ liệu chi tiêu tháng này',
            style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: CategoryPieChart(
        categoryTotals: totals,
        colors: const [
          AppColors.expense,
          AppColors.warning,
          AppColors.primary,
          AppColors.aiAccent,
          Colors.blueGrey,
          Colors.brown,
          Colors.teal,
        ],
      ),
    );
  }

  Widget _buildAiInsightCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AiInsightScreen()),
        ),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.aiAccent.withOpacity(0.08),
                AppColors.aiAccent.withOpacity(0.15),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.aiAccent.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.aiAccent.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome, color: AppColors.aiAccent, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI Phân tích chi tiêu',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: AppColors.aiAccent)),
                    SizedBox(height: 2),
                    Text('Xem nhận xét và dự báo thông minh',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.aiAccent),
            ],
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
