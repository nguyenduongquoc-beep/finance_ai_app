import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/financial_issue.dart';
import '../../models/transaction_model.dart';
import '../../models/category_model.dart';
import '../../models/trend_result.dart';
import '../../services/firestore_service.dart';
import '../../services/ai_service.dart';
import '../../services/financial_analytics_service.dart';
import '../../services/theme_controller.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/weekly_heatmap_card.dart';
import '../../widgets/trend_chart_card.dart';

/// 18. AI Insight — Phân tích có căn cứ + AI giải thích theo yêu cầu
class AiInsightScreen extends StatefulWidget {
  const AiInsightScreen({super.key});

  @override
  State<AiInsightScreen> createState() => _AiInsightScreenState();
}

class _CategoryCut {
  final String categoryName;
  final double currentDailyAvg;
  final double targetDailyAvg;

  _CategoryCut({
    required this.categoryName,
    required this.currentDailyAvg,
    required this.targetDailyAvg,
  });
}

class _AiInsightScreenState extends State<AiInsightScreen> {
  final _aiService = AiService();
  final _firestoreService = FirestoreService();
  final _analyticsService = FinancialAnalyticsService();

  bool _isLoading = true;
  String? _errorMessage;

  int _healthScore = 100;
  List<FinancialIssue> _issues = [];
  List<_CategoryCut> _topCuts = [];
  Map<String, List<int>> _weeklyHeatmap = {};
  List<double> _monthlySpendingForTrend = [];

  // Local session state for UI actions
  final Set<String> _dismissedKeys = {};
  final Map<String, String> _aiExplanations = {};
  final Map<String, bool> _aiLoadingMap = {};

  // Lazy load state for 6-month trend
  bool _isLoadingTrend = false;
  bool _hasLoadedTrend = false;
  TrendResult? _trendResult;

  // Lazy load state for Overview AI
  bool _isLoadingOverview = false;
  bool _hasLoadedOverview = false;
  String? _spendingAnalysis;
  String? _monthEndPrediction;

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  /// Dart thuần — Nhanh, không cần chờ Gemini AI
  Future<void> _loadInsights() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final last30Days = now.subtract(const Duration(days: 30));

    final lastMonthStart = DateTime(now.year, now.month - 1, 1);
    final lastMonthEnd = DateTime(now.year, now.month, 0, 23, 59, 59);

    try {
      final transactions =
          await _firestoreService.streamTransactions(uid, from: last30Days).first;
      final categories = await _firestoreService.streamCategories(uid).first;
      final monthTransactions =
          await _firestoreService.streamTransactions(uid, from: monthStart).first;

      final lastMonthTransactions = await _firestoreService
          .streamTransactions(uid, from: lastMonthStart, to: lastMonthEnd)
          .first;

      final userProfile = await _firestoreService.getUserProfile(uid);
      final monthlyIncome = userProfile?.monthlyIncome ?? 0;

      // --- Financial Analytics Layer (Dart thuần, KHÔNG gọi AI) ---
      final issues = _analyticsService.detectIssues(
        currentMonthTx: monthTransactions,
        lastMonthTx: lastMonthTransactions,
        categories: categories,
        monthlyIncome: monthlyIncome,
      );
      final healthScore = _analyticsService.calculateHealthScore(issues);
      final heatmap = _analyticsService.computeWeeklyHeatmap(transactions, categories);

      // Top cuts (Cơ hội tiết kiệm)
      final Map<String, double> totals = {};
      for (final tx in transactions.where((t) => t.type == 'expense')) {
        final cat = categories.where((c) => c.categoryId == tx.categoryId).firstOrNull;
        final name = cat?.name ?? 'Khác';
        totals[name] = (totals[name] ?? 0) + tx.amount;
      }
      final sortedCats = totals.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topCuts = sortedCats.take(3).map((e) {
        final dailyAvg = e.value / 30;
        return _CategoryCut(
          categoryName: e.key,
          currentDailyAvg: dailyAvg,
          targetDailyAvg: dailyAvg * 0.75,
        );
      }).toList();

      // Dữ liệu 6 tháng chuẩn bị cho Trend chart
      final sixMonthsAgo = DateTime(now.year, now.month - 5, 1);
      final trendTransactions =
          await _firestoreService.streamTransactions(uid, from: sixMonthsAgo).first;
      final List<double> monthlySpending = [];
      for (int i = 5; i >= 0; i--) {
        final month = DateTime(now.year, now.month - i, 1);
        final monthEnd = DateTime(month.year, month.month + 1, 0);
        final monthTotal = trendTransactions
            .where((t) =>
                t.type == 'expense' &&
                t.date.isAfter(month.subtract(const Duration(days: 1))) &&
                t.date.isBefore(monthEnd.add(const Duration(days: 1))))
            .fold<double>(0, (a, t) => a + t.amount);
        monthlySpending.add(monthTotal);
      }

      if (!mounted) return;
      setState(() {
        _healthScore = healthScore;
        _issues = issues;
        _weeklyHeatmap = heatmap;
        _topCuts = topCuts;
        _monthlySpendingForTrend = monthlySpending;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('AI Insight Data Load error: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Không thể tải phân tích tài chính lúc này. Vui lòng kiểm tra kết nối.';
        _isLoading = false;
      });
    }
  }

