import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../models/financial_forecast_result.dart';
import '../../models/financial_issue.dart';
import '../../models/transaction_model.dart';
import '../../models/category_model.dart';
import '../../models/budget_model.dart';
import '../../models/wallet_model.dart';
import '../../models/user_model.dart';
import '../../models/recurring_transaction_model.dart';
import '../../services/firestore_service.dart';
import '../../services/ai_service.dart';
import '../../services/financial_analytics_service.dart';
import '../../services/financial_forecast_service.dart';
import '../../services/theme_controller.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/weekly_heatmap_card.dart';

/// ============================================================
/// AI FINANCIAL INSIGHTS SCREEN
/// 1. Điểm sức khỏe tài chính
/// 2. Dự báo số dư cuối tháng
/// 3. Cảnh báo ngân sách
/// 4. Chi tiêu bất thường
/// 5. Đề xuất AI từ Gemini (gated)
/// ============================================================
class AiInsightScreen extends StatefulWidget {
  const AiInsightScreen({super.key});

  @override
  State<AiInsightScreen> createState() => _AiInsightScreenState();
}

class _AiInsightScreenState extends State<AiInsightScreen> {
  final _aiService = AiService();
  final _firestoreService = FirestoreService();
  final _analyticsService = FinancialAnalyticsService();
  final _forecastService = FinancialForecastService();

  bool _isLoading = true;
  String? _errorMessage;

  FinancialInsightSummary? _forecastSummary;
  Map<String, List<int>> _weeklyHeatmap = {};

  // Gemini AI state
  bool _isLoadingAiExplanation = false;
  String? _aiExplanation;
  String? _aiErrorMessage;

  @override
  void initState() {
    super.initState();
    _loadInsights();
  }

  /// Tải dữ liệu 4 tháng qua Future.wait và tính toán Dart thuần
  Future<void> _loadInsights() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final now = DateTime.now();
    final monthStr = DateFormat('MM/yyyy').format(now);

    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    final m1Start = DateTime(now.year, now.month - 1, 1);
    final m1End = DateTime(now.year, now.month, 0, 23, 59, 59);

    final m2Start = DateTime(now.year, now.month - 2, 1);
    final m2End = DateTime(now.year, now.month - 1, 0, 23, 59, 59);

    final m3Start = DateTime(now.year, now.month - 3, 1);
    final m3End = DateTime(now.year, now.month - 2, 0, 23, 59, 59);

    final last30Days = now.subtract(const Duration(days: 30));

