import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================
/// THEME CONTROLLER
/// Quản lý trạng thái Dark Mode toàn app bằng ValueNotifier (đơn giản,
/// không cần thêm package quản lý state mới). Lưu lựa chọn qua
/// shared_preferences để giữ nguyên qua các lần mở app.
/// ============================================================
class ThemeController {
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.light);
  static const _prefKey = 'theme_mode';

  /// Gọi 1 lần trong main() TRƯỚC khi runApp(), để nạp đúng lựa chọn
  /// đã lưu từ lần trước (nếu có).
  static Future<void> loadSavedTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    mode.value = saved == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }

  static Future<void> toggle(bool isDark) async {
    mode.value = isDark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, isDark ? 'dark' : 'light');
  }

  static bool get isDark => mode.value == ThemeMode.dark;
}
