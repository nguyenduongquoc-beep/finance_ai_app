import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../models/wallet_model.dart';
import '../models/category_model.dart';
import '../models/transaction_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../utils/constants.dart';
import '../services/theme_controller.dart';
import 'auth/login_screen.dart';
import 'management/wallet_management_screen.dart';
import 'management/category_management_screen.dart';
import 'management/budget_management_screen.dart';
import 'management/saving_goal_screen.dart';
import 'ai/ai_report_screen.dart';
import 'notification_screen.dart';
import 'personal_info_screen.dart';
import 'about_app_screen.dart';
import '../widgets/stream_error_widget.dart';
import '../widgets/app_snackbar.dart';

/// 21. Profile — Redesign theo Figma
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  ImageProvider? _avatarImage(String? path) {
    if (path == null) return null;
    final file = File(path);
    return file.existsSync() ? FileImage(file) : null;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, _, __) {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        final firestoreService = FirestoreService();
        final authService = AuthService();

        return Scaffold(
          backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Cá nhân'),
      ),
      body: StreamBuilder<AppUser?>(
        stream: firestoreService.streamUserProfile(uid),
        builder: (context, userSnap) {
          if (userSnap.hasError) {
            return StreamErrorWidget(error: userSnap.error.toString());
          }
          final user = userSnap.data;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Header section (Avatar + Name + Email)
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.primary.withOpacity(0.15),
                      backgroundImage: _avatarImage(user?.avatar),
                      child: user?.avatar == null || _avatarImage(user?.avatar) == null
                          ? const Icon(Icons.person, size: 40, color: AppColors.primary)
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      user?.name ?? '',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.email ?? '',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 3 Thống kê: Tổng ví / Tổng danh mục / Tổng giao dịch
              StreamBuilder<List<Wallet>>(
                stream: firestoreService.streamWallets(uid),
                builder: (context, walletSnap) {
                  final walletCount = walletSnap.data?.length ?? 0;
                  return StreamBuilder<List<Category>>(
                    stream: firestoreService.streamCategories(uid),
                    builder: (context, catSnap) {
                      final categoryCount = catSnap.data?.length ?? 0;
                      return StreamBuilder<List<AppTransaction>>(
                        stream: firestoreService.streamTransactions(uid),
                        builder: (context, txSnap) {
                          final transactionCount = txSnap.data?.length ?? 0;
                          return _buildStatRow(walletCount, categoryCount, transactionCount);
                        },
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 24),

              // Nhóm 1: TÀI KHOẢN
              _sectionLabel('TÀI KHOẢN'),
              _menuTile(
                context,
                icon: Icons.person_outline,
                label: 'Thông tin cá nhân',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PersonalInfoScreen()),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Nhóm 2: QUẢN LÝ TÀI CHÍNH
              _sectionLabel('QUẢN LÝ TÀI CHÍNH'),
              _menuTile(
                context,
                icon: Icons.account_balance_wallet_outlined,
                label: 'Quản lý ví',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WalletManagementScreen()),
                  );
                },
              ),
              _menuTile(
                context,
                icon: Icons.category_outlined,
                label: 'Quản lý danh mục',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CategoryManagementScreen()),
                  );
                },
              ),
              _menuTile(
                context,
                icon: Icons.pie_chart_outline,
                label: 'Ngân sách & hạn mức',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const BudgetManagementScreen()),
                  );
                },
              ),
              _menuTile(
                context,
                icon: Icons.flag_outlined,
                label: 'Mục tiêu tiết kiệm',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SavingGoalScreen()),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Nhóm 3: PHÂN TÍCH & THÔNG BÁO
              _sectionLabel('PHÂN TÍCH & THÔNG BÁO'),
              _menuTile(
                context,
                icon: Icons.summarize_outlined,
                label: 'Báo cáo AI',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AiReportScreen()),
                  );
                },
              ),
              _menuTile(
                context,
                icon: Icons.notifications_outlined,
                label: 'Thông báo',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const NotificationScreen()),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Nhóm 4: TÙY CHỈNH
              _sectionLabel('TÙY CHỈNH'),
              // Ngôn ngữ hiển thị (layout only, ticket riêng)
              _menuTile(
                context,
                icon: Icons.language_outlined,
                label: 'Ngôn ngữ hiển thị',
                trailingText: 'Tiếng Việt',
                onTap: () {
                  // TODO: nối màn chọn ngôn ngữ ở ticket đa ngôn ngữ
                  AppSnackbar.show(context, 'Tính năng đang được phát triển');
                },
              ),
              // Tiền tệ mặc định (layout only, ticket riêng)
              _menuTile(
                context,
                icon: Icons.attach_money_outlined,
                label: 'Tiền tệ mặc định',
                trailingText: 'VNĐ',
                onTap: () {
                  // TODO: nối màn chọn tiền tệ
                  AppSnackbar.show(context, 'Tính năng đang được phát triển');
                },
              ),
              // Chế độ tối — nối ThemeController
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ValueListenableBuilder<ThemeMode>(
                  valueListenable: ThemeController.mode,
                  builder: (context, mode, _) {
                    final isDark = mode == ThemeMode.dark;
                    return SwitchListTile(
                      secondary: Icon(
                        isDark ? Icons.wb_sunny_outlined : Icons.dark_mode_outlined,
                        color: AppColors.primary,
                      ),
                      title: const Text('Chế độ tối'),
                      value: isDark,
                      onChanged: (v) => ThemeController.toggle(v),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Nhóm 5: KHÁC
              _sectionLabel('KHÁC'),
              _menuTile(
                context,
                icon: Icons.info_outline,
                label: 'Thông tin về ứng dụng',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AboutAppScreen()),
                  );
                },
              ),
              const SizedBox(height: 24),

              // Nút Đăng xuất
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  leading: const Icon(Icons.logout, color: AppColors.expense),
                  title: const Text(
                    'Đăng xuất',
                    style: TextStyle(color: AppColors.expense, fontWeight: FontWeight.w600),
                  ),
                  onTap: () async {
                    await authService.signOut();
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    }
                  },
                ),
              ),

              // Text Phiên bản
              Center(
                child: Text(
                  'Phiên bản hiện tại: v1.0.0',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  },
);
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: AppColors.textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildStatRow(int walletCount, int categoryCount, int transactionCount) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem('$walletCount', 'Tổng ví'),
          Container(height: 30, width: 1, color: Colors.grey.shade200),
          _statItem('$categoryCount', 'Danh mục'),
          Container(height: 30, width: 1, color: Colors.grey.shade200),
          _statItem('$transactionCount', 'Giao dịch'),
        ],
      ),
    );
  }

  Widget _statItem(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.income,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _menuTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? trailingText,
  }) {
    return Card(
      color: AppColors.card,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trailingText != null) ...[
              Text(
                trailingText,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(width: 6),
            ],
            const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
