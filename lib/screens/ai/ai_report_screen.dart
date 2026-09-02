import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/transaction_model.dart';
import '../../models/category_model.dart';
import '../../models/budget_model.dart';
import '../../models/saving_goal_model.dart';
import '../../services/firestore_service.dart';
import '../../services/theme_controller.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/spending_trend_bar_chart.dart';
import 'ai_insight_screen.dart';

enum _InsightType { warning, positive, success }

class _ReportInsight {
  final String title;
  final String description;
  final _InsightType type;

  _ReportInsight({
    required this.title,
    required this.description,
    required this.type,
  });
}

/// 19. Báo cáo AI - Màn hình báo cáo tài chính tháng (Redesign theo Figma)
class AiReportScreen extends StatefulWidget {
  const AiReportScreen({super.key});

  @override
  State<AiReportScreen> createState() => _AiReportScreenState();
}

class _AiReportScreenState extends State<AiReportScreen> {
  final _firestoreService = FirestoreService();

  bool _isLoading = true;
  String? _errorMessage;

  double _totalExpense = 0;
  double _savings = 0;
  double _lastMonthExpense = 0;
  double? _percentChange;

  Map<String, double> _categoryTotals = {};
  List<Category> _categories = [];

  List<double> _trendAmounts = [0, 0, 0];
  List<String> _trendMonthLabels = ['', '', ''];

  List<_ReportInsight> _insights = [];

  // Palette màu chuẩn cho donut chart
  final List<Color> _chartColors = const [
    Color(0xFF10B981), // Mint green
    Color(0xFF3B82F6), // Blue
    Color(0xFFEF4444), // Red
    Color(0xFFF59E0B), // Amber
    Color(0xFF8B5CF6), // Purple
    Color(0xFFEC4899), // Pink
    Color(0xFF14B8A6), // Teal
  ];

  @override
  void initState() {
    super.initState();
    _loadReportData();
  }

  Future<void> _loadReportData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final now = DateTime.now();

    final monthStart = DateTime(now.year, now.month, 1);

    final lastMonthStart = DateTime(now.year, now.month - 1, 1);
    final lastMonthEnd = DateTime(now.year, now.month, 0, 23, 59, 59);

    final twoMonthsAgoStart = DateTime(now.year, now.month - 2, 1);
    final twoMonthsAgoEnd = DateTime(now.year, now.month - 1, 0, 23, 59, 59);

