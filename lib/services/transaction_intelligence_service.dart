import '../models/category_model.dart';
import '../models/category_suggestion.dart';
import '../models/transaction_anomaly_result.dart';
import '../models/transaction_model.dart';

/// ============================================================
/// TRANSACTION INTELLIGENCE SERVICE
/// Pure Dart service cho Smart Transaction Assistant:
/// 1. Gợi ý danh mục dựa trên keyword, OCR merchant và lịch sử giao dịch.
/// 2. Phát hiện khoản chi bất thường so với lịch sử 90 ngày.
/// ============================================================
class TransactionIntelligenceService {
  /// Bảng từ khóa mở rộng cho các danh mục phổ biến
  static const Map<String, List<String>> _expenseKeywords = {
    'di chuyen': [
      'grab',
      'be',
      'xanh sm',
      'gojek',
      'taxi',
      'xang',
      'xe bus',
      've xe',
      'gui xe',
      'bai xe',
      'di chuyen',
      'giao thong'
    ],
    'an uong': [
      'highlands',
      'starbucks',
      'ca phe',
      'pho',
      'com',
      'tra sua',
      'kfc',
      'mcdonalds',
      'lotte',
      'nha hang',
      'an sang',
      'an trua',
      'an toi',
      'banh mi',
      'nuoc ep',
      'tai xin',
      'quan an',
      'bun',
      'lau',
      'nuong',
      'tra',
      'banh',
      'food',
      'coffee'
    ],
    'mua sam': [
      'shopee',
      'lazada',
      'tiki',
      'sieu thi',
      'quan ao',
      'giay',
      'bach hoa xanh',
      'winmart',
      'circle k',
      '7-eleven',
      'mua sam',
      'thoi trang',
      'my pham',
      'shopping'
    ],
    'hoa don': [
      'dien',
      'nuoc',
      'internet',
      'wifi',
      'truyen hinh',
      'tien dien',
      'tien nuoc',
      'tien nha',
      'rac',
      'hoa don',
      'dich vu',
      'bill'
    ],
    'suc khoe': [
      'thuoc',
      'nha thuoc',
      'benh vien',
      'phong kham',
      'kham benh',
      'pharmedic',
      'pharmacity',
      'long chau',
      'y te',
      'suc khoe'
    ],
    'giai tri': [
      'xem phim',
      'cgv',
      'lotte cinema',
      'du lich',
      'game',
      've xem phim',
      'giai tri',
      'cinema',
      'movie'
    ],
    'giao duc': [
      'hoc phi',
      'sach',
      'khoa hoc',
      'giao duc',
      'truong hoc',
      'hoc tap',
      'hoc tieng anh'
    ],
  };

  static const Map<String, List<String>> _incomeKeywords = {
    'luong': [
      'luong',
      'thuong',
      'income',
      'salary',
      'tien luong',
      'tien thuong',
      'freelance',
      'hoa hong',
      'ban hang',
      'doanh thu',
      'thu nhap',
      'bonus'
    ],
  };

  /// Loại bỏ dấu tiếng Việt và đưa về chữ thường
  static String removeVietnameseDiacritics(String str) {
    var withDiacritics = str.toLowerCase().trim();

    const vietnameseSigns = [
      'aàáạảãâầấậẩẫăằắặẳẵ',
      'eèéẹẻẽêềếệểễ',
      'iìíịỉĩ',
      'oòóọỏõôồốộổỗơờớợởỡ',
      'uùúụủũưừứựửữ',
      'yỳýỵỷỹ',
      'dđ'
    ];

    for (var i = 0; i < vietnameseSigns.length; i++) {
      for (var j = 1; j < vietnameseSigns[i].length; j++) {
        withDiacritics = withDiacritics.replaceAll(
            vietnameseSigns[i][j], vietnameseSigns[i][0]);
      }
    }
    return withDiacritics;
  }

