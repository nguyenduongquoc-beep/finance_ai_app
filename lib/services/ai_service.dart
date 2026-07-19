import 'package:google_generative_ai/google_generative_ai.dart';
import 'dart:io';
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

  static const String _modelName = 'gemini-2.5-flash';

  late final GenerativeModel _model;
  ChatSession? _chatSession;

  AiService() {
    _model = GenerativeModel(model: _modelName, apiKey: geminiApiKey);
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
    final response = await _model.generateContent([Content.text(prompt)]);
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
    final response = await _model.generateContent([Content.text(prompt)]);
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
    final response = await _model.generateContent([Content.text(prompt)]);
    return response.text ??
        'Bạn cần tiết kiệm khoảng ${monthlyRequired.round()} đồng/tháng để đạt mục tiêu.';
  }

  /// AI 5: Chatbot tài chính - trả lời câu hỏi dựa trên dữ liệu Firestore
  Future<String> chatWithFinancialData({
    required String userQuestion,
    required String contextData, // dữ liệu tổng hợp từ Firestore (thu/chi/ví/ngân sách)
  }) async {
    _chatSession ??= _model.startChat(history: [
      Content.text('''
Bạn là trợ lý tài chính cá nhân thông minh. Bạn được cung cấp dữ liệu tài chính thực
tế của người dùng (thu nhập, chi tiêu, ví, ngân sách). Hãy trả lời câu hỏi của người
dùng dựa CHÍNH XÁC trên dữ liệu này, bằng tiếng Việt, ngắn gọn, dễ hiểu.

Dữ liệu tài chính hiện tại của người dùng:
$contextData
'''),
    ]);
    final response = await _chatSession!.sendMessage(Content.text(userQuestion));
    return response.text ?? 'Xin lỗi, mình chưa thể trả lời câu hỏi này.';
  }

  /// AI 6: Gợi ý cắt giảm chi tiêu cho 1 danh mục cụ thể
  
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
    final monthLabels = List.generate(6, (i) => 'Tháng ${i + 1}');
    final dataLines = List.generate(6, (i) => '- ${monthLabels[i]}: ${amounts[i].toStringAsFixed(0)} đồng');
    final prompt = '''
Bạn là trợ lý tài chính cá nhân. Dựa trên dữ liệu chi tiêu trong 6 tháng gần nhất dưới đây, hãy phân tích xu hướng (tăng, giảm, ổn định) và đưa ra nhận xét ngắn gọn, thân thiện bằng tiếng Việt. Nếu có xu hướng tăng, hãy tính % thay đổi và cung cấp gợi ý quản lý. Dữ liệu:
${dataLines.join('\n')}
''';
    final response = await _model.generateContent([Content.text(prompt)]);
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
    final response = await _model.generateContent([Content.text(prompt)]);
    return response.text ?? 'Giảm chi tiêu cho $categoryName có thể giúp bạn tiết kiệm thêm.';
  }

  /// Reset phiên chat (khi người dùng vào lại màn hình AI Chat)

  /// AI 7: OCR trích xuất thông tin hoá đơn
  Future<ReceiptInfo?> extractReceiptInfo(File receiptImage) async {
    try {
      // Read image bytes
      final bytes = await receiptImage.readAsBytes();
      // Build prompt
      final prompt = '''
Bạn là trợ lý tài chính. Hãy trích xuất các thông tin sau từ hoá đơn (ngôn ngữ tiếng Việt):
- Tên cửa hàng/merchant
- Tổng số tiền (đồng)
- Ngày giao dịch (dd/MM/yyyy) nếu có
Trả về kết quả dưới dạng JSON có các trường: merchant, total, date (ISO string hoặc null).''';
      // Create multipart content
      final content = Content.multi([
        TextPart(prompt),
        DataPart('image/jpeg', bytes),
      ]);
      final response = await _model.generateContent([content]);
      if (response.text == null) return null;
      final Map<String, dynamic> data = jsonDecode(response.text!.trim());
      return ReceiptInfo.fromJson(data);
    } catch (e) {
      return null;
    }
  }

  /// Reset phiên chat (khi người dùng vào lại màn hình AI Chat)
  void resetChatSession() {
    _chatSession = null;
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
