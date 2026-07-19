import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';
import 'auth/login_screen.dart';
import 'management/wallet_management_screen.dart';
import 'management/category_management_screen.dart';
import 'management/budget_management_screen.dart';
import 'management/saving_goal_screen.dart';
import 'ai/ai_report_screen.dart';
import 'notification_screen.dart';
import '../widgets/stream_error_widget.dart';

/// 21. Profile - Thông tin cá nhân, Avatar, Thu nhập, Đổi mật khẩu, Dark Mode, Ngôn ngữ
/// + Truy cập nhanh vào các màn hình quản lý (ví, danh mục, ngân sách, mục tiêu)
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final firestoreService = FirestoreService();
    final authService = AuthService();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Cá nhân')),
      body: StreamBuilder<AppUser?>(
        stream: firestoreService.streamUserProfile(uid),
        builder: (context, snap) {
          if (snap.hasError) return StreamErrorWidget(error: snap.error.toString());
          final user = snap.data;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.primary.withOpacity(0.15),
                      backgroundImage:
                          user?.avatar != null ? NetworkImage(user!.avatar!) : null,
                      child: user?.avatar == null
                          ? const Icon(Icons.person, size: 40, color: AppColors.primary)
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Text(user?.name ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(user?.email ?? '', style: const TextStyle(color: AppColors.textSecondary)),
                    if (user != null) ...[
                      const SizedBox(height: 4),
                      Text('Thu nhập: ${AppFormatters.currency(user.monthlyIncome)}/tháng',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _sectionLabel('Quản lý'),
              _menuTile(context, Icons.account_balance_wallet_outlined, 'Quản lý ví',
                  const WalletManagementScreen()),
              _menuTile(context, Icons.category_outlined, 'Quản lý danh mục',
                  const CategoryManagementScreen()),
              _menuTile(context, Icons.pie_chart_outline, 'Quản lý ngân sách',
                  const BudgetManagementScreen()),
              _menuTile(context, Icons.flag_outlined, 'Mục tiêu tiết kiệm',
                  const SavingGoalScreen()),
              const SizedBox(height: 16),
              _sectionLabel('Báo cáo & Thông báo'),
              _menuTile(context, Icons.summarize_outlined, 'Báo cáo AI', const AiReportScreen()),
              _menuTile(
                  context, Icons.notifications_outlined, 'Thông báo', const NotificationScreen()),
              const SizedBox(height: 16),
              _sectionLabel('Cài đặt'),
              SwitchListTile(
                secondary: const Icon(Icons.dark_mode_outlined),
                title: const Text('Chế độ tối'),
                value: false,
                onChanged: (v) {
                  // TODO: tích hợp ThemeProvider để chuyển Dark Mode
                },
              ),
              ListTile(
                leading: const Icon(Icons.language_outlined),
                title: const Text('Ngôn ngữ'),
                trailing: const Text('Tiếng Việt'),
                onTap: () {
                  // TODO: màn hình chọn ngôn ngữ
                },
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Đổi mật khẩu'),
                onTap: () {
                  // TODO: màn hình đổi mật khẩu
                },
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.logout, color: AppColors.expense),
                title: const Text('Đăng xuất', style: TextStyle(color: AppColors.expense)),
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
            ],
          );
        },
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
    );
  }

  Widget _menuTile(BuildContext context, IconData icon, String label, Widget screen) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)),
      ),
    );
  }
}
