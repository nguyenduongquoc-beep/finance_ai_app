import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../widgets/main_navigation.dart';
import '../setup/profile_setup_screen.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';

/// 3. Login Screen - Đăng nhập bằng Email hoặc Google
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  String? _errorMessage;

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _authService.loginWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainNavigation()),
      );
    } catch (e) {
      setState(() => _errorMessage = 'Email hoặc mật khẩu không đúng.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleLogin() async {
    setState(() => _isLoading = true);
    try {
      final credential = await _authService.loginWithGoogle();
      if (credential == null || !mounted) return;
      
      final bool isNewUser = credential.additionalUserInfo?.isNewUser ?? false;
      if (isNewUser) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
        );
      } else {
        final profile = await FirestoreService().getUserProfile(credential.user!.uid);
        if (!mounted) return;
        if (profile == null) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const MainNavigation()),
          );
        }
      }
    } catch (e) {
      setState(() => _errorMessage = 'Đăng nhập Google thất bại.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fixedLightBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                // Heading / Title
                Text(
                  'Chào mừng trở lại 👋',
                  style: GoogleFonts.inter(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.fixedLightTextPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Chào mừng bạn quay lại với ứng dụng quản lý tài chính Finance AI',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppColors.fixedLightTextSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 36),

                // Email Label & Field
                Text(
                  'Địa chỉ Email',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.fixedLightTextPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: GoogleFonts.inter(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'nguyenvana@gmail.com',
                    hintStyle: GoogleFonts.inter(color: Colors.grey.shade400),
                    prefixIcon: const Icon(Icons.email_outlined, color: Colors.grey),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || !v.contains('@')) ? 'Email không hợp lệ' : null,
                ),
                const SizedBox(height: 20),

                // Password Label & Field
                Text(
                  'Mật khẩu',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.fixedLightTextPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: GoogleFonts.inter(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    hintStyle: GoogleFonts.inter(color: Colors.grey.shade400),
                    prefixIcon: const Icon(Icons.lock_outline, color: Colors.grey),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: Colors.grey,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.length < 6) ? 'Mật khẩu tối thiểu 6 ký tự' : null,
                ),
                const SizedBox(height: 12),

                // Remember Me & Forgot Password Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _rememberMe,
                            activeColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                            onChanged: (v) => setState(() => _rememberMe = v ?? false),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Ghi nhớ tôi',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppColors.fixedLightTextSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                      ),
                      child: Text(
                        'Quên mật khẩu?',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Error message
                if (_errorMessage != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _errorMessage!,
                      style: GoogleFonts.inter(color: AppColors.expense, fontSize: 13),
                    ),
                  ),
                ],

                // CTA Login Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isLoading ? null : _handleLogin,
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'Đăng nhập',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 24),

                // Divider "hoặc đăng nhập bằng"
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey.shade200)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'hoặc đăng nhập bằng',
                        style: GoogleFonts.inter(
                          color: AppColors.fixedLightTextSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: Colors.grey.shade200)),
                  ],
                ),
                const SizedBox(height: 24),

                // Google sign-in button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : _handleGoogleLogin,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey.shade200),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      backgroundColor: Colors.white,
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.network(
                          'https://developers.google.com/static/identity/images/g-logo.png',
                          width: 20,
                          height: 20,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: Colors.red.shade100,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                'G',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Đăng nhập bằng Google',
                          style: GoogleFonts.inter(
                            color: AppColors.fixedLightTextPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Footer link "Chưa có tài khoản? Đăng ký ngay"
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RegisterScreen()),
                    ),
                    child: Text.rich(
                      TextSpan(
                        text: 'Chưa có tài khoản? ',
                        style: GoogleFonts.inter(
                          color: AppColors.fixedLightTextSecondary,
                          fontSize: 14,
                        ),
                        children: [
                          TextSpan(
                            text: 'Đăng ký ngay',
                            style: GoogleFonts.inter(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
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
