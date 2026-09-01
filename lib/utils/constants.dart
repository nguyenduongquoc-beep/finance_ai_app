import 'package:flutter/material.dart';
import '../services/theme_controller.dart';

/// ============================================================
/// APP CONSTANTS
/// Các hằng số dùng chung trong toàn bộ ứng dụng
/// ============================================================
class AppColors {
  static const Color primary = Color(0xFF2E7D6B); // xanh lá đậm - tài chính, ổn định
  static const Color secondary = Color(0xFF4CAF94);
  static const Color income = Color(0xFF2E7D32); // xanh - thu nhập
  static const Color expense = Color(0xFFD32F2F); // đỏ - chi tiêu
  static const Color warning = Color(0xFFFFA726);
  static const Color aiAccent = Color(0xFF7C4DFF); // tím - điểm nhấn AI

  // Đổi động theo ThemeController.isDark
  static Color get background =>
      ThemeController.isDark ? const Color(0xFF121212) : const Color(0xFFF7F8FA);
  static Color get card =>
      ThemeController.isDark ? const Color(0xFF1E1E1E) : Colors.white;
  static Color get textPrimary =>
      ThemeController.isDark ? const Color(0xFFF5F5F5) : const Color(0xFF1A1A1A);
  static Color get textSecondary =>
      ThemeController.isDark ? const Color(0xFFB0B0B0) : const Color(0xFF757575);

  // Dùng riêng cho nhóm màn Auth — LUÔN sáng, không phụ thuộc ThemeController
  static const Color fixedLightBackground = Color(0xFFF7F8FA);
  static const Color fixedLightCard = Colors.white;
  static const Color fixedLightTextPrimary = Color(0xFF1A1A1A);
  static const Color fixedLightTextSecondary = Color(0xFF757575);

  // Dark theme colors — splash, onboarding, login
  static const Color darkBackground = Color(0xFF0A1A2E);
  static const Color darkSurface = Color(0xFF112240);
  static const Color darkCard = Color(0xFF1A2F4A);
  static const Color accentGreen = Color(0xFF4ADE80);
  static const Color glowGreen = Color(0xFF00E676);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFB0BEC5);
  static const Color darkDivider = Color(0xFF1E3A5F);
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