  /// Gợi ý danh mục cho giao dịch
  /// Thứ tự ưu tiên:
  /// 1. Tên cửa hàng từ OCR (nếu có)
  /// 2. Từ khóa trong note
  /// 3. Lịch sử giao dịch tương tự cùng user
  CategorySuggestion suggestCategory({
    required String note,
    String? ocrMerchant,
    required List<Category> categories,
    required String transactionType, // income | expense
    List<AppTransaction>? userHistory,
  }) {
    // Chỉ xét các danh mục active thuộc đúng type (income/expense)
    final validCategories =
        categories.where((c) => c.type == transactionType).toList();

    if (validCategories.isEmpty) {
      return CategorySuggestion.none();
    }

    final normalizedNote = removeVietnameseDiacritics(note);
    final normalizedOcr = ocrMerchant != null ? removeVietnameseDiacritics(ocrMerchant) : '';

    if (normalizedNote.isEmpty && normalizedOcr.isEmpty) {
      return CategorySuggestion.none();
    }

    // 1. Ưu tiên từ OCR merchant
    if (normalizedOcr.isNotEmpty) {
      // 1a. So khớp trực tiếp tên OCR với danh mục
      for (final cat in validCategories) {
        final catNameNorm = removeVietnameseDiacritics(cat.name);
        if (normalizedOcr.contains(catNameNorm) || catNameNorm.contains(normalizedOcr)) {
          return CategorySuggestion(
            categoryId: cat.categoryId,
            categoryName: cat.name,
            confidence: 90,
            reason: 'Gợi ý từ tên cửa hàng trên hóa đơn (${ocrMerchant!})',
            source: 'ocr',
          );
        }
      }
      // 1b. So khớp OCR merchant với bảng từ khóa
      final keywordMatchFromOcr = _matchKeyword(normalizedOcr, validCategories, transactionType);
      if (keywordMatchFromOcr != null) {
        return CategorySuggestion(
          categoryId: keywordMatchFromOcr.categoryId,
          categoryName: keywordMatchFromOcr.name,
          confidence: 85,
          reason: 'Gợi ý từ cửa hàng nhận diện từ hóa đơn (${ocrMerchant!})',
          source: 'ocr',
        );
      }
    }

    // 2. Từ khóa trong note
    if (normalizedNote.isNotEmpty) {
      // 2a. So khớp trực tiếp tên danh mục trong note
      for (final cat in validCategories) {
        final catNameNorm = removeVietnameseDiacritics(cat.name);
        if (catNameNorm.length >= 3 && (normalizedNote.contains(catNameNorm) || catNameNorm.contains(normalizedNote))) {
          return CategorySuggestion(
            categoryId: cat.categoryId,
            categoryName: cat.name,
            confidence: 85,
            reason: 'Khớp tên danh mục "${cat.name}" trong ghi chú',
            source: 'keyword',
          );
        }
      }

      // 2b. So khớp bảng từ khóa
      final keywordMatchFromNote = _matchKeyword(normalizedNote, validCategories, transactionType);
      if (keywordMatchFromNote != null) {
        return CategorySuggestion(
          categoryId: keywordMatchFromNote.categoryId,
          categoryName: keywordMatchFromNote.name,
          confidence: 85,
          reason: 'Khớp từ khóa trong ghi chú',
          source: 'keyword',
        );
      }
    }

    // 3. Từ lịch sử giao dịch tương tự
    if (userHistory != null && userHistory.isNotEmpty) {
      final searchKey = normalizedOcr.isNotEmpty ? normalizedOcr : normalizedNote;
      if (searchKey.isNotEmpty) {
        final categoryCounts = <String, int>{};

        for (final tx in userHistory) {
          if (tx.type != transactionType) continue;
          final txNoteNorm = tx.note != null ? removeVietnameseDiacritics(tx.note!) : '';
          if (txNoteNorm.isEmpty) continue;

          if (txNoteNorm.contains(searchKey) || searchKey.contains(txNoteNorm)) {
            // Chỉ đếm nếu categoryId nằm trong danh mục hợp lệ
            if (validCategories.any((c) => c.categoryId == tx.categoryId)) {
              categoryCounts[tx.categoryId] = (categoryCounts[tx.categoryId] ?? 0) + 1;
            }
          }
        }

        if (categoryCounts.isNotEmpty) {
          // Lấy categoryId có số lần lặp nhiều nhất
          String? bestCatId;
          int maxCount = 0;
          categoryCounts.forEach((catId, count) {
            if (count > maxCount) {
              maxCount = count;
              bestCatId = catId;
            }
          });

          if (bestCatId != null) {
            final cat = validCategories.firstWhere((c) => c.categoryId == bestCatId);
            return CategorySuggestion(
              categoryId: cat.categoryId,
              categoryName: cat.name,
              confidence: 80,
              reason: 'Dựa trên lịch sử giao dịch tương tự ($maxCount lần)',
              source: 'history',
            );
          }
        }
      }
    }

    // Không đoán nếu không khớp hoặc confidence thấp
    return CategorySuggestion.none();
  }

