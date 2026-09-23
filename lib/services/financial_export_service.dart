import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/budget_model.dart';
import '../models/category_model.dart';
import '../models/financial_issue.dart';
import '../models/financial_report_data.dart';
import '../models/saving_goal_model.dart';
import '../models/transaction_model.dart';
import '../models/wallet_model.dart';
import 'financial_analytics_service.dart';
import 'financial_forecast_service.dart';

/// Exception được throw khi xuất dữ liệu gặp lỗi hợp lệ (ví dụ danh sách rỗng)
class ExportException implements Exception {
  final String message;
  ExportException(this.message);

  @override
  String toString() => message;
}

/// Service chịu trách nhiệm xử lý xuất file CSV và PDF tài chính cục bộ.
/// Toàn bộ logic tính toán được tách biệt khỏi UI.
class FinancialExportService {
  final FinancialAnalyticsService _analyticsService;
  final FinancialForecastService _forecastService;

  FinancialExportService({
    FinancialAnalyticsService? analyticsService,
    FinancialForecastService? forecastService,
  })  : _analyticsService = analyticsService ?? FinancialAnalyticsService(),
        _forecastService = forecastService ?? FinancialForecastService();

  // ============================================================
  // 1. PURE-DART REPORT BUILDER
  // ============================================================

  /// Tổng hợp toàn bộ dữ liệu báo cáo tài chính thành model `FinancialReportData`.
  /// Hàm này hoàn toàn là Dart thuần — UI gọi hàm này rồi truyền data vào PDF renderer.
  FinancialReportData buildReportData({
    required List<AppTransaction> currentPeriodTx,
    required List<Wallet> wallets,
    required List<Category> categories,
    required List<Budget> budgets,
    required List<SavingGoal> savingGoals,
    required String periodLabel,
    required bool isCurrentMonth,
    List<AppTransaction>? lastMonthTx,
    List<List<AppTransaction>>? preceding3MonthsTx,
    DateTime? refDate,
  }) {
    final now = refDate ?? DateTime.now();

    // 1. Tính tổng Thu - Chi thực tế (CHỈ tính type 'income' và 'expense')
    double totalInc = 0;
    double totalExp = 0;
    for (final tx in currentPeriodTx) {
      if (tx.type == 'income') {
        totalInc += tx.amount;
      } else if (tx.type == 'expense') {
        totalExp += tx.amount;
      }
    }
    final netDiff = totalInc - totalExp;

    // Tổng số dư ví hiện tại (chỉ hiển thị nếu là tháng hiện tại)
    final double? walletBal = isCurrentMonth
        ? wallets
            .where((w) => w.isActive)
            .fold<double>(0, (sum, w) => sum + w.balance)
        : null;

    // 2. Cơ cấu chi tiêu theo danh mục
    final Map<String, double> catAmounts = {};
    for (final tx in currentPeriodTx.where((t) => t.type == 'expense')) {
      catAmounts[tx.categoryId] = (catAmounts[tx.categoryId] ?? 0) + tx.amount;
    }

    final List<CategoryExpenseItem> categoryBreakdown = [];
    final sortedCatEntries = catAmounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (final entry in sortedCatEntries) {
      final cat = categories.cast<Category?>().firstWhere(
            (c) => c?.categoryId == entry.key,
            orElse: () => null,
          );
      final catName = cat?.name ?? 'Đã xóa';
      final pct = totalExp > 0 ? (entry.value / totalExp) * 100 : 0.0;

      categoryBreakdown.add(CategoryExpenseItem(
        categoryName: catName,
        amount: entry.value,
        percentage: pct,
      ));
    }

    // 3. Ngân sách
    final List<BudgetReportItem> budgetItems = [];
    for (final b in budgets) {
      final cat = categories.cast<Category?>().firstWhere(
            (c) => c?.categoryId == b.categoryId,
            orElse: () => null,
          );
      final catName = cat?.name ?? 'Đã xóa';
      final spent = catAmounts[b.categoryId] ?? 0;
      final pct = b.limit <= 0 ? 0.0 : (spent / b.limit) * 100;

      String statusStr;
      if (spent >= b.limit) {
        statusStr = 'Đã vượt';
      } else if (pct >= 80) {
        statusStr = 'Có nguy cơ';
      } else {
        statusStr = 'An toàn';
      }

      budgetItems.add(BudgetReportItem(
        categoryName: catName,
        spent: spent,
        limit: b.limit,
        percentage: pct,
        status: statusStr,
      ));
    }

    // 4. Mục tiêu tiết kiệm
    final List<SavingGoalReportItem> savingGoalItems = [];
    for (final g in savingGoals) {
      final nameStr = g.name.trim().isNotEmpty ? g.name : 'Đã xóa';
      final pct = g.targetAmount <= 0
          ? 0.0
          : (g.savedAmount / g.targetAmount * 100).clamp(0, 100).toDouble();

      savingGoalItems.add(SavingGoalReportItem(
        goalName: nameStr,
        savedAmount: g.savedAmount,
        targetAmount: g.targetAmount,
        percentage: pct,
      ));
    }

    // 5. Insights & Điểm sức khỏe tài chính từ Dart Services
    final issues = _analyticsService.detectIssues(
      currentMonthTx: currentPeriodTx,
      lastMonthTx: lastMonthTx ?? [],
      categories: categories,
      monthlyIncome: totalInc,
    );

    final healthScore = _analyticsService.calculateHealthScore(issues);
    final String healthRating;
    if (healthScore >= 80) {
      healthRating = 'Tốt';
    } else if (healthScore >= 60) {
      healthRating = 'Cần theo dõi';
    } else if (healthScore >= 40) {
      healthRating = 'Có rủi ro';
    } else {
      healthRating = 'Cần hành động ngay';
    }

    final List<ReportInsightItem> insightItems = [];
    for (final issue in issues.take(4)) {
      insightItems.add(ReportInsightItem(
        title: issue.title,
        description: issue.description,
        type: issue.severity == IssueSeverity.critical ? 'warning' : 'positive',
      ));
    }
    if (insightItems.isEmpty) {
      insightItems.add(ReportInsightItem(
        title: 'Quản lý tài chính ổn định',
        description: 'Các chỉ số thu chi đang trong mức kiểm soát an toàn.',
        type: 'success',
      ));
    }

    // 6. Forecast (chỉ tính khi là tháng hiện tại)
    final monthEndForecast = isCurrentMonth
        ? _forecastService.calculateMonthEndForecast(
            activeWallets: wallets,
            currentMonthTx: currentPeriodTx,
            refDate: now,
          )
        : null;

    return FinancialReportData(
      reportTitle: 'BÁO CÁO TÀI CHÍNH CÁ NHÂN',
      periodLabel: periodLabel,
      exportDate: now,
      isCurrentMonth: isCurrentMonth,
      totalIncome: totalInc,
      totalExpense: totalExp,
      netDifference: netDiff,
      currentWalletBalance: walletBal,
      categoryBreakdown: categoryBreakdown,
      budgets: budgetItems,
      savingGoals: savingGoalItems,
      insights: insightItems,
      healthScore: healthScore,
      healthRating: healthRating,
      monthEndForecast: monthEndForecast,
    );
  }