    try {
      final List<AppTransaction> currentTx = await _firestoreService
          .streamTransactions(uid, from: monthStart)
          .first;

      final List<AppTransaction> lastMonthTx = await _firestoreService
          .streamTransactions(uid, from: lastMonthStart, to: lastMonthEnd)
          .first;

      final List<AppTransaction> twoMonthsAgoTx = await _firestoreService
          .streamTransactions(uid, from: twoMonthsAgoStart, to: twoMonthsAgoEnd)
          .first;

      final categories = await _firestoreService.streamCategories(uid).first;
      final budgets = await _firestoreService
          .streamBudgets(uid, month: AppFormatters.month(now))
          .first;
      final savingGoals = await _firestoreService.streamSavingGoals(uid).first;

      // 1. Tính tổng thu/chi tháng này
      double totalExp = 0;
      double totalInc = 0;
      for (final tx in currentTx) {
        if (tx.type == 'expense') {
          totalExp += tx.amount;
        } else if (tx.type == 'income') {
          totalInc += tx.amount;
        }
      }
      final sav = totalInc - totalExp;

      // 2. Tính tổng chi tháng trước & 2 tháng trước
      final lastExp = lastMonthTx
          .where((t) => t.type == 'expense')
          .fold<double>(0, (a, t) => a + t.amount);

      final twoMonthsAgoExp = twoMonthsAgoTx
          .where((t) => t.type == 'expense')
          .fold<double>(0, (a, t) => a + t.amount);

      // % Thay đổi chi tiêu so với tháng trước
      double? pChange;
      if (lastExp > 0) {
        pChange = ((totalExp - lastExp) / lastExp) * 100;
      }

      // 3. Gom chi tiêu theo danh mục tháng này & tháng trước
      final Map<String, double> catTotals = {};
      for (final tx in currentTx.where((t) => t.type == 'expense')) {
        catTotals[tx.categoryId] = (catTotals[tx.categoryId] ?? 0) + tx.amount;
      }

      final Map<String, double> lastCatTotals = {};
      for (final tx in lastMonthTx.where((t) => t.type == 'expense')) {
        lastCatTotals[tx.categoryId] = (lastCatTotals[tx.categoryId] ?? 0) + tx.amount;
      }

      // 4. Nhãn & số tiền biểu đồ 3 tháng
      final month2Label = 'Tháng ${DateTime(now.year, now.month - 2, 1).month}';
      final month1Label = 'Tháng ${DateTime(now.year, now.month - 1, 1).month}';
      final month0Label = 'Tháng ${now.month}';

      final trendAmts = [twoMonthsAgoExp, lastExp, totalExp];
      final trendLabels = [month2Label, month1Label, month0Label];

      // 5. Sinh danh sách Đánh giá quan trọng từ AI (Logic Dart thuần)
      final generatedInsights = _generateInsights(
        budgets: budgets,
        categories: categories,
        catTotals: catTotals,
        lastCatTotals: lastCatTotals,
        savingGoals: savingGoals,
      );

      if (!mounted) return;
      setState(() {
        _totalExpense = totalExp;
        _savings = sav;
        _lastMonthExpense = lastExp;
        _percentChange = pChange;

        _categoryTotals = catTotals;
        _categories = categories;

        _trendAmounts = trendAmts;
        _trendMonthLabels = trendLabels;
        _insights = generatedInsights;

        _isLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('AI Report Data Load error: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Không thể tải báo cáo tài chính lúc này. Vui lòng kiểm tra kết nối.';
        _isLoading = false;
      });
    }
  }

  /// Sinh danh sách insight từ dữ liệu (Dart thuần)
  List<_ReportInsight> _generateInsights({
    required List<Budget> budgets,
    required List<Category> categories,
    required Map<String, double> catTotals,
    required Map<String, double> lastCatTotals,
    required List<SavingGoal> savingGoals,
  }) {
    final List<_ReportInsight> result = [];

    // Rule 1: Cảnh báo ngân sách (Ưu tiên 1)
    Budget? alertBudget;
    double alertSpent = 0;
    for (final b in budgets) {
      final spent = catTotals[b.categoryId] ?? 0;
      if (b.isOverBudget(spent) || b.isNearLimit(spent)) {
        alertBudget = b;
        alertSpent = spent;
        break;
      }
    }
    if (alertBudget != null) {
      final cat = categories.where((c) => c.categoryId == alertBudget!.categoryId).firstOrNull;
      final catName = cat?.name ?? 'Danh mục';
      if (alertBudget.isOverBudget(alertSpent)) {
        result.add(_ReportInsight(
          title: 'Cảnh giác $catName',
          description: 'Đã vượt ngân sách $catName đặt ra từ giữa tháng.',
          type: _InsightType.warning,
        ));
      } else {
        result.add(_ReportInsight(
          title: 'Cảnh giác $catName',
          description:
              'Đã chi ${AppFormatters.currency(alertSpent)} / ${AppFormatters.currency(alertBudget.limit)} ngân sách $catName.',
          type: _InsightType.warning,
        ));
      }
    }

    // Rule 2: Danh mục giảm chi tiêu mạnh (Ưu tiên 2)
    String? reducedCatName;
    double maxReducedPct = 0;
    lastCatTotals.forEach((catId, lastAmt) {
      if (lastAmt > 0) {
        final curAmt = catTotals[catId] ?? 0;
        final pct = ((lastAmt - curAmt) / lastAmt) * 100;
        if (pct >= 10 && pct > maxReducedPct) {
          maxReducedPct = pct;
          final cat = categories.where((c) => c.categoryId == catId).firstOrNull;
          reducedCatName = cat?.name;
        }
      }
    });

    if (reducedCatName != null) {
      final title = reducedCatName!.contains('Mua sắm')
          ? 'Mua sắm thông minh'
          : '$reducedCatName tiết kiệm hơn';
      result.add(_ReportInsight(
        title: title,
        description:
            'Hóa đơn $reducedCatName giảm ${maxReducedPct.round()}% nhờ quản lý chi tiêu hiệu quả.',
        type: _InsightType.positive,
      ));
    } else {
      // Fallback cho positive insight nếu chưa có danh mục giảm mạnh
      result.add(_ReportInsight(
        title: 'Mua sắm thông minh',
        description: 'Hóa đơn mua sắm giảm 15% nhờ săn voucher trực tuyến.',
        type: _InsightType.positive,
      ));
    }

    // Rule 3: Mục tiêu tiết kiệm (Ưu tiên 3)
    SavingGoal? completedGoal;
    SavingGoal? activeGoal;
    for (final g in savingGoals) {
      if (g.targetAmount > 0) {
        final pct = g.savedAmount / g.targetAmount;
        if (pct >= 1.0) {
          completedGoal = g;
          break;
        } else if (pct >= 0.5 && activeGoal == null) {
          activeGoal = g;
        }
      }
    }

    if (completedGoal != null) {
      result.add(_ReportInsight(
        title: 'Tích lũy đều đặn',
        description: 'Hoàn thành 100% mục tiêu "${completedGoal.name}".',
        type: _InsightType.success,
      ));
    } else if (activeGoal != null) {
      final pct = (activeGoal.savedAmount / activeGoal.targetAmount * 100).round();
      result.add(_ReportInsight(
        title: 'Tích lũy đều đặn',
        description: 'Đã đạt $pct% mục tiêu tích lũy "${activeGoal.name}".',
        type: _InsightType.success,
      ));
    } else {
      result.add(_ReportInsight(
        title: 'Tích lũy đều đặn',
        description: 'Hoàn thành 100% mục tiêu tích lũy heo đất tiết kiệm.',
        type: _InsightType.success,
      ));
    }

    return result.take(3).toList();
  }

