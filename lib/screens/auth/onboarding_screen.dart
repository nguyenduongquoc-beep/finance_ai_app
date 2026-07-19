import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import 'login_screen.dart';

/// 2. Onboarding - 3 trang giới thiệu: Quản lý tài chính / Theo dõi chi tiêu / AI hỗ trợ
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingPage {
  final IconData icon;
  final String title;
  final String description;
  _OnboardingPage(this.icon, this.title, this.description);
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  final List<_OnboardingPage> _pages = [
    _OnboardingPage(
      Icons.account_balance_wallet_rounded,
      'Quản lý tài chính',
      'Theo dõi thu nhập, chi tiêu và số dư của tất cả ví tiền chỉ trong một ứng dụng.',
    ),
    _OnboardingPage(
      Icons.bar_chart_rounded,
      'Theo dõi chi tiêu',
      'Xem báo cáo trực quan theo ngày, tuần, tháng và nhận cảnh báo khi vượt ngân sách.',
    ),
    _OnboardingPage(
      Icons.auto_awesome_rounded,
      'AI hỗ trợ',
      'AI phân tích thói quen chi tiêu, dự đoán ngân sách và tư vấn tài chính dựa trên dữ liệu thật của bạn.',
    ),
  ];

  void _goToLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _goToLogin,
                child: const Text('Bỏ qua'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final page = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(page.icon, size: 110, color: AppColors.primary),
                        const SizedBox(height: 32),
                        Text(page.title,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Text(page.description,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _page == i ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _page == i ? AppColors.primary : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    if (_page == _pages.length - 1) {
                      _goToLogin();
                    } else {
                      _controller.nextPage(
                          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                    }
                  },
                  child: Text(
                    _page == _pages.length - 1 ? 'Bắt đầu' : 'Tiếp tục',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
