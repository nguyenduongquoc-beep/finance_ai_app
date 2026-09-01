import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../utils/constants.dart';
import 'login_screen.dart';

/// 2. Onboarding - 3 trang giới thiệu: Quản lý tài chính / Theo dõi chi tiêu / AI hỗ trợ
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingPage {
  final String imagePath;
  final String title;
  final String description;
  _OnboardingPage(this.imagePath, this.title, this.description);
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  final List<_OnboardingPage> _pages = [
    _OnboardingPage(
      'assets/images/onboarding_1.png',
      'Quản lý tài chính thông minh',
      'Theo dõi thu nhập, chi tiêu và số dư của tất cả ví tiền chỉ trong một ứng dụng duy nhất.',
    ),
    _OnboardingPage(
      'assets/images/onboarding_2.png',
      'Theo dõi chi tiêu thông minh',
      'Xem báo cáo trực quan theo ngày, tuần, tháng và nhận cảnh báo khi vượt ngân sách.',
    ),
    _OnboardingPage(
      'assets/images/onboarding_3.png',
      'Lập ngân sách tự động',
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
    final isLast = _page == _pages.length - 1;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0D2137),
              AppColors.darkBackground,
              Color(0xFF061220),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Skip button
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16, top: 8),
                  child: TextButton(
                    onPressed: _goToLogin,
                    child: Text(
                      'Bỏ qua',
                      style: GoogleFonts.inter(
                        color: AppColors.darkTextSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),

              // Page content
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) {
                    final page = _pages[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          const Spacer(flex: 1),
                          // Illustration with glow effect
                          Container(
                            height: 280,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.accentGreen.withOpacity(0.08),
                                  blurRadius: 60,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: Image.asset(
                                page.imagePath,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const Spacer(flex: 1),
                          // Title
                          Text(
                            page.title,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 14),
                          // Description
                          Text(
                            page.description,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              color: AppColors.darkTextSecondary,
                              fontSize: 14,
                              height: 1.6,
                            ),
                          ),
                          const Spacer(flex: 2),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Dot indicators
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) {
                  final isActive = _page == i;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: isActive ? 28 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.accentGreen
                          : AppColors.darkTextSecondary.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: AppColors.accentGreen.withOpacity(0.4),
                                blurRadius: 8,
                              ),
                            ]
                          : null,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 32),

              // CTA Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppColors.accentGreen,
                          Color(0xFF22C55E),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accentGreen.withOpacity(0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        if (isLast) {
                          _goToLogin();
                        } else {
                          _controller.nextPage(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeInOut,
                          );
                        }
                      },
                      child: Text(
                        isLast ? 'Bắt đầu ngay' : 'Tiếp theo',
                        style: GoogleFonts.inter(
                          color: AppColors.darkBackground,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