  /// Lazy-load giải thích cho 1 vấn đề cụ thể
  Future<void> _explainIssue(FinancialIssue issue) async {
    final key = issue.title;
    setState(() => _aiLoadingMap[key] = true);
    try {
      final explanation = await _aiService.explainSingleIssue(issue);
      if (!mounted) return;
      setState(() {
        _aiExplanations[key] = explanation;
        _aiLoadingMap[key] = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiExplanations[key] = 'Không thể tải đề xuất từ AI lúc này.';
        _aiLoadingMap[key] = false;
      });
    }
  }

  /// Lazy-load giải thích cho 1 cơ hội tiết kiệm cụ thể
  Future<void> _explainCut(_CategoryCut cut) async {
    final key = 'cut_${cut.categoryName}';
    setState(() => _aiLoadingMap[key] = true);
    try {
      final explanation = await _aiService.suggestSpendingCuts(
        categoryName: cut.categoryName,
        currentDailyAvg: cut.currentDailyAvg,
        targetDailyAvg: cut.targetDailyAvg,
      );
      if (!mounted) return;
      setState(() {
        _aiExplanations[key] = explanation;
        _aiLoadingMap[key] = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiExplanations[key] = 'Không thể tải đề xuất từ AI lúc này.';
        _aiLoadingMap[key] = false;
      });
    }
  }

  /// Lazy-load phân tích xu hướng 6 tháng từ Gemini
  Future<void> _loadTrendLazy() async {
    if (_hasLoadedTrend || _isLoadingTrend) return;
    setState(() => _isLoadingTrend = true);
    try {
      final result = await _aiService.analyzeTrend(
        monthlySpending: _monthlySpendingForTrend,
      );
      if (!mounted) return;
      setState(() {
        _trendResult = result;
        _isLoadingTrend = false;
        _hasLoadedTrend = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingTrend = false;
      });
    }
  }

