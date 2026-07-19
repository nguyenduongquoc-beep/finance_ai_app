import 'package:flutter/material.dart';

/// ============================================================
/// APP CONSTANTS
/// Các hằng số dùng chung trong toàn bộ ứng dụng
/// ============================================================
class AppColors {
  static const Color primary = Color(0xFF2E7D6B); // xanh lá đậm - tài chính, ổn định
  static const Color secondary = Color(0xFF4CAF94);
  static const Color income = Color(0xFF2E7D32); // xanh - thu nhập
  static const Color expense = Color(0xFFD32F2F); // đỏ - chi tiêu
  static const Color background = Color(0xFFF7F8FA);
  static const Color card = Colors.white;
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF757575);
  static const Color warning = Color(0xFFFFA726);
  static const Color aiAccent = Color(0xFF7C4DFF); // tím - điểm nhấn AI
}

class AppStrings {
  static const String appName = 'Finance AI';
}

/// Danh mục mặc định - Thu
class DefaultIncomeCategories {
  static const List<Map<String, dynamic>> categories = [
    {'name': 'Lương', 'icon': 'work', 'color': 0xFF2E7D32},
    {'name': 'Thưởng', 'icon': 'card_giftcard', 'color': 0xFFFBC02D},
    {'name': 'Bán hàng', 'icon': 'storefront', 'color': 0xFF1976D2},
  ];
}

/// Danh mục mặc định - Chi
class DefaultExpenseCategories {
  static const List<Map<String, dynamic>> categories = [
    {'name': 'Ăn uống', 'icon': 'restaurant', 'color': 0xFFD32F2F},
    {'name': 'Mua sắm', 'icon': 'shopping_bag', 'color': 0xFFE64A19},
    {'name': 'Xăng xe', 'icon': 'local_gas_station', 'color': 0xFF5D4037},
    {'name': 'Học tập', 'icon': 'school', 'color': 0xFF1976D2},
    {'name': 'Giải trí', 'icon': 'movie', 'color': 0xFF7B1FA2},
    {'name': 'Du lịch', 'icon': 'flight', 'color': 0xFF0097A7},
    {'name': 'Y tế', 'icon': 'local_hospital', 'color': 0xFFC2185B},
  ];
}

/// Loại giao dịch
enum TransactionType { income, expense }

/// Loại ví
enum WalletType { cash, bank, eWallet, other }