  /// Helper so khớp từ khóa
  Category? _matchKeyword(String text, List<Category> validCategories, String transactionType) {
    final keywordsMap = transactionType == 'income' ? _incomeKeywords : _expenseKeywords;

    for (final entry in keywordsMap.entries) {
      final categoryGroupKey = entry.key; // e.g. 'di chuyen', 'an uong'
      final keywords = entry.value;

      final matched = keywords.any((kw) => text.contains(kw));
      if (matched) {
        // Tìm category nào khớp nhất với categoryGroupKey
        for (final cat in validCategories) {
          final catNorm = removeVietnameseDiacritics(cat.name);
          if (catNorm.contains(categoryGroupKey) || categoryGroupKey.contains(catNorm)) {
            return cat;
          }
        }
        // Thử tìm category đầu tiên có tên chứa một trong các keyword
        for (final cat in validCategories) {
          final catNorm = removeVietnameseDiacritics(cat.name);
          for (final kw in keywords) {
            if (catNorm.contains(kw) || kw.contains(catNorm)) {
              return cat;
            }
          }
        }
      }
    }
    return null;
  }

  /// Phát hiện khoản chi bất thường
  /// Chỉ áp dụng cho `expense`. Không áp dụng cho `income`, `transfer`, `goal_deposit`, `goal_withdraw`.
  /// So sánh với lịch sử 90 ngày gần nhất cùng category.
  TransactionAnomalyResult detectAnomaly({
    required double amount,
    required String categoryId,
    required String categoryName,
    required String transactionType,
    required List<AppTransaction> userHistory,
    DateTime? currentDate,
    String? excludeTransactionId,
  }) {
    // Chỉ áp dụng cho expense
    if (transactionType != 'expense' || categoryId.isEmpty || amount <= 0) {
      return TransactionAnomalyResult.normal();
    }

    final now = currentDate ?? DateTime.now();
    final ninetyDaysAgo = now.subtract(const Duration(days: 90));

    // Lọc lịch sử 90 ngày cùng danh mục
    // Loại trừ giao dịch định kỳ có recurringScheduleId để không làm sai mức chi thông thường
    // Loại trừ giao dịch đang sửa (excludeTransactionId) nếu có
    final filteredHistory = userHistory.where((tx) {
      if (tx.type != 'expense') return false;
      if (tx.categoryId != categoryId) return false;
      if (tx.date.isBefore(ninetyDaysAgo)) return false;
      if (tx.recurringScheduleId != null && tx.recurringScheduleId!.isNotEmpty) {
        return false;
      }
      if (excludeTransactionId != null &&
          excludeTransactionId.isNotEmpty &&
          tx.transactionId == excludeTransactionId) {
        return false;
      }
      return true;
    }).toList();


    // Cần ít nhất 5 giao dịch lịch sử
    if (filteredHistory.length < 5) {
      return TransactionAnomalyResult.normal();
    }

    // Tính median
    final amounts = filteredHistory.map((t) => t.amount).toList()..sort();
    final int n = amounts.length;
    final double median = (n % 2 == 1)
        ? amounts[n ~/ 2]
        : (amounts[(n ~/ 2) - 1] + amounts[n ~/ 2]) / 2.0;

    if (median <= 0) {
      return TransactionAnomalyResult.normal();
    }

    final ratio = amount / median;
    final difference = amount - median;

    // Ngưỡng cảnh báo: amount >= median * 2 VÀ difference >= 100.000 VNĐ
    if (ratio >= 2.0 && difference >= 100000.0) {
      final severity = ratio >= 4.0 ? 'critical' : 'warning';
      final ratioFormatted = ratio.toStringAsFixed(1).replaceAll('.0', '');
      final reason =
          'Khoản chi này cao hơn khoảng $ratioFormatted lần mức chi $categoryName thông thường của bạn trong 90 ngày gần đây.';

      return TransactionAnomalyResult(
        isAnomalous: true,
        severity: severity,
        currentAmount: amount,
        expectedAmount: median,
        ratio: ratio,
        difference: difference,
        categoryName: categoryName,
        historySampleSize: filteredHistory.length,
        reason: reason,
      );
    }

    return TransactionAnomalyResult.normal();
  }
}