  // ============================================================
  // 2. XUẤT CSV
  // ============================================================

  /// Escape một trường trong CSV theo chuẩn RFC 4180
  String _escapeCsvField(String field) {
    if (field.contains(',') ||
        field.contains('"') ||
        field.contains('\n') ||
        field.contains('\r')) {
      final escaped = field.replaceAll('"', '""');
      return '"$escaped"';
    }
    return field;
  }

  /// Xuất giao dịch ra file CSV cục bộ với UTF-8 BOM để Excel hiển thị đúng tiếng Việt.
  /// Thăng hoa các entity bị xóa thành "Đã xóa", KHÔNG xuất path/URL ảnh hóa đơn (`tx.image`).
  Future<File> exportTransactionsCsv({
    required List<AppTransaction> transactions,
    required List<Category> categories,
    required List<Wallet> wallets,
    required List<SavingGoal> savingGoals,
    required String filenamePrefix,
    Directory? outputDir,
  }) async {
    if (transactions.isEmpty) {
      throw ExportException('Không có giao dịch nào trong khoảng thời gian được chọn.');
    }

    // Sắp xếp giao dịch mới nhất trước
    final sortedTx = List<AppTransaction>.from(transactions)
      ..sort((a, b) => b.date.compareTo(a.date));

    // Map tra cứu nhanh
    final categoryMap = {for (var c in categories) c.categoryId: c};
    final walletMap = {for (var w in wallets) w.walletId: w};
    final goalMap = {for (var g in savingGoals) g.goalId: g};

    final StringBuffer csvBuffer = StringBuffer();

    // 1. Cột bắt buộc
    final headers = [
      'Mã giao dịch',
      'Ngày',
      'Loại giao dịch',
      'Số tiền (VNĐ)',
      'Ví nguồn',
      'Ví đích',
      'Danh mục',
      'Ghi chú',
      'Địa điểm',
      'Nguồn giao dịch',
      'Lịch định kỳ liên quan',
    ];
    csvBuffer.writeln(headers.map(_escapeCsvField).join(','));

    // 2. Các hàng dữ liệu
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    for (final tx in sortedTx) {
      // Nhãn tiếng Việt loại giao dịch
      String typeLabel;
      switch (tx.type) {
        case 'income':
          typeLabel = 'Thu nhập';
          break;
        case 'expense':
          typeLabel = 'Chi tiêu';
          break;
        case 'transfer':
          typeLabel = 'Chuyển tiền';
          break;
        case 'goal_deposit':
          typeLabel = 'Nạp mục tiêu';
          break;
        case 'goal_withdraw':
          typeLabel = 'Rút mục tiêu';
          break;
        default:
          typeLabel = tx.type;
      }

      // Ví nguồn
      final sourceWallet = walletMap[tx.walletId];
      final sourceWalletName = sourceWallet?.walletName ?? 'Đã xóa';

      // Ví đích (dành cho transfer)
      String targetWalletName = '';
      if (tx.type == 'transfer') {
        if (tx.toWalletId != null) {
          final targetWallet = walletMap[tx.toWalletId];
          targetWalletName = targetWallet?.walletName ?? 'Đã xóa';
        } else {
          targetWalletName = 'Đã xóa';
        }
      }

      // Danh mục / Mục tiêu
      String categoryOrGoalName = '';
      if (tx.type == 'goal_deposit' || tx.type == 'goal_withdraw') {
        if (tx.goalId != null) {
          final goal = goalMap[tx.goalId];
          categoryOrGoalName = goal?.name ?? 'Đã xóa';
        } else {
          categoryOrGoalName = 'Đã xóa';
        }
      } else {
        if (tx.categoryId.isNotEmpty) {
          final cat = categoryMap[tx.categoryId];
          categoryOrGoalName = cat?.name ?? 'Đã xóa';
        }
      }

      // Nguồn giao dịch
      final isRecurring =
          tx.recurringScheduleId != null && tx.recurringScheduleId!.isNotEmpty;
      final sourceLabel = isRecurring ? 'Định kỳ' : 'Thủ công';

      final row = [
        tx.transactionId,
        dateFormat.format(tx.date),
        typeLabel,
        tx.amount.round().toString(),
        sourceWalletName,
        targetWalletName,
        categoryOrGoalName,
        tx.note ?? '',
        tx.location ?? '',
        sourceLabel,
        tx.recurringScheduleId ?? '',
      ];

      csvBuffer.writeln(row.map(_escapeCsvField).join(','));
    }

    // Ghi file với UTF-8 BOM
    final tempDir = outputDir ?? await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filenamePrefix.csv');

    final utf8Bytes = utf8.encode(csvBuffer.toString());
    final bomBytes = [0xEF, 0xBB, 0xBF]; // UTF-8 BOM
    final fullBytes = [...bomBytes, ...utf8Bytes];

    await file.writeAsBytes(fullBytes, flush: true);
    return file;
  }


