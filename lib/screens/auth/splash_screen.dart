import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthState();
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
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.savings_rounded, size: 90, color: Colors.white),
            const SizedBox(height: 16),
            const Text(
              AppStrings.appName,
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Trợ lý tài chính cá nhân thông minh',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }
}
