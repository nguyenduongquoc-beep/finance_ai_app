import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../widgets/main_navigation.dart';
import '../setup/profile_setup_screen.dart';
import '../setup/wallet_setup_screen.dart';
import 'onboarding_screen.dart';

/// 1. Splash Screen
/// Hiển thị logo, kiểm tra trạng thái đăng nhập
/// -> Nếu đã đăng nhập: Home | Nếu chưa: Onboarding/Login
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _checkAuthState();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _checkAuthState() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      );
    } else {
      final profile = await FirestoreService().getUserProfile(user.uid);
      if (!mounted) return;
      if (profile == null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
        );
      } else {
        final wallets = await FirestoreService().streamWallets(user.uid).first;
        if (!mounted) return;
        if (wallets.isEmpty) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const WalletSetupScreen()),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainNavigation()),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Glowing logo
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.glowGreen
                                .withOpacity(0.3 * _pulseAnimation.value),
                            blurRadius: 40 * _pulseAnimation.value,
                            spreadRadius: 10 * _pulseAnimation.value,
                          ),
                          BoxShadow(
                            color: AppColors.accentGreen
                                .withOpacity(0.15 * _pulseAnimation.value),
                            blurRadius: 80 * _pulseAnimation.value,
                            spreadRadius: 20 * _pulseAnimation.value,
                          ),
                        ],
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.accentGreen.withOpacity(0.2),
                              AppColors.darkSurface,
                            ],
                          ),
                          border: Border.all(
                            color: AppColors.accentGreen.withOpacity(0.4),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.savings_rounded,
                          size: 56,
                          color: AppColors.accentGreen,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),
                // App name
                Text(
                  AppStrings.appName,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                // Subtitle
                Text(
                  'Trợ lý tài chính cá nhân thông minh',
                  style: GoogleFonts.inter(
                    color: AppColors.darkTextSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 48),
                // Loading indicator
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    color: AppColors.accentGreen,
                    strokeWidth: 2.5,
                    backgroundColor: AppColors.darkSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
