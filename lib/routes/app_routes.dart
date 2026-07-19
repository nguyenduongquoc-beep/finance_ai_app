import 'package:flutter/material.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/auth/onboarding_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/setup/profile_setup_screen.dart';
import '../screens/setup/wallet_setup_screen.dart';
import '../screens/setup/category_setup_screen.dart';
import '../widgets/main_navigation.dart';

/// ============================================================
/// APP ROUTES
/// Định nghĩa các route đặt tên dùng chung trong app
/// ============================================================
class AppRoutes {
  static const String splash = '/';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String profileSetup = '/setup/profile';
  static const String walletSetup = '/setup/wallet';
  static const String categorySetup = '/setup/category';
  static const String home = '/home';

  static Map<String, WidgetBuilder> routes = {
    splash: (context) => const SplashScreen(),
    onboarding: (context) => const OnboardingScreen(),
    login: (context) => const LoginScreen(),
    register: (context) => const RegisterScreen(),
    forgotPassword: (context) => const ForgotPasswordScreen(),
    profileSetup: (context) => const ProfileSetupScreen(),
    walletSetup: (context) => const WalletSetupScreen(),
    categorySetup: (context) => const CategorySetupScreen(),
    home: (context) => const MainNavigation(),
  };
}
