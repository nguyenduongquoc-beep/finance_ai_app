import 'package:intl/intl.dart';

/// ============================================================
/// FORMATTERS
/// Các hàm định dạng tiền tệ, ngày tháng dùng chung
/// ============================================================
class AppFormatters {
  static final NumberFormat _currencyFormat = NumberFormat.decimalPattern('vi_VN');
  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy');
  static final DateFormat _monthFormat = DateFormat('MM/yyyy');

  /// Format số tiền: 1200000 -> "1.200.000 đ"
  static String currency(num amount) {
    return '${_currencyFormat.format(amount)} đ';
  }

  /// Format số tiền không kèm đơn vị: 1200000 -> "1.200.000"
  static String number(num amount) {
    return _currencyFormat.format(amount);
  }

  /// Format ngày: DateTime -> "10/07/2026"
  static String date(DateTime date) {
    return _dateFormat.format(date);
  }

  /// Format tháng: DateTime -> "07/2026"
  static String month(DateTime date) {
    return _monthFormat.format(date);
  }

  /// Parse chuỗi tiền tệ nhập vào (loại bỏ dấu chấm) -> double
  static double parseCurrencyInput(String input) {
    final cleaned = input.replaceAll('.', '').replaceAll(',', '').replaceAll(' đ', '').trim();
    return double.tryParse(cleaned) ?? 0;
  }
}
