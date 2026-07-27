import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:typed_data';
import 'dart:convert';
import '../models/receipt_info.dart';
import '../models/trend_result.dart';
import '../models/transaction_model.dart';
import '../models/category_model.dart';
import '../config/api_keys.dart';

/// ============================================================
/// AI SERVICE
/// Gọi Gemini API để phân tích chi tiêu, dự đoán, chatbot tài chính
///
/// LƯU Ý BẢO MẬT:
/// Gọi trực tiếp Gemini từ client (như hiện tại) sẽ lộ API key trong app.
/// Khi lên bản chính thức, nên chuyển sang gọi qua Cloud Functions
/// (proxy) để giấu API key, tương tự kiến trúc dùng cho các dự án AI khác.
/// Tạm thời dùng trực tiếp để thuận tiện phát triển & demo khóa luận.
/// ============================================================
class AiService {
  // Danh sách model dự phòng, thử lần lượt nếu model chính bị lỗi 404/not found
  static const List<String> _modelFallbackChain = [
    'gemini-3.5-flash',       // model chính, đã xác nhận hoạt động qua Bước 1
    'gemini-3.5-flash-lite',  // dự phòng 1
    'gemini-3.6-flash',       // dự phòng 2
    'gemini-flash-latest',    // dự phòng 3
  ];

  final List<Content> _chatHistory = [];

  AiService() {
    debugPrint('🔧 Model fallback chain: $_modelFallbackChain');
    if (geminiApiKey.isEmpty || geminiApiKey == 'YOUR_GEMINI_API_KEY_HERE') {
      throw Exception('Gemini API key chưa được cấu hình trong config/api_keys.dart');
    }
  }

  // Hàm helper gọi generateContent có tự động thử model dự phòng khi gặp lỗi "not found"
  Future<GenerateContentResponse> _generateWithFallback(List<Content> content) async {
    Exception? lastError;
    for (final modelName in _modelFallbackChain) {
      try {
        debugPrint('🚀 Đang gọi Gemini với model: $modelName');
        final model = GenerativeModel(model: modelName, apiKey: geminiApiKey);
        final response = await model.generateContent(content)
            .timeout(const Duration(seconds: 15));
        return response;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('⚠️ Model "$modelName" thất bại: $e — thử model dự phòng tiếp theo...');
        continue;
      }
    }
    throw lastError ?? Exception('Tất cả model AI đều không khả dụng');
  }

  /// AI 1: Phân tích thói quen chi tiêu (30 ngày gần đây)
  Future<String> analyzeSpendingHabits({
    required List<AppTransaction> transactions,
    required List<Category> categories,
  }) async {
    final summary = _buildCategorySummary(transactions, categories);
    final prompt = '''
Bạn là trợ lý tài chính cá nhân. Dựa trên dữ liệu chi tiêu 30 ngày gần đây sau đây, hãy
phân tích thói quen chi tiêu của người dùng và đưa ra nhận xét ngắn gọn, thân thiện,
kèm 1-2 gợi ý cải thiện cụ thể. Trả lời bằng tiếng Việt, khoảng 3-4 câu.

Dữ liệu chi tiêu theo danh mục:
$summary
''';
    final response = await _generateWithFallback([Content.text(prompt)]);
    return response.text ?? 'Không thể phân tích dữ liệu lúc này.';
  }

  /// AI 3: Dự đoán số tiền chi tiêu cuối tháng
  Future<String> predictMonthEnd({
    required double spentSoFar,
    required int dayOfMonth,
    required int totalDaysInMonth,
  }) async {
    final dailyAvg = spentSoFar / dayOfMonth;
    final predicted = dailyAvg * totalDaysInMonth;
    final prompt = '''
Người dùng đã chi $spentSoFar đồng trong $dayOfMonth ngày đầu tháng (tháng có
$totalDaysInMonth ngày). Với tốc độ chi tiêu trung bình $dailyAvg đồng/ngày, ước tính
tổng chi tiêu cuối tháng sẽ khoảng $predicted đồng. Hãy viết một câu nhận xét ngắn
gọn bằng tiếng Việt cho người dùng về dự đoán này.
''';
    final response = await _generateWithFallback([Content.text(prompt)]);
    return response.text ?? 'Theo tốc độ hiện tại, dự kiến chi tiêu cuối tháng khoảng ${predicted.round()} đồng.';
  }

