import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/theme_controller.dart';
import '../utils/constants.dart';

/// Thông tin về ứng dụng — màn tĩnh
class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            title: Text('Thông tin về ứng dụng',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              children: [
                const SizedBox(height: 24),

                // App Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 20),

                // App Name
                Text(
                  AppStrings.appName,
                  style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Phiên bản v1.0.0',
                  style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),

                // Description
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Giới thiệu',
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      const SizedBox(height: 12),
                      Text(
                        'Finance AI là ứng dụng quản lý tài chính cá nhân thông minh, '
                        'tích hợp trí tuệ nhân tạo (AI) để giúp bạn theo dõi thu chi, '
                        'phân tích thói quen chi tiêu và đưa ra các đề xuất cải thiện tài chính.',
                        style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary, height: 1.6),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Features
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tính năng nổi bật',
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      const SizedBox(height: 12),
                      _featureItem(Icons.account_balance_wallet_outlined, 'Quản lý đa ví (tiền mặt, ngân hàng, ví điện tử)'),
                      _featureItem(Icons.bar_chart, 'Ngân sách thông minh với cảnh báo vượt hạn mức'),
                      _featureItem(Icons.auto_awesome, 'Trợ lý AI phân tích chi tiêu và đề xuất cải thiện'),
                      _featureItem(Icons.document_scanner_outlined, 'OCR hóa đơn — tự động nhận diện thông tin từ ảnh'),
                      _featureItem(Icons.savings_outlined, 'Mục tiêu tiết kiệm với theo dõi tiến độ'),
                      _featureItem(Icons.show_chart, 'Biểu đồ xu hướng tài chính 6 tháng'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Tech credits
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Công nghệ sử dụng',
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      const SizedBox(height: 12),
                      _techItem('Flutter', 'Framework phát triển ứng dụng đa nền tảng'),
                      _techItem('Firebase', 'Backend: Authentication, Firestore, Cloud Messaging'),
                      _techItem('Gemini AI', 'Trí tuệ nhân tạo phân tích và tư vấn tài chính'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Contact
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Liên hệ hỗ trợ',
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.email_outlined, size: 18, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text('support@financeai.app',
                              style: GoogleFonts.inter(fontSize: 14, color: AppColors.primary)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Copyright
                Text(
                  '© 2026 Finance AI. All rights reserved.',
                  style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _featureItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary, height: 1.4)),
          ),
        ],
      ),
    );
  }

  Widget _techItem(String name, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6, right: 10),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
                children: [
                  TextSpan(text: '$name — ', style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: desc),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