  // ============================================================
  // 3. XUẤT PDF BÁO CÁO TÀI CHÍNH
  // ============================================================

  /// Tạo PDF bytes từ `FinancialReportData`. Hỗ trợ truyền TTF Unicode font tùy chọn.
  Future<Uint8List> generateFinancialReportPdf({
    required FinancialReportData data,
    pw.Font? ttfFont,
    pw.Font? ttfBoldFont,
  }) async {
    // Nạp font tiếng Việt nếu chưa truyền vào
    pw.Font mainFont;
    pw.Font boldFont;

    if (ttfFont != null && ttfBoldFont != null) {
      mainFont = ttfFont;
      boldFont = ttfBoldFont;
    } else {
      try {
        final regularData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
        final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
        mainFont = pw.Font.ttf(regularData);
        boldFont = pw.Font.ttf(boldData);
      } catch (_) {
        mainFont = pw.Font.helvetica();
        boldFont = pw.Font.helveticaBold();
      }
    }

    final pdf = pw.Document();

    final primaryColor = PdfColor.fromHex('#10B981');
    final darkNavy = PdfColor.fromHex('#16283A');
    final secondaryText = PdfColor.fromHex('#64748B');
    final lightBg = PdfColor.fromHex('#F8FAFC');

    final currencyFormat = NumberFormat('#,##0', 'vi_VN');
    String formatMoney(double amount) => '${currencyFormat.format(amount.round())} VNĐ';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(
          base: mainFont,
          bold: boldFont,
        ),
        header: (context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 12),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Finance AI App',
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: 14,
                    color: primaryColor,
                  ),
                ),
                pw.Text(
                  'Kỳ báo cáo: ${data.periodLabel}',
                  style: pw.TextStyle(fontSize: 10, color: secondaryText),
                ),
              ],
            ),
          );
        },
        footer: (context) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(top: 12),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Báo cáo tự động từ dữ liệu lưu trữ local - Không phải tư vấn tài chính chuyên nghiệp.',
                  style: pw.TextStyle(fontSize: 8, color: secondaryText),
                ),
                pw.Text(
                  'Trang ${context.pageNumber}/${context.pagesCount}',
                  style: pw.TextStyle(fontSize: 8, color: secondaryText),
                ),
              ],
            ),
          );
        },
        build: (context) {
          return [
            pw.SizedBox(height: 12),

            // Banner tiêu đề
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: darkNavy,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    data.reportTitle,
                    style: pw.TextStyle(
                      font: boldFont,
                      fontSize: 18,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'Kỳ: ${data.periodLabel}',
                        style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey300),
                      ),
                      pw.Text(
                        'Ngày xuất: ${DateFormat('dd/MM/yyyy HH:mm').format(data.exportDate)}',
                        style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey400),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 20),

            // 1. TỔNG QUAN THỰC TẾ
            pw.Text(
              '1. TỔNG QUAN THỰC TẾ',
              style: pw.TextStyle(font: boldFont, fontSize: 13, color: darkNavy),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: lightBg,
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
              ),
              child: pw.Column(
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Tổng thu nhập thực tế:'),
                      pw.Text(
                        formatMoney(data.totalIncome),
                        style: pw.TextStyle(font: boldFont, color: PdfColors.green700),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Tổng chi tiêu thực tế:'),
                      pw.Text(
                        formatMoney(data.totalExpense),
                        style: pw.TextStyle(font: boldFont, color: PdfColors.red700),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Divider(color: PdfColors.grey300, thickness: 0.5),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Chênh lệch thu - chi:'),
                      pw.Text(
                        formatMoney(data.netDifference),
                        style: pw.TextStyle(
                          font: boldFont,
                          color: data.netDifference >= 0 ? PdfColors.green700 : PdfColors.red700,
                        ),
                      ),
                    ],
                  ),
                  if (data.isCurrentMonth && data.currentWalletBalance != null) ...[
                    pw.SizedBox(height: 6),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Tổng số dư ví hiện tại:'),
                        pw.Text(
                          formatMoney(data.currentWalletBalance!),
                          style: pw.TextStyle(font: boldFont, color: darkNavy),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            pw.SizedBox(height: 20),

            // 2. CHI TIÊU THEO DANH MỤC
            pw.Text(
              '2. CHI TIÊU THEO DANH MỤC',
              style: pw.TextStyle(font: boldFont, fontSize: 13, color: darkNavy),
            ),
            pw.SizedBox(height: 8),
            if (data.categoryBreakdown.isEmpty)
              pw.Text('Chưa có chi tiêu trong kỳ báo cáo.',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600))
            else
              pw.TableHelper.fromTextArray(
                headers: ['Danh mục', 'Số tiền', 'Tỷ lệ'],
                data: data.categoryBreakdown.map((item) {
                  return [
                    item.categoryName,
                    formatMoney(item.amount),
                    '${item.percentage.toStringAsFixed(1)}%',
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(font: boldFont, color: PdfColors.white, fontSize: 10),
                headerDecoration: pw.BoxDecoration(color: darkNavy),
                cellStyle: const pw.TextStyle(fontSize: 10),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight,
                  2: pw.Alignment.centerRight,
                },
              ),

            pw.SizedBox(height: 20),

            // 3. NGÂN SÁCH
            pw.Text(
              '3. TÌNH HÌNH NGÂN SÁCH',
              style: pw.TextStyle(font: boldFont, fontSize: 13, color: darkNavy),
            ),
            pw.SizedBox(height: 8),
            if (data.budgets.isEmpty)
              pw.Text('Chưa thiết lập ngân sách cho kỳ báo cáo này.',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600))
            else
              pw.TableHelper.fromTextArray(
                headers: ['Danh mục', 'Đã chi', 'Hạn mức', 'Sử dụng', 'Trạng thái'],
                data: data.budgets.map((b) {
                  return [
                    b.categoryName,
                    formatMoney(b.spent),
                    formatMoney(b.limit),
                    '${b.percentage.toStringAsFixed(1)}%',
                    b.status,
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(font: boldFont, color: PdfColors.white, fontSize: 10),
                headerDecoration: pw.BoxDecoration(color: primaryColor),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.center,
                },
              ),

            pw.SizedBox(height: 20),

            // 4. MỤC TIÊU TIẾT KIỆM
            pw.Text(
              '4. MỤC TIÊU TIẾT KIỆM',
              style: pw.TextStyle(font: boldFont, fontSize: 13, color: darkNavy),
            ),
            pw.SizedBox(height: 8),
            if (data.savingGoals.isEmpty)
              pw.Text('Chưa có mục tiêu tiết kiệm.',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600))
            else
              pw.TableHelper.fromTextArray(
                headers: ['Tên mục tiêu', 'Đã tiết kiệm', 'Mục tiêu', 'Tiến độ'],
                data: data.savingGoals.map((g) {
                  return [
                    g.goalName,
                    formatMoney(g.savedAmount),
                    formatMoney(g.targetAmount),
                    '${g.percentage.toStringAsFixed(1)}%',
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(font: boldFont, color: PdfColors.white, fontSize: 10),
                headerDecoration: pw.BoxDecoration(color: darkNavy),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                },
              ),

            pw.SizedBox(height: 20),

            // 5. AI FINANCIAL INSIGHTS & SỨC KHỎE
            pw.Text(
              '5. ĐÁNH GIÁ SỨC KHỎE TÀI CHÍNH',
              style: pw.TextStyle(font: boldFont, fontSize: 13, color: darkNavy),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: lightBg,
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Điểm sức khỏe tài chính:', style: pw.TextStyle(font: boldFont)),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: pw.BoxDecoration(
                          color: primaryColor,
                          borderRadius: pw.BorderRadius.circular(12),
                        ),
                        child: pw.Text(
                          '${data.healthScore}/100 - ${data.healthRating}',
                          style: pw.TextStyle(font: boldFont, color: PdfColors.white, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  ...data.insights.map((insight) {
                    return pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 6),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('• ', style: pw.TextStyle(font: boldFont, color: primaryColor)),
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(insight.title, style: pw.TextStyle(font: boldFont, fontSize: 10)),
                                pw.Text(insight.description,
                                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),

            // 6. DỰ BÁO CUỐI THÁNG (Chỉ thêm khi là tháng hiện tại)
            if (data.isCurrentMonth && data.monthEndForecast != null) ...[
              pw.SizedBox(height: 20),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#FEF3C7'), // Light warning amber
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: PdfColor.fromHex('#F59E0B'), width: 1),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          '6. DỰ BÁO CUỐI THÁNG',
                          style: pw.TextStyle(
                              font: boldFont, fontSize: 12, color: PdfColor.fromHex('#92400E')),
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: pw.BoxDecoration(
                            color: PdfColor.fromHex('#D97706'),
                            borderRadius: pw.BorderRadius.circular(4),
                          ),
                          child: pw.Text(
                            'Dự báo, không phải số liệu thực tế',
                            style: pw.TextStyle(
                                font: boldFont, fontSize: 8, color: PdfColors.white),
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 8),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Số dư cuối tháng dự kiến:'),
                        pw.Text(
                          formatMoney(data.monthEndForecast!.projectedEndBalance),
                          style: pw.TextStyle(font: boldFont, fontSize: 11),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Thu định kỳ còn lại:'),
                        pw.Text(formatMoney(data.monthEndForecast!.plannedRemainingIncome)),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Chi định kỳ còn lại:'),
                        pw.Text(formatMoney(data.monthEndForecast!.plannedRemainingExpense)),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Chi tiêu linh hoạt dự kiến:'),
                        pw.Text(formatMoney(
                            data.monthEndForecast!.projectedRemainingDiscretionaryExpense)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ];
        },
      ),
    );

    return pdf.save();
  }

  // ============================================================
  // 4. LƯU VÀ CHIA SẺ FILE
  // ============================================================

  /// Lưu bytes PDF ra file ở thư mục tạm
  Future<File> savePdfToFile(Uint8List pdfBytes, String filenamePrefix, {Directory? outputDir}) async {
    final tempDir = outputDir ?? await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filenamePrefix.pdf');
    await file.writeAsBytes(pdfBytes, flush: true);
    return file;
  }


  /// Mở share sheet native của thiết bị
  Future<void> shareFile(String filePath, {String? text, String? subject}) async {
    final xFile = XFile(filePath);
    await Share.shareXFiles([xFile], text: text, subject: subject);
  }
}