  /// AI 4: Lập kế hoạch tiết kiệm
  Future<String> generateSavingPlan({
    required String goalName,
    required double targetAmount,
    required int months,
  }) async {
    final monthlyRequired = targetAmount / months;
    final dailyRequired = monthlyRequired / 30;
    final prompt = '''
Người dùng muốn tiết kiệm để mua "$goalName" với số tiền $targetAmount đồng trong
$months tháng. Số tiền cần tiết kiệm là khoảng $monthlyRequired đồng/tháng, tương
đương $dailyRequired đồng/ngày. Hãy viết lời khuyên ngắn gọn, khích lệ bằng tiếng Việt.
''';
    final response = await _generateWithFallback([Content.text(prompt)]);
    return response.text ??
        'Bạn cần tiết kiệm khoảng ${monthlyRequired.round()} đồng/tháng để đạt mục tiêu.';
  }

  /// AI 5: Chatbot tài chính - trả lời câu hỏi dựa trên dữ liệu Firestore
  Future<String> chatWithFinancialData({
    required String userQuestion,
    required String contextData, // dữ liệu tổng hợp từ Firestore (thu/chi/ví/ngân sách)
  }) async {
    if (_chatHistory.isEmpty) {
      _chatHistory.add(Content.text('''
Bạn là trợ lý tài chính cá nhân thông minh. Bạn được cung cấp dữ liệu tài chính thực
tế của người dùng (thu nhập, chi tiêu, ví, ngân sách). Hãy trả lời câu hỏi của người
dùng dựa CHÍNH XÁC trên dữ liệu này, bằng tiếng Việt, ngắn gọn, dễ hiểu.

Dữ liệu tài chính hiện tại của người dùng:
$contextData
'''));
    }
    _chatHistory.add(Content.text(userQuestion));
    try {
      final response = await _generateWithFallback(_chatHistory);
      if (response.text != null) {
        _chatHistory.add(Content.model([TextPart(response.text!)]));
      }
      return response.text ?? 'Xin lỗi, mình chưa thể trả lời câu hỏi này.';
    } catch (e) {
      // Remove last user question to allow retrying
      if (_chatHistory.isNotEmpty) {
        _chatHistory.removeLast();
      }
      rethrow;
    }
  }

  /// AI 2: Phân tích xu hướng tài chính (6 tháng gần nhất)
  Future<TrendResult> analyzeTrend({
    required List<double> monthlySpending, // oldest -> newest (6 months)
  }) async {
    // Ensure we have exactly 6 values, pad with zeros if needed
    final List<double> amounts = List<double>.from(monthlySpending);
    while (amounts.length < 6) {
      amounts.insert(0, 0);
    }
    // Compute overall percent change
    double? percentChange;
    if (amounts.first != 0) {
      percentChange = ((amounts.last - amounts.first) / amounts.first) * 100;
    }
    // Build prompt for Gemini
    final now = DateTime.now();
    final monthLabels = List.generate(6, (i) {
      final month = DateTime(now.year, now.month - (5 - i), 1);
      return 'Tháng ${month.month}/${month.year}';
    });
    final dataLines = List.generate(6, (i) => '- ${monthLabels[i]}: ${amounts[i].toStringAsFixed(0)} đồng');
    final prompt = '''
Bạn là trợ lý tài chính cá nhân. Dựa trên dữ liệu chi tiêu trong 6 tháng gần nhất dưới đây, hãy phân tích xu hướng (tăng, giảm, ổn định) và đưa ra nhận xét ngắn gọn, thân thiện bằng tiếng Việt. Nếu có xu hướng tăng, hãy tính % thay đổi và cung cấp gợi ý quản lý. Dữ liệu:
${dataLines.join('\n')}
''';
    final response = await _generateWithFallback([Content.text(prompt)]);
    final insight = response.text ?? 'Không thể phân tích xu hướng lúc này.';
    return TrendResult(
      monthlyAmounts: amounts,
      insight: insight,
      percentChange: percentChange,
    );
  }