  /// Lazy-load nhận định tổng quan từ Gemini
  Future<void> _loadOverviewLazy() async {
    if (_hasLoadedOverview || _isLoadingOverview) return;
    setState(() => _isLoadingOverview = true);

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final last30Days = now.subtract(const Duration(days: 30));
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;

    try {
      final transactions =
          await _firestoreService.streamTransactions(uid, from: last30Days).first;
      final categories = await _firestoreService.streamCategories(uid).first;
      final monthTransactions =
          await _firestoreService.streamTransactions(uid, from: monthStart).first;

      final spentSoFar = monthTransactions
          .where((t) => t.type == 'expense')
          .fold<double>(0, (a, t) => a + t.amount);

      String analysis = 'Không thể tải phân tích chi tiêu lúc này.';
      String prediction = 'Không thể tải dự đoán chi tiêu lúc này.';

      await Future.wait([
        _aiService.analyzeSpendingHabits(
          transactions: transactions,
          categories: categories,
        ).then((res) => analysis = res).catchError((_) => analysis),
        _aiService.predictMonthEnd(
          spentSoFar: spentSoFar,
          dayOfMonth: now.day,
          totalDaysInMonth: daysInMonth,
        ).then((res) => prediction = res).catchError((_) => prediction),
      ]);

      if (!mounted) return;
      setState(() {
        _spendingAnalysis = analysis;
        _monthEndPrediction = prediction;
        _isLoadingOverview = false;
        _hasLoadedOverview = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingOverview = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.aiAccent.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome, color: AppColors.aiAccent, size: 18),
                ),
                const SizedBox(width: 8),
                const Text('AI Insight'),
              ],
            ),
            actions: [
              if (!_isLoading)
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Làm mới',
                  onPressed: _loadInsights,
                ),
            ],
          ),
          body: _buildBody(),
        );
      },
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.aiAccent),
            const SizedBox(height: 16),
            Text('Đang tải dữ liệu phân tích...',
                style: TextStyle(color: AppColors.textSecondary)),
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
              Text(_errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loadInsights,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.aiAccent),
              ),
            ],
          ),
        ),
      );
    }

    final activeIssues = _issues.where((i) => !_dismissedKeys.contains(i.title)).toList();
    final activeCuts = _topCuts.where((c) => !_dismissedKeys.contains('cut_${c.categoryName}')).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. Điểm sức khỏe tài chính
        _buildHealthScoreCard(_healthScore),
        const SizedBox(height: 16),

        // 2. Vấn đề & Cơ hội (Danh sách thẻ gộp)
        _buildIssuesAndOpportunitiesSection(activeIssues, activeCuts),
        const SizedBox(height: 16),

        // 3. Tần suất chi tiêu theo tuần (Heatmap)
        WeeklyHeatmapCard(heatmapData: _weeklyHeatmap),
        const SizedBox(height: 16),

        // 4. Xu hướng chi tiêu 6 tháng (Lazy-load expansion)
        _buildTrendSection(),
        const SizedBox(height: 16),

        // 5. Nhận định tổng quan từ AI (Lazy-load expansion)
        _buildOverviewSection(),
        const SizedBox(height: 24),
      ],
    );
  }

  // ============================================================
  // 1. HEALTH SCORE CARD
  // ============================================================
  Widget _buildHealthScoreCard(int score) {
    final Color scoreColor;
    final String scoreLabel;
    final IconData scoreIcon;
    if (score >= 70) {
      scoreColor = AppColors.income;
      scoreLabel = 'Tốt';
      scoreIcon = Icons.sentiment_very_satisfied;
    } else if (score >= 40) {
      scoreColor = AppColors.warning;
      scoreLabel = 'Cần chú ý';
      scoreIcon = Icons.sentiment_neutral;
    } else {
      scoreColor = AppColors.expense;
      scoreLabel = 'Cần cải thiện';
      scoreIcon = Icons.sentiment_very_dissatisfied;
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scoreColor.withOpacity(0.12), scoreColor.withOpacity(0.04)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scoreColor.withOpacity(0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: scoreColor.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: scoreColor, width: 3),
              ),
              child: Center(
                child: Text(
                  '$score',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: scoreColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Điểm sức khỏe tài chính',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(scoreIcon, size: 18, color: scoreColor),
                      const SizedBox(width: 4),
                      Text(
                        scoreLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: scoreColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: score / 100,
                      minHeight: 6,
                      backgroundColor: scoreColor.withOpacity(0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(scoreColor),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 2. VẤN ĐỀ & CƠ HỘI SECTION
  // ============================================================
  Widget _buildIssuesAndOpportunitiesSection(
      List<FinancialIssue> issues, List<_CategoryCut> cuts) {
    final totalItems = issues.length + cuts.length;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.bolt_rounded,
                    color: AppColors.warning, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Vấn đề & Cơ hội',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
              if (totalItems > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$totalItems',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          if (totalItems == 0)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.income.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.income, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tình hình tài chính an toàn. Chưa phát hiện vấn đề đáng chú ý nào trong tháng này!',
                      style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            ...issues.map((issue) => _buildIssueCard(issue)),
            ...cuts.map((cut) => _buildCutOpportunityCard(cut)),
          ],
        ],
      ),
    );
  }

  Widget _buildIssueCard(FinancialIssue issue) {
    final key = issue.title;
    final isCritical = issue.severity == IssueSeverity.critical;
    final severityColor = isCritical ? AppColors.expense : AppColors.warning;

    IconData catIcon;
    switch (issue.category) {
      case IssueCategory.spike:
        catIcon = Icons.trending_up_rounded;
        break;
      case IssueCategory.budgetShare:
        catIcon = Icons.pie_chart_outline_rounded;
        break;
      case IssueCategory.lowSaving:
        catIcon = Icons.account_balance_wallet_outlined;
        break;
    }

    final isLoadingAi = _aiLoadingMap[key] ?? false;
    final explanation = _aiExplanations[key];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: severityColor.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: severityColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: severityColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(catIcon, size: 18, color: severityColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            issue.title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        // Badge Tin cậy (Dart tính)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: severityColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${issue.confidenceScore.round()}% Tin cậy',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: severityColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      issue.description,
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
          const SizedBox(height: 10),
          // Action Buttons: AI Explain & Dismiss
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: isLoadingAi ? null : () => _explainIssue(issue),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.aiAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isLoadingAi)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.aiAccent,
                          ),
                        )
                      else
                        const Icon(Icons.auto_awesome, size: 14, color: AppColors.aiAccent),
                      const SizedBox(width: 6),
                      Text(
                        explanation != null ? 'Cập nhật giải thích' : 'Xem giải thích từ AI',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.aiAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                tooltip: 'Bỏ qua',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
                onPressed: () {
                  setState(() => _dismissedKeys.add(key));
                },
              ),
            ],
          ),

          // Inline AI Explanation
          if (explanation != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.aiAccent.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.aiAccent.withOpacity(0.2)),
              ),
              child: Text(
                explanation,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCutOpportunityCard(_CategoryCut cut) {
    final key = 'cut_${cut.categoryName}';
    final monthSavings = (cut.currentDailyAvg - cut.targetDailyAvg) * 30;
    final isLoadingAi = _aiLoadingMap[key] ?? false;
    final explanation = _aiExplanations[key];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.income.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.income.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.income.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lightbulb_outline_rounded,
                    size: 18, color: AppColors.income),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Cơ hội tiết kiệm: ${cut.categoryName}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        // Badge Tin cậy cố định 85% cho cơ hội tiết kiệm
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.income.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '85% Tin cậy',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.income,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${AppFormatters.number(cut.currentDailyAvg.round().toDouble())}đ/ngày → '
                      '${AppFormatters.number(cut.targetDailyAvg.round().toDouble())}đ/ngày '
                      '(tiết kiệm ~${AppFormatters.number(monthSavings.round().toDouble())}đ/tháng)',
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
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: isLoadingAi ? null : () => _explainCut(cut),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.aiAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isLoadingAi)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.aiAccent,
                          ),
                        )
                      else
                        const Icon(Icons.auto_awesome, size: 14, color: AppColors.aiAccent),
                      const SizedBox(width: 6),
                      Text(
                        explanation != null ? 'Cập nhật gợi ý' : 'Xem gợi ý từ AI',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.aiAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                tooltip: 'Bỏ qua',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
                onPressed: () {
                  setState(() => _dismissedKeys.add(key));
                },
              ),
            ],
          ),
          if (explanation != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.aiAccent.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.aiAccent.withOpacity(0.2)),
              ),
              child: Text(
                explanation,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // 4. XU HƯỚNG CHI TIÊU 6 THÁNG (LAZY LOAD)
  // ============================================================
  Widget _buildTrendSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: const Row(
            children: [
              Icon(Icons.show_chart_rounded, color: AppColors.primary, size: 20),
              SizedBox(width: 10),
              Text(
                'Xu hướng chi tiêu 6 tháng',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          onExpansionChanged: (expanded) {
            if (expanded) {
              _loadTrendLazy();
            }
          },
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _isLoadingTrend
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      ),
                    )
                  : _trendResult != null
                      ? TrendChartCard(trendResult: _trendResult!)
                      : const Text('Không thể tải dữ liệu xu hướng 6 tháng.'),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // 5. NHẬN ĐỊNH TỔNG QUAN TỪ AI (LAZY LOAD)
  // ============================================================
  Widget _buildOverviewSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: const Row(
            children: [
              Icon(Icons.psychology_outlined, color: AppColors.aiAccent, size: 20),
              SizedBox(width: 10),
              Text(
                'Nhận định tổng quan từ AI',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          onExpansionChanged: (expanded) {
            if (expanded) {
              _loadOverviewLazy();
            }
          },
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _isLoadingOverview
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: CircularProgressIndicator(color: AppColors.aiAccent),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_spendingAnalysis != null) ...[
                          const Text(
                            'Thói quen chi tiêu',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _spendingAnalysis!,
                            style: TextStyle(
                                height: 1.5, color: AppColors.textPrimary),
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (_monthEndPrediction != null) ...[
                          const Text(
                            'Dự đoán cuối tháng',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppColors.warning,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _monthEndPrediction!,
                            style: TextStyle(
                                height: 1.5, color: AppColors.textPrimary),
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