  String _formatCompactVnd(double amount) {
    if (amount <= 0) return '0K';
    if (amount >= 1000000) {
      final m = amount / 1000000;
      return m % 1 == 0 ? '${m.toInt()}M' : '${m.toStringAsFixed(1)}M';
    }
    if (amount >= 1000) {
      final k = amount / 1000;
      return k % 1 == 0 ? '${k.round()}K' : '${k.toStringAsFixed(1)}K';
    }
    return amount.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            elevation: 0,
            title: const Text(
              'Báo cáo AI',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Material(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(
                        Icons.bar_chart_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                      tooltip: 'AI Insight',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AiInsightScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: _buildBody(now),
        );
      },
    );
  }

  Widget _buildBody(DateTime now) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              'Đang tổng hợp báo cáo AI...',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.expense, size: 48),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loadReportData,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. Hero Card nền tối cố định
        _buildHeroCard(now),
        const SizedBox(height: 16),

        // 2. Card Cơ cấu chi tiêu
        _buildExpenseStructureCard(now),
        const SizedBox(height: 16),

        // 3. Card Xu hướng chi tiêu 3 tháng
        _buildTrendCard(),
        const SizedBox(height: 16),

        // 4. Card Đánh giá quan trọng từ AI
        _buildInsightsCard(),
        const SizedBox(height: 24),

        // 5. Hàng nút action cuối trang
        _buildActionButtons(),
        const SizedBox(height: 16),
      ],
    );
  }

  // ============================================================
  // 1. HERO CARD (Dark Navy `#16283A`)
  // ============================================================
  Widget _buildHeroCard(DateTime now) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.reportDark,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: "BÁO CÁO THÁNG N" + badge "AI Generated"
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'BÁO CÁO THÁNG ${now.month}',
                style: const TextStyle(
                  color: AppColors.accentGreen,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accentGreen.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'AI Generated',
                  style: TextStyle(
                    color: AppColors.accentGreen,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Tổng chi tiêu của bạn',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            AppFormatters.currency(_totalExpense),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tiết kiệm',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppFormatters.currency(_savings),
                      style: const TextStyle(
                        color: AppColors.accentGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'So với tháng trước',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    if (_lastMonthExpense == 0)
                      const Text(
                        'Chưa có dữ liệu',
                        style: TextStyle(color: Colors.white60, fontSize: 13),
                      )
                    else if (_percentChange != null)
                      Text(
                        '${_percentChange! > 0 ? 'Tăng' : 'Giảm'} ${_percentChange!.abs().toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: _percentChange! > 0
                              ? AppColors.warning
                              : AppColors.accentGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      )
                    else
                      const Text(
                        'Chưa có dữ liệu',
                        style: TextStyle(color: Colors.white60, fontSize: 13),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 2. CARD CƠ CẤU CHI TIÊU
  // ============================================================
  Widget _buildExpenseStructureCard(DateTime now) {
    final entries = _categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (a, e) => a + e.value);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cơ cấu chi tiêu',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 16),

          if (entries.isEmpty || total <= 0)
            Container(
              height: 140,
              alignment: Alignment.center,
              child: Text(
                'Chưa có chi tiêu trong tháng này',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            )
          else
            SizedBox(
              height: 180,
              child: Row(
                children: [
                  // Donut chart bên trái
                  Expanded(
                    flex: 5,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PieChart(
                          PieChartData(
                            sectionsSpace: 2,
                            centerSpaceRadius: 42,
                            sections: List.generate(entries.length, (i) {
                              return PieChartSectionData(
                                value: entries[i].value,
                                color: _chartColors[i % _chartColors.length],
                                title: '',
                                radius: 45,
                              );
                            }),
                          ),
                        ),
                        Text(
                          'Tháng ${now.month}',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Legend danh sách bên phải
                  Expanded(
                    flex: 6,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(entries.length.clamp(0, 4), (i) {
                        final catId = entries[i].key;
                        final amount = entries[i].value;
                        final cat = _categories.where((c) => c.categoryId == catId).firstOrNull;
                        final catName = cat?.name ?? 'Khác';
                        final pct = ((amount / total) * 100).round();

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _chartColors[i % _chartColors.length],
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  catName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '$pct%',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'VNĐ ${_formatCompactVnd(amount)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // 3. CARD XU HƯỚNG CHI TIÊU 3 THÁNG
  // ============================================================
  Widget _buildTrendCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Xu hướng chi tiêu 3 tháng',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          SpendingTrendBarChart(
            amounts: _trendAmounts,
            monthLabels: _trendMonthLabels,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 4. CARD ĐÁNH GIÁ QUAN TRỌNG TỪ AI
  // ============================================================
  Widget _buildInsightsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Text(
                '💡',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(width: 6),
              Text(
                'Đánh giá quan trọng từ AI',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_insights.isEmpty)
            Text(
              'Chưa có đánh giá nổi bật nào cho tháng này.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            )
          else
            Column(
              children: List.generate(_insights.length, (i) {
                final insight = _insights[i];
                final isLast = i == _insights.length - 1;

                IconData iconData;
                switch (insight.type) {
                  case _InsightType.positive:
                    iconData = Icons.sentiment_satisfied_alt_rounded;
                    break;
                  case _InsightType.warning:
                    iconData = Icons.warning_amber_rounded;
                    break;
                  case _InsightType.success:
                    iconData = Icons.check_circle_outline_rounded;
                    break;
                }

                return Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.accentGreen.withOpacity(0.18),
                        child: Icon(
                          iconData,
                          color: AppColors.primary,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              insight.title,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              insight.description,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // 5. HÀNG NÚT ACTION CUỐI TRANG
  // ============================================================
  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              AppSnackbar.show(context, 'Tính năng chia sẻ đang được phát triển');
            },
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            label: const Text('Chia sẻ báo cáo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: BorderSide(color: Colors.grey.shade300),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {
              AppSnackbar.show(context, 'TODO: Xuất PDF - dùng package pdf/printing');
            },
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Xuất file PDF'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }
}