  /// AI 6: Gợi ý cắt giảm chi tiêu cho 1 danh mục cụ thể
  Future<String> suggestSpendingCuts({
    required String categoryName,
    required double currentDailyAvg,
    required double targetDailyAvg,
  }) async {
    final monthlySavings = (currentDailyAvg - targetDailyAvg) * 30;
    final prompt = '''
Người dùng đang chi trung bình $currentDailyAvg đồng/ngày cho "$categoryName".
Nếu giảm xuống còn $targetDailyAvg đồng/ngày, mỗi tháng sẽ tiết kiệm được khoảng
$monthlySavings đồng. Viết một gợi ý ngắn gọn, thực tế bằng tiếng Việt.
''';
    final response = await _generateWithFallback([Content.text(prompt)]);
    return response.text ?? 'Giảm chi tiêu cho $categoryName có thể giúp bạn tiết kiệm thêm.';
  }

  /// AI 7: OCR trích xuất thông tin hoá đơn
  Future<ReceiptInfo?> extractReceiptInfo(Uint8List imageBytes) async {
    try {
      // Build prompt
      const prompt = '''
Bạn là trợ lý tài chính. Hãy trích xuất các thông tin sau từ hoá đơn (ngôn ngữ tiếng Việt):
- Tên cửa hàng/merchant
- Tổng số tiền (đồng)
- Ngày giao dịch (dd/MM/yyyy) nếu có
Trả về kết quả dưới dạng JSON có các trường: merchant, total, date (ISO string hoặc null).
Chỉ trả về JSON thuần túy, không bọc trong markdown code block, không thêm giải thích.''';
      // Create multipart content
      final content = Content.multi([
        TextPart(prompt),
        DataPart('image/jpeg', imageBytes),
      ]);
      final response = await _generateWithFallback([content]);
      if (response.text == null) return null;
      final cleanedText = _stripMarkdownCodeFence(response.text!);
      final Map<String, dynamic> data = jsonDecode(cleanedText);
      return ReceiptInfo.fromJson(data);
    } catch (e) {
      debugPrint('OCR Receipt extraction error: $e');
      return null;
    }
  }

  String _stripMarkdownCodeFence(String text) {
    final trimmed = text.trim();
    final fenceRegex = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$');
    final match = fenceRegex.firstMatch(trimmed);
    return match != null ? match.group(1)!.trim() : trimmed;
  }

  /// Reset phiên chat (khi người dùng vào lại màn hình AI Chat)
  void resetChatSession() {
    _chatHistory.clear();
  }

  String _buildCategorySummary(
      List<AppTransaction> transactions, List<Category> categories) {
    final Map<String, double> totals = {};
    double totalSpent = 0;
    for (final tx in transactions.where((t) => t.type == 'expense')) {
      totals[tx.categoryId] = (totals[tx.categoryId] ?? 0) + tx.amount;
      totalSpent += tx.amount;
    }
    final buffer = StringBuffer();
    totals.forEach((catId, amount) {
      final cat = categories.firstWhere(
        (c) => c.categoryId == catId,
        orElse: () => Category(
            categoryId: catId,
            userId: '',
            name: 'Khác',
            type: 'expense',
            icon: 'category',
            color: 0xFF9E9E9E),
      );
      final percent = totalSpent == 0 ? 0 : (amount / totalSpent * 100).round();
      buffer.writeln('- ${cat.name}: ${amount.round()} đồng ($percent%)');
    });
    return buffer.toString();
  }
}
