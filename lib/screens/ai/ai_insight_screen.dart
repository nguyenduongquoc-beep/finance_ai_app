import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/financial_issue.dart';
import '../../services/firestore_service.dart';
import '../../services/ai_service.dart';
import '../../services/financial_analytics_service.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../models/trend_result.dart';
import '../../widgets/trend_chart_card.dart';

/// 18. AI Insight - AI tự động phân tích, không cần người dùng hỏi
class AiInsightScreen extends StatefulWidget {
  const AiInsightScreen({super.key});

  @override
  State<AiInsightScreen> createState() => _AiInsightScreenState();
}

class _InsightData {
  final String spendingAnalysis;
  final String monthEndPrediction;
  final List<_CategoryCut> topCuts;
  final TrendResult? trendResult;
  // MỚI — Financial Analytics Layer
  final int healthScore;
  final List<FinancialIssue> issues;
  final String aiSuggestionForIssues;

  _InsightData({
    required this.spendingAnalysis,
    required this.monthEndPrediction,
    required this.topCuts,
    this.trendResult,
    required this.healthScore,
    required this.issues,
    required this.aiSuggestionForIssues,
  });
}

class _CategoryCut {
  final String categoryName;
  final double currentDailyAvg;
  final double targetDailyAvg;
  String? aiSuggestion;
  bool isLoading = false;

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

  _InsightData? _data;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  Future<void> _loadInsights() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final last30Days = now.subtract(const Duration(days: 30));
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;

    // Tính khoảng thời gian tháng trước để so sánh
    final lastMonthStart = DateTime(now.year, now.month - 1, 1);
    final lastMonthEnd = DateTime(now.year, now.month, 0, 23, 59, 59);

