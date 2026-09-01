import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/user_model.dart';
import '../../models/transaction_model.dart';
import '../../models/category_model.dart';
import '../../models/wallet_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../services/theme_controller.dart';
import '../../widgets/transaction_card.dart';
import '../../widgets/dashboard_chart.dart';
import '../../widgets/stream_error_widget.dart';
import '../ai/ai_insight_screen.dart';
import '../home/transaction_list_screen.dart';

/// 9. Home Dashboard
/// Hiển thị: Xin chào + avatar + tên | Tổng số dư | Thu tháng | Chi tháng
/// Bên dưới: Bộ lọc nửa năm -> Biểu đồ cột tương tác -> Donut theo tháng chọn -> Giao dịch gần đây -> AI Insight
class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  int _selectedMonthIndex = 5; // mặc định = tháng cuối cùng (tháng hiện tại) trong mảng 6 tháng
  late int _selectedYear;
  late int _selectedHalf; // 1 = Th1-Th6, 2 = Th7-Th12

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedHalf = now.month <= 6 ? 1 : 2;
    _selectedMonthIndex = _defaultMonthIndex();
  }

  /// Tính index mặc định: tháng hiện tại trong khối, hoặc tháng cuối cùng
  int _defaultMonthIndex() {
    final now = DateTime.now();
    if (_selectedYear == now.year) {
      final firstMonthOfHalf = _selectedHalf == 1 ? 1 : 7;
      final offset = now.month - firstMonthOfHalf;
      if (offset >= 0 && offset <= 5) return offset;
    }
    return 5; // tháng cuối khối
  }

  /// Tính khoảng from/to từ year + half
  DateTime get _filterFrom => DateTime(_selectedYear, _selectedHalf == 1 ? 1 : 7, 1);
  DateTime get _filterTo {
    if (_selectedHalf == 1) {
      return DateTime(_selectedYear, 6, 30, 23, 59, 59);
    } else {
      return DateTime(_selectedYear, 12, 31, 23, 59, 59);
    }
  }

  /// Tính dữ liệu thu/chi cho 6 tháng theo khối đang chọn
  Map<String, List<double>> _build6MonthData(List<AppTransaction> allTx) {
    final incomeByMonth = <double>[];
    final expenseByMonth = <double>[];
    final firstMonth = _selectedHalf == 1 ? 1 : 7;

    for (int i = 0; i < 6; i++) {
      final monthNum = firstMonth + i;
      final month = DateTime(_selectedYear, monthNum, 1);
      final nextMonth = DateTime(_selectedYear, monthNum + 1, 1);
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
    final firstMonth = _selectedHalf == 1 ? 1 : 7;
    final showYear = _selectedYear != now.year;
    final yearSuffix = showYear ? '/${_selectedYear % 100}' : '';
    return [
      for (int i = 0; i < 6; i++)
        'Th${firstMonth + i}$yearSuffix'
    ];
  }

  /// Lấy danh sách giao dịch của tháng được chọn trong biểu đồ
  List<AppTransaction> _getSelectedMonthTx(List<AppTransaction> allTx) {
    final firstMonth = _selectedHalf == 1 ? 1 : 7;
    final selectedMonth = firstMonth + _selectedMonthIndex;
    final monthStart = DateTime(_selectedYear, selectedMonth, 1);
    final monthEnd = DateTime(_selectedYear, selectedMonth + 1, 1);
    return allTx.where((t) => !t.date.isBefore(monthStart) && t.date.isBefore(monthEnd)).toList();
  }

  /// Lấy DateTime đại diện cho tháng đang chọn
  DateTime get _selectedMonthDate {
    final firstMonth = _selectedHalf == 1 ? 1 : 7;
    return DateTime(_selectedYear, firstMonth + _selectedMonthIndex, 1);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, _, __) {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        final firestoreService = FirestoreService();
        final now = DateTime.now();
        final currentMonthStart = DateTime(now.year, now.month, 1);

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: StreamBuilder<AppUser?>(
              stream: firestoreService.streamUserProfile(uid),
              builder: (context, userSnap) {
                if (userSnap.hasError) return StreamErrorWidget(error: userSnap.error.toString());
                final user = userSnap.data;

                return StreamBuilder<List<Wallet>>(
                  stream: firestoreService.streamWallets(uid),
                  builder: (context, walletSnap) {
                    if (walletSnap.hasError) return StreamErrorWidget(error: walletSnap.error.toString());
                    final wallets = walletSnap.data ?? [];
                    final totalBalance = wallets.fold<double>(0, (a, w) => a + w.balance);

                    // Load transactions cho khối 6 tháng đang chọn
                    return StreamBuilder<List<AppTransaction>>(
                      stream: firestoreService.streamTransactions(uid, from: _filterFrom, to: _filterTo),
                      builder: (context, txSnap) {
                        if (txSnap.hasError) return StreamErrorWidget(error: txSnap.error.toString());
                        final allTx = txSnap.data ?? [];

                        // Giao dịch tháng hiện tại thật (cho chips Thu/Chi)
                        final currentMonthTx = allTx.where((t) => !t.date.isBefore(currentMonthStart)).toList();
                        final bool currentMonthInFilter = _selectedYear == now.year &&
                            ((_selectedHalf == 1 && now.month <= 6) || (_selectedHalf == 2 && now.month >= 7));

                        final chartData = _build6MonthData(allTx);
                        final monthLabels = _build6MonthLabels();
                        final selectedMonthTx = _getSelectedMonthTx(allTx);

                        if (currentMonthInFilter) {
                          final income = currentMonthTx
                              .where((t) => t.type == 'income')
                              .fold<double>(0, (a, t) => a + t.amount);
                          final expense = currentMonthTx
                              .where((t) => t.type == 'expense')
                              .fold<double>(0, (a, t) => a + t.amount);

                          return StreamBuilder<List<Category>>(
                            stream: firestoreService.streamCategories(uid),
                            builder: (context, catSnap) {
                              if (catSnap.hasError) return StreamErrorWidget(error: catSnap.error.toString());
                              final categories = catSnap.data ?? [];
                              return _buildDashboardContent(
                                user: user,
                                totalBalance: totalBalance,
                                income: income,
                                expense: expense,
                                chartData: chartData,
                                monthLabels: monthLabels,
                                selectedMonthTx: selectedMonthTx,
                                recentTx: allTx.where((t) => !t.date.isBefore(currentMonthStart)).toList(),
                                allTx: allTx,
                                categories: categories,
                              );
                            },
                          );
                        } else {
                          return StreamBuilder<List<AppTransaction>>(
                            stream: firestoreService.streamTransactions(uid, from: currentMonthStart),
                            builder: (context, currentTxSnap) {
                              final currentTx = currentTxSnap.data ?? [];
                              final income = currentTx
                                  .where((t) => t.type == 'income')
                                  .fold<double>(0, (a, t) => a + t.amount);
                              final expense = currentTx
                                  .where((t) => t.type == 'expense')
                                  .fold<double>(0, (a, t) => a + t.amount);

                              return StreamBuilder<List<Category>>(
                                stream: firestoreService.streamCategories(uid),
                                builder: (context, catSnap) {
                                  if (catSnap.hasError) return StreamErrorWidget(error: catSnap.error.toString());
                                  final categories = catSnap.data ?? [];
                                  return _buildDashboardContent(
                                    user: user,
                                    totalBalance: totalBalance,
                                    income: income,
                                    expense: expense,
                                    chartData: chartData,
                                    monthLabels: monthLabels,
                                    selectedMonthTx: selectedMonthTx,
                                    recentTx: currentTx,
                                    allTx: allTx,
                                    categories: categories,
                                  );
                                },
                              );
                            },
                          );
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildDashboardContent({
    required AppUser? user,
    required double totalBalance,
    required double income,
    required double expense,
    required Map<String, List<double>> chartData,
    required List<String> monthLabels,
    required List<AppTransaction> selectedMonthTx,
    required List<AppTransaction> recentTx,
    required List<AppTransaction> allTx,
    required List<Category> categories,
  }) {
    final selectedDate = _selectedMonthDate;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _buildHeader(context, user, totalBalance, income, expense),
        const SizedBox(height: 16),
        _buildSectionTitle('Thu / Chi 6 tháng gần đây (triệu VNĐ)'),
        _buildHalfYearFilter(),
        _buildChartLegend(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: IncomeExpenseBarChart(
            incomeByMonth: chartData['income']!,
            expenseByMonth: chartData['expense']!,
            monthLabels: monthLabels,
            selectedIndex: _selectedMonthIndex,
            onMonthTap: (i) => setState(() => _selectedMonthIndex = i),
          ),
        ),
        const SizedBox(height: 16),
        _buildSectionTitle(
          'Top danh mục chi tiêu — Tháng ${selectedDate.month}/${selectedDate.year}',
        ),
        _buildCategoryPie(selectedMonthTx, categories),
        const SizedBox(height: 16),
        _buildSectionTitle(
          'Giao dịch gần đây',
          actionLabel: 'Xem tất cả',
          onAction: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => const TransactionListScreen()),
          ),
        ),
        if (recentTx.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Chưa có giao dịch nào tháng này',
                style: TextStyle(color: AppColors.textSecondary)),
          )
        else
          ...recentTx.take(5).map((tx) => TransactionCard(
                transaction: tx,
                category: categories
                    .where((c) => c.categoryId == tx.categoryId)
                    .firstOrNull,
              )),
        const SizedBox(height: 16),
        _buildAiInsightCard(context),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, AppUser? user, double totalBalance, double income, double expense) {
    final now = DateTime.now();
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
              // Avatar
              _buildAvatar(user),
              const SizedBox(width: 12),
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
                    if (user?.occupation != null && user!.occupation!.isNotEmpty)
                      Text(
                        user.occupation!,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
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
          Text('TỔNG SỐ DƯ',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 13,
                  letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(
            AppFormatters.currency(totalBalance),
            style: const TextStyle(
                color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildStatChip(
                    'Thu nhập (Tháng ${now.month})', income, Icons.arrow_downward_rounded, AppColors.income),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatChip(
                    'Chi tiêu (Tháng ${now.month})', expense, Icons.arrow_upward_rounded, AppColors.expense),
              ),
            ],
          ),
          if (user?.monthlyIncome != null && user!.monthlyIncome > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Thu nhập khai báo trong hồ sơ: ${AppFormatters.currency(user.monthlyIncome)}/tháng',
                style: const TextStyle(color: Colors.white60, fontSize: 11, fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }

  /// Avatar tròn: dùng ảnh local từ user.avatar, fallback icon mặc định
  Widget _buildAvatar(AppUser? user) {
    final avatarPath = user?.avatar;
    if (avatarPath != null && avatarPath.isNotEmpty) {
      final file = File(avatarPath);
      return CircleAvatar(
        radius: 22,
        backgroundColor: Colors.white.withOpacity(0.2),
        backgroundImage: FileImage(file),
        onBackgroundImageError: (_, __) {},
      );
    }
    return CircleAvatar(
      radius: 22,
      backgroundColor: Colors.white.withOpacity(0.2),
      child: const Icon(Icons.person, color: Colors.white, size: 24),
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
            Flexible(
              child: Text(label,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  overflow: TextOverflow.ellipsis),
            ),
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

  /// Bộ lọc: Dropdown năm + SegmentedButton nửa năm
  Widget _buildHalfYearFilter() {
    final now = DateTime.now();
    final years = [for (int y = now.year - 4; y <= now.year; y++) y];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Dropdown chọn năm
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.textSecondary.withOpacity(0.2)),
            ),
            child: DropdownButton<int>(
              value: _selectedYear,
              underline: const SizedBox(),
              isDense: true,
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
              items: years.map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
              onChanged: (y) {
                if (y == null) return;
                setState(() {
                  _selectedYear = y;
                  _selectedMonthIndex = _defaultMonthIndex();
                });
              },
            ),
          ),
          const SizedBox(width: 10),
          // Toggle nửa năm
          Expanded(
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('Th1–Th6', style: TextStyle(fontSize: 12))),
                ButtonSegment(value: 2, label: Text('Th7–Th12', style: TextStyle(fontSize: 12))),
              ],
              selected: {_selectedHalf},
              onSelectionChanged: (selection) {
                setState(() {
                  _selectedHalf = selection.first;
                  _selectedMonthIndex = _defaultMonthIndex();
                });
              },
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return AppColors.primary;
                  }
                  return AppColors.card;
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Colors.white;
                  }
                  return AppColors.textSecondary;
                }),
                side: WidgetStateProperty.all(
                  BorderSide(color: AppColors.textSecondary.withOpacity(0.2)),
                ),
                shape: WidgetStateProperty.all(
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Legend row: ● Thu nhập  ● Chi tiêu
  Widget _buildChartLegend() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: AppColors.income,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 4),
          Text('Thu nhập', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(width: 16),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: AppColors.expense,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 4),
          Text('Chi tiêu', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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
          Expanded(
            child: Text(title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                overflow: TextOverflow.ellipsis),
          ),
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
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('AI Phân tích chi tiêu',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: AppColors.aiAccent)),
                    const SizedBox(height: 2),
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
