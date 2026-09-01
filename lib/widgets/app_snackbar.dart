import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// ============================================================
/// APP SNACKBAR
/// Helper hiển thị SnackBar thống nhất toàn app — dùng kiểu "floating"
/// để KHÔNG đẩy FloatingActionButton (+) lên khi hiện thông báo.
/// ============================================================
class AppSnackbar {
  static void show(BuildContext context, String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: isError ? Colors.white : AppColors.textPrimary),
        ),
        backgroundColor: isError ? AppColors.expense : AppColors.card,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 90),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