    try {
      final transactions =
          await _firestoreService.streamTransactions(uid, from: last30Days).first;
      final categories = await _firestoreService.streamCategories(uid).first;
      final monthTransactions =
          await _firestoreService.streamTransactions(uid, from: monthStart).first;

      // Fetch giao dịch tháng trước để so sánh (Financial Analytics Layer)
      final lastMonthTransactions = await _firestoreService
          .streamTransactions(uid, from: lastMonthStart, to: lastMonthEnd)
          .first;

      // Lấy thông tin user để có monthlyIncome
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

      final spentSoFar = monthTransactions
          .where((t) => t.type == 'expense')
          .fold<double>(0, (a, t) => a + t.amount);

      // Build top 3 categories for cut suggestions
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
          targetDailyAvg: dailyAvg * 0.75, // suggest 25% cut
        );
      }).toList();

      // Trend analysis data prep — cần fetch giao dịch 6 tháng, KHÔNG dùng biến transactions (chỉ 30 ngày)
      final sixMonthsAgo = DateTime(now.year, now.month - 5, 1);
      final trendTransactions =
          await _firestoreService.streamTransactions(uid, from: sixMonthsAgo).first;
      final List<double> monthlySpending = [];
      for (int i = 5; i >= 0; i--) {
        final month = DateTime(now.year, now.month - i, 1);
        final monthEnd = DateTime(month.year, month.month + 1, 0);
        final monthTotal = trendTransactions
            .where((t) => t.type == 'expense' && t.date.isAfter(month.subtract(const Duration(days: 1))) && t.date.isBefore(monthEnd.add(const Duration(days: 1))))
            .fold<double>(0, (a, t) => a + t.amount);
        monthlySpending.add(monthTotal);
      }

      // Run AI tasks in parallel (bao gồm cả AI giải thích vấn đề mới)
      String analysis = 'Không thể tải phân tích chi tiêu lúc này.';
      String prediction = 'Không thể tải dự đoán chi tiêu lúc này.';
      String aiSuggestionForIssues = '';
      TrendResult? trendResult;

      await Future.wait<dynamic>([
        _aiService.analyzeSpendingHabits(
          transactions: transactions,
          categories: categories,
        ).timeout(const Duration(seconds: 30)).then((res) {
          analysis = res;
        }).catchError((e, stackTrace) {
          debugPrint('AI Insight (Spending Habits) error: $e');
          debugPrintStack(stackTrace: stackTrace);
        }),
        _aiService.predictMonthEnd(
          spentSoFar: spentSoFar,
          dayOfMonth: now.day,
          totalDaysInMonth: daysInMonth,
        ).timeout(const Duration(seconds: 30)).then((res) {
          prediction = res;
        }).catchError((e, stackTrace) {
          debugPrint('AI Insight (Month End) error: $e');
          debugPrintStack(stackTrace: stackTrace);
        }),
        _aiService.analyzeTrend(
          monthlySpending: monthlySpending,
        ).timeout(const Duration(seconds: 30)).then((res) {
          trendResult = res;
        }).catchError((e, stackTrace) {
          debugPrint('AI Insight (Trend) error: $e');
          debugPrintStack(stackTrace: stackTrace);
        }),
        // MỚI: Gọi AI giải thích + đề xuất cho các vấn đề đã phát hiện
        _aiService.explainAndSuggestForIssues(issues)
            .timeout(const Duration(seconds: 30)).then((res) {
          aiSuggestionForIssues = res;
        }).catchError((e, stackTrace) {
          debugPrint('AI Insight (Issue Suggestions) error: $e');
          debugPrintStack(stackTrace: stackTrace);
          aiSuggestionForIssues = issues.isEmpty
              ? 'Chúc mừng bạn! Chưa phát hiện vấn đề tài chính đáng chú ý nào trong tháng này.'
              : 'Không thể tải đề xuất AI lúc này.';
        }),
      ]);

      if (!mounted) return;
      setState(() {
        _data = _InsightData(
          spendingAnalysis: analysis,
          monthEndPrediction: prediction,
          topCuts: topCuts,
          trendResult: trendResult,
          healthScore: healthScore,
          issues: issues,
          aiSuggestionForIssues: aiSuggestionForIssues,
        );
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('AI Insight Data Load error: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Không thể tải phân tích AI lúc này. Vui lòng kiểm tra kết nối và API key.';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadCutSuggestion(_CategoryCut cut) async {
    setState(() => cut.isLoading = true);
    try {
      final suggestion = await _aiService.suggestSpendingCuts(
        categoryName: cut.categoryName,
        currentDailyAvg: cut.currentDailyAvg,
        targetDailyAvg: cut.targetDailyAvg,
      );
      if (!mounted) return;
      setState(() {
        cut.aiSuggestion = suggestion;
        cut.isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => cut.isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.aiAccent),
            SizedBox(height: 16),
            Text('AI đang phân tích dữ liệu của bạn...',
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
                  style: const TextStyle(color: AppColors.textSecondary)),
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

    final data = _data!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // === MỚI: Điểm sức khỏe tài chính ===
        _buildHealthScoreCard(data.healthScore),
        const SizedBox(height: 16),
        // === MỚI: Danh sách vấn đề phát hiện ===
        if (data.issues.isNotEmpty) ...[
          _buildIssuesList(data.issues),
          const SizedBox(height: 16),
        ],
        // === MỚI: Đề xuất từ AI cho các vấn đề ===
        _buildAiSuggestionCard(data.aiSuggestionForIssues, data.issues.isEmpty),
        const SizedBox(height: 16),
        // === GIỮ NGUYÊN: Các tính năng cũ ===
        if (data.trendResult != null) ...[
          TrendChartCard(trendResult: data.trendResult!),
          const SizedBox(height: 16),
        ],
        _insightCard(
          icon: Icons.pie_chart_outline,
          title: 'Phân tích thói quen chi tiêu',
          content: data.spendingAnalysis,
          color: AppColors.primary,
        ),
        const SizedBox(height: 16),
        _insightCard(
          icon: Icons.trending_up,
          title: 'Dự đoán chi tiêu cuối tháng',
          content: data.monthEndPrediction,
          color: AppColors.warning,
        ),
        if (data.topCuts.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildCutSuggestionsSection(data.topCuts),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  // ============================================================
  // MỚI — HEALTH SCORE CARD
  // ============================================================
  Widget _buildHealthScoreCard(int score) {
    // Màu theo mức: xanh ≥70, vàng 40-69, đỏ <40
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
            // Số điểm lớn
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
                  const Text(
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
                  // Thanh tiến trình
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
  // MỚI — DANH SÁCH VẤN ĐỀ PHÁT HIỆN
  // ============================================================
  Widget _buildIssuesList(List<FinancialIssue> issues) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Padding(
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
                  child: const Icon(Icons.warning_amber_rounded,
                      color: AppColors.warning, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Vấn đề phát hiện',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.expense.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${issues.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.expense,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...issues.map((issue) => _buildIssueItem(issue)),
          ],
        ),
      ),
    );
  }

  Widget _buildIssueItem(FinancialIssue issue) {
    final isCritical = issue.severity == IssueSeverity.critical;
    final severityColor = isCritical ? AppColors.expense : AppColors.warning;
    final severityLabel = isCritical ? 'Nghiêm trọng' : 'Cảnh báo';
    final severityIcon = isCritical ? Icons.error : Icons.warning_amber_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: severityColor.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: severityColor.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(severityIcon, size: 20, color: severityColor),
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: severityColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        severityLabel,
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
                  style: const TextStyle(
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
  }

  // ============================================================
  // MỚI — ĐỀ XUẤT TỪ AI
  // ============================================================
  Widget _buildAiSuggestionCard(String suggestion, bool noIssues) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (noIssues ? AppColors.income : AppColors.aiAccent)
                        .withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    noIssues ? Icons.check_circle_outline : Icons.auto_awesome,
                    color: noIssues ? AppColors.income : AppColors.aiAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    noIssues ? 'Tình hình tài chính' : 'Đề xuất từ AI',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text(suggestion,
                style: const TextStyle(
                    height: 1.6, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // GIỮ NGUYÊN — Các widget cũ
  // ============================================================
  Widget _insightCard({
    required IconData icon,
    required String title,
    required String content,
    Color color = AppColors.aiAccent,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text(content,
                style: const TextStyle(height: 1.6, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _buildCutSuggestionsSection(List<_CategoryCut> cuts) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.expense.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.content_cut, color: AppColors.expense, size: 20),
                ),
                const SizedBox(width: 10),
                const Text('Gợi ý cắt giảm chi tiêu',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            ...cuts.map((cut) => _buildCutCard(cut)),
          ],
        ),
      ),
    );
  }

  Widget _buildCutCard(_CategoryCut cut) {
    final monthSavings = (cut.currentDailyAvg - cut.targetDailyAvg) * 30;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
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
                    Text(cut.categoryName,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      '${AppFormatters.number(cut.currentDailyAvg.round().toDouble())} đ/ngày → '
                      '${AppFormatters.number(cut.targetDailyAvg.round().toDouble())} đ/ngày',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.income.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'tiết kiệm ${AppFormatters.number(monthSavings.round().toDouble())}đ/tháng',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.income,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (cut.aiSuggestion != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.aiAccent.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_awesome, size: 14, color: AppColors.aiAccent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(cut.aiSuggestion!,
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textPrimary,
                            height: 1.45)),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: cut.isLoading ? null : () => _loadCutSuggestion(cut),
                icon: cut.isLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.aiAccent))
                    : const Icon(Icons.auto_awesome, size: 14, color: AppColors.aiAccent),
                label: Text(
                    cut.isLoading ? 'Đang phân tích...' : 'Xem gợi ý AI',
                    style: const TextStyle(fontSize: 12, color: AppColors.aiAccent)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.aiAccent),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