    try {
      final results = await Future.wait<dynamic>([
        _firestoreService.streamWallets(uid).first, // 0: List<Wallet>
        _firestoreService.streamCategories(uid).first, // 1: List<Category>
        _firestoreService
            .streamBudgets(uid, month: monthStr)
            .first, // 2: List<Budget>
        _firestoreService
            .streamTransactions(uid, from: monthStart, to: monthEnd)
            .first, // 3: Current month Tx
        _firestoreService
            .streamTransactions(uid, from: m1Start, to: m1End)
            .first, // 4: Month -1 Tx
        _firestoreService
            .streamTransactions(uid, from: m2Start, to: m2End)
            .first, // 5: Month -2 Tx
        _firestoreService
            .streamTransactions(uid, from: m3Start, to: m3End)
            .first, // 6: Month -3 Tx
        _firestoreService.getUserProfile(uid), // 7: AppUser?
        _firestoreService
            .streamTransactions(uid, from: last30Days)
            .first, // 8: Last 30 days Tx for heatmap
        _firestoreService
            .streamRecurringTransactions(uid)
            .first, // 9: Recurring schedules
      ]);

      final wallets = results[0] as List<Wallet>;
      final categories = results[1] as List<Category>;
      final currentBudgets = results[2] as List<Budget>;
      final currentMonthTx = results[3] as List<AppTransaction>;
      final m1Tx = results[4] as List<AppTransaction>;
      final m2Tx = results[5] as List<AppTransaction>;
      final m3Tx = results[6] as List<AppTransaction>;
      final userProfile = results[7] as AppUser?;
      final last30DaysTx = results[8] as List<AppTransaction>;
      final recurringSchedules =
          results[9] as List<RecurringTransactionSchedule>;

      final monthlyIncome = userProfile?.monthlyIncome ?? 0;

      // 1. Phân tích vấn đề bằng Dart thuần
      final issues = _analyticsService.detectIssues(
        currentMonthTx: currentMonthTx,
        lastMonthTx: m1Tx,
        categories: categories,
        monthlyIncome: monthlyIncome,
      );

      // 2. Dự báo dòng tiền, ngân sách & anomaly bằng Dart thuần
      final summary = _forecastService.generateSummary(
        activeWallets: wallets,
        currentMonthBudgets: currentBudgets,
        categories: categories,
        currentMonthTx: currentMonthTx,
        preceding3MonthsTx: [m3Tx, m2Tx, m1Tx],
        monthlyIncome: monthlyIncome,
        issues: issues,
        recurringSchedules: recurringSchedules,
        refDate: now,
      );

      final heatmap =
          _analyticsService.computeWeeklyHeatmap(last30DaysTx, categories);

      if (!mounted) return;
      setState(() {
        _forecastSummary = summary;
        _weeklyHeatmap = heatmap;
        _isLoading = false;
      });

      // Lần đầu tải dữ liệu thành công -> Gọi Gemini diễn giải AI
      _fetchAiExplanation(summary);
    } catch (e, stackTrace) {
      debugPrint('AI Financial Insights Data Load error: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Không thể tải phân tích tài chính lúc này. Vui lòng kiểm tra kết nối.';
        _isLoading = false;
      });
    }
  }

  /// Gọi Gemini diễn giải số liệu (gated: chỉ gọi khi được trigger)
  Future<void> _fetchAiExplanation(FinancialInsightSummary summary) async {
    if (!mounted) return;
    setState(() {
      _isLoadingAiExplanation = true;
      _aiErrorMessage = null;
    });

    try {
      final explanation = await _aiService.explainFinancialInsights(summary);
      if (!mounted) return;
      setState(() {
        _aiExplanation = explanation;
        _isLoadingAiExplanation = false;
      });
    } catch (e) {
      debugPrint('Gemini explanation error: $e');
      if (!mounted) return;
      final msg = AiService.isNoNetworkException(e)
          ? 'Không có kết nối mạng.'
          : 'Chưa thể tải phần giải thích AI. Các chỉ số tài chính bên trên vẫn được tính từ dữ liệu của bạn.';
      setState(() {
        _aiErrorMessage = msg;
        _isLoadingAiExplanation = false;
      });
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
                  child: const Icon(Icons.auto_awesome,
                      color: AppColors.aiAccent, size: 18),
                ),
                const SizedBox(width: 8),
                const Text('AI Financial Insights'),
              ],
            ),
            actions: [
              if (!_isLoading)
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Làm mới phân tích',
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
            Text(
              'Đang tính toán dự báo & phân tích tài chính...',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null || _forecastSummary == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: AppColors.expense, size: 48),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? 'Không có dữ liệu phân tích.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loadInsights,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.aiAccent),
              ),
            ],
          ),
        ),
      );
    }

    final summary = _forecastSummary!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. Điểm sức khỏe tài chính
        _buildHealthScoreSection(summary),
        const SizedBox(height: 16),

        // 2. Dự báo số dư cuối tháng
        _buildMonthEndForecastSection(summary.monthEndForecast),
        const SizedBox(height: 16),

        // 3. Cảnh báo vượt ngân sách
        _buildBudgetForecastSection(summary.budgetForecasts),
        const SizedBox(height: 16),

        // 4. Chi tiêu bất thường
        _buildSpendingAnomalySection(summary.anomalies),
        const SizedBox(height: 16),

        // 5. Đề xuất AI từ Gemini
        _buildAiExplanationSection(summary),
        const SizedBox(height: 16),

        // 6. Heatmap tần suất chi tiêu theo tuần
        WeeklyHeatmapCard(heatmapData: _weeklyHeatmap),
        const SizedBox(height: 24),
      ],
    );
  }

  // ============================================================
  // 1. ĐIỂM SỨC KHỎE TÀI CHÍNH CARD
  // ============================================================
  Widget _buildHealthScoreSection(FinancialInsightSummary summary) {
    final score = summary.healthScore;
    final Color scoreColor;
    final IconData scoreIcon;

    if (score >= 80) {
      scoreColor = AppColors.income;
      scoreIcon = Icons.sentiment_very_satisfied;
    } else if (score >= 60) {
      scoreColor = AppColors.primary;
      scoreIcon = Icons.sentiment_satisfied;
    } else if (score >= 40) {
      scoreColor = AppColors.warning;
      scoreIcon = Icons.sentiment_neutral;
    } else {
      scoreColor = AppColors.expense;
      scoreIcon = Icons.sentiment_very_dissatisfied;
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: scoreColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: scoreColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: scoreColor, width: 3),
                  ),
                  child: Center(
                    child: Text(
                      '$score',
                      style: TextStyle(
                        fontSize: 26,
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
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: scoreColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              summary.healthRating,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: scoreColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
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
          if (summary.deductions.isNotEmpty) ...[
            const Divider(height: 1),
            Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                dense: true,
                title: Text(
                  'Chi tiết lý do chấm điểm (${summary.deductions.length} khoản trừ)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                children: summary.deductions.map((d) {
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.remove_circle_outline,
                            size: 14, color: AppColors.expense),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            d.reason,
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textPrimary),
                          ),
                        ),
                        Text(
                          '-${d.points}đ',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.expense,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // 2. DỰ BÁO SỐ DƯ CUỐI THÁNG CARD
  // ============================================================
  Widget _buildMonthEndForecastSection(MonthEndForecast forecast) {
    final isNegative = forecast.projectedEndBalance < 0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
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
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.account_balance_wallet_outlined,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Dự báo số dư cuối tháng',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          if (!forecast.hasEnoughData)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Chưa đủ dữ liệu chi tiêu tháng này để dự báo.',
                      style:
                          TextStyle(fontSize: 13, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            // Projected Balance Summary Highlight
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (isNegative ? AppColors.expense : AppColors.income)
                    .withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: (isNegative ? AppColors.expense : AppColors.income)
                      .withOpacity(0.25),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Số dư dự kiến cuối tháng',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${AppFormatters.number(forecast.projectedEndBalance)}đ',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color:
                              isNegative ? AppColors.expense : AppColors.income,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isNegative ? AppColors.expense : AppColors.income)
                          .withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isNegative
                              ? Icons.warning_amber_rounded
                              : Icons.trending_flat,
                          size: 16,
                          color:
                              isNegative ? AppColors.expense : AppColors.income,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isNegative ? 'Nguy cơ âm ví' : 'Ổn định',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isNegative
                                ? AppColors.expense
                                : AppColors.income,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Key Metrics Table
            _buildMetricRow('Tổng số dư hiện tại',
                AppFormatters.number(forecast.currentTotalBalance)),
            _buildMetricRow('Chi tiêu từ đầu tháng',
                AppFormatters.number(forecast.monthToDateExpense)),
            _buildMetricRow(
                'Trung bình chi linh hoạt/ngày',
                AppFormatters.number(
                    forecast.averageDailyDiscretionaryExpense)),
            if (forecast.plannedRemainingIncome > 0)
              _buildMetricRow('Thu nhập định kỳ sắp tới',
                  '+${AppFormatters.number(forecast.plannedRemainingIncome)}'),
            if (forecast.plannedRemainingExpense > 0)
              _buildMetricRow('Chi định kỳ/Hóa đơn sắp tới',
                  '-${AppFormatters.number(forecast.plannedRemainingExpense)}'),
            _buildMetricRow(
                'Số ngày còn lại', '${forecast.remainingDays} ngày'),
            _buildMetricRow('Chi phí dự kiến còn lại',
                AppFormatters.number(forecast.projectedRemainingExpense)),

            const SizedBox(height: 8),

            // Assumptions & Data Section
            Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                dense: true,
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Dữ liệu & Giả định',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '• Số ngày đã qua: ${forecast.elapsedDays}/${forecast.totalDaysInMonth} ngày',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '• Giả định: Dự báo này giả định không có khoản thu mới và mức chi tiêu giữ nguyên như từ đầu tháng.',
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          Text('$valueđ',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  // ============================================================
  // 3. CẢNH BÁO VƯỢT NGÂN SÁCH SECTION
  // ============================================================
  Widget _buildBudgetForecastSection(List<BudgetForecast> forecasts) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
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
                  color: AppColors.warning.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.pie_chart_outline_rounded,
                    color: AppColors.warning, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Cảnh báo vượt ngân sách',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              if (forecasts.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${forecasts.where((f) => f.status != BudgetForecastStatus.safe).length}/${forecasts.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.warning,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          if (forecasts.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.income.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: AppColors.income, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Chưa thiết lập ngân sách nào cho tháng này.',
                      style:
                          TextStyle(fontSize: 13, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            )
          else
            ...forecasts.map((b) => _buildBudgetForecastCard(b)),
        ],
      ),
    );
  }

  Widget _buildBudgetForecastCard(BudgetForecast budget) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    switch (budget.status) {
      case BudgetForecastStatus.exceeded:
        statusColor = AppColors.expense;
        statusLabel = 'Đã vượt';
        statusIcon = Icons.cancel_outlined;
        break;
      case BudgetForecastStatus.atRisk:
        statusColor = Colors.deepOrange;
        statusLabel = 'Có nguy cơ';
        statusIcon = Icons.warning_amber_rounded;
        break;
      case BudgetForecastStatus.warning:
        statusColor = AppColors.warning;
        statusLabel = 'Cảnh báo';
        statusIcon = Icons.error_outline;
        break;
      case BudgetForecastStatus.safe:
        statusColor = AppColors.income;
        statusLabel = 'An toàn';
        statusIcon = Icons.check_circle_outline;
        break;
    }

    final percentDisplay = (budget.percentUsed * 100).round();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                budget.categoryName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 13, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Đã chi: ${AppFormatters.number(budget.spent)}đ / ${AppFormatters.number(budget.limit)}đ ($percentDisplay%)',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (budget.percentUsed).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: statusColor.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Tốc độ chi: ${AppFormatters.number(budget.dailyPace)}đ/ngày',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              if (budget.estimatedExceededDate != null &&
                  budget.status == BudgetForecastStatus.atRisk)
                Text(
                  'Dự kiến vượt ngày ${DateFormat('dd/MM').format(budget.estimatedExceededDate!)}',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepOrange),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 4. CHI TIÊU BẤT THƯỜNG SECTION
  // ============================================================
  Widget _buildSpendingAnomalySection(List<SpendingAnomaly> anomalies) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
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
                  color: AppColors.expense.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.bolt_rounded,
                    color: AppColors.expense, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Chi tiêu bất thường',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              if (anomalies.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.expense.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${anomalies.length}',
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
          const SizedBox(height: 12),
          if (anomalies.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.income.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: AppColors.income, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Không phát hiện danh mục nào chi tiêu bất thường so với 3 tháng trước.',
                      style:
                          TextStyle(fontSize: 13, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            )
          else
            ...anomalies.map((a) => _buildAnomalyCard(a)),
        ],
      ),
    );
  }

  Widget _buildAnomalyCard(SpendingAnomaly anomaly) {
    final isCritical = anomaly.severity == IssueSeverity.critical;
    final color = isCritical ? AppColors.expense : AppColors.warning;
    final percentOver = ((anomaly.excessRatio * 100) - 100).round();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                anomaly.categoryName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Vượt +$percentOver%',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Chi hiện tại: ${AppFormatters.number(anomaly.currentSpend)}đ (Mức kỳ vọng: ${AppFormatters.number(anomaly.expectedSpendToDate)}đ)',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Chênh lệch: +${AppFormatters.number(anomaly.excessAmount)}đ',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: color),
              ),
              Text(
                'Dữ liệu từ ${anomaly.monthsOfHistory} tháng trước',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 5. ĐỀ XUẤT AI TỪ GEMINI SECTION (Gated)
  // ============================================================
  Widget _buildAiExplanationSection(FinancialInsightSummary summary) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
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
                  color: AppColors.aiAccent.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome,
                    color: AppColors.aiAccent, size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Phân tích & Đề xuất AI',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              IconButton(
                icon: _isLoadingAiExplanation
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.aiAccent),
                      )
                    : const Icon(Icons.refresh_rounded,
                        color: AppColors.aiAccent, size: 20),
                tooltip: 'Làm mới đề xuất AI',
                onPressed: _isLoadingAiExplanation
                    ? null
                    : () => _fetchAiExplanation(summary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          if (_isLoadingAiExplanation)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(color: AppColors.aiAccent),
                    const SizedBox(height: 12),
                    Text(
                      'Gemini đang phân tích chỉ số tài chính...',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            )
          else if (_aiErrorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning.withOpacity(0.2)),
              ),
              child: Text(
                _aiErrorMessage!,
                style: TextStyle(
                    fontSize: 13, height: 1.5, color: AppColors.textPrimary),
              ),
            )
          else if (_aiExplanation != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.aiAccent.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.aiAccent.withOpacity(0.2)),
              ),
              child: Text(
                _aiExplanation!,
                style: TextStyle(
                    fontSize: 13, height: 1.5, color: AppColors.textPrimary),
              ),
            )
          else
            Text(
              'Bấm "Làm mới đề xuất AI" để xem phần giải thích từ Gemini.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
        ],
      ),
    );
  }
}
