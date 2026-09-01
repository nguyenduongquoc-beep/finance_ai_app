import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/storage_service.dart';
import '../services/theme_controller.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';
import '../widgets/app_snackbar.dart';

/// Thông tin cá nhân — chỉnh sửa hồ sơ + đổi mật khẩu
class PersonalInfoScreen extends StatefulWidget {
  const PersonalInfoScreen({super.key});

  @override
  State<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends State<PersonalInfoScreen> {
  final _firestoreService = FirestoreService();
  final _authService = AuthService();
  final _picker = ImagePicker();

  final _nameController = TextEditingController();
  final _incomeController = TextEditingController();
  final _occupationController = TextEditingController();

  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  AppUser? _user;
  String? _avatarPath;
  File? _newAvatarFile;
  bool _isLoading = false;
  bool _isSavingProfile = false;
  bool _isChangingPassword = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final user = await _firestoreService.getUserProfile(uid);
    if (user != null && mounted) {
      setState(() {
        _user = user;
        _avatarPath = user.avatar;
        _nameController.text = user.name;
        _incomeController.text = user.monthlyIncome > 0
            ? user.monthlyIncome.toInt().toString()
            : '';
        _occupationController.text = user.occupation ?? '';
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _incomeController.dispose();
    _occupationController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (picked != null) {
        setState(() => _newAvatarFile = File(picked.path));
      }
    } catch (e) {
      debugPrint('Error picking avatar: $e');
    }
  }

  ImageProvider? _avatarImage() {
    if (_newAvatarFile != null) return FileImage(_newAvatarFile!);
    if (_avatarPath != null) {
      final file = File(_avatarPath!);
      if (file.existsSync()) return FileImage(file);
    }
    return null;
  }

  Future<void> _saveProfile() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      AppSnackbar.show(context, 'Vui lòng nhập tên hiển thị', isError: true);
      return;
    }

    setState(() => _isSavingProfile = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

      // Upload new avatar if selected
      if (_newAvatarFile != null) {
        try {
          final path = await StorageService().uploadAvatar(uid, _newAvatarFile!);
          await _firestoreService.updateUserProfile(uid, {'avatar': path});
          setState(() {
            _avatarPath = path;
            _newAvatarFile = null;
          });
        } catch (e) {
          debugPrint('Avatar upload failed: $e');
        }
      }

      await _firestoreService.updateUserProfile(uid, {
        'name': name,
        'monthlyIncome': AppFormatters.parseCurrencyInput(_incomeController.text),
        'occupation': _occupationController.text.trim(),
      });

      if (mounted) {
        AppSnackbar.show(context, 'Đã lưu thông tin thành công');
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.show(context, 'Lỗi: ${e.toString()}', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSavingProfile = false);
    }
  }

  Future<void> _changePassword() async {
    final current = _currentPasswordController.text;
    final newPass = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;

    if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
      AppSnackbar.show(context, 'Vui lòng nhập đầy đủ các trường mật khẩu', isError: true);
      return;
    }
    if (newPass.length < 6) {
      AppSnackbar.show(context, 'Mật khẩu mới phải có ít nhất 6 ký tự', isError: true);
      return;
    }
    if (newPass != confirm) {
      AppSnackbar.show(context, 'Xác nhận mật khẩu không khớp', isError: true);
      return;
    }

    setState(() => _isChangingPassword = true);
    try {
      await _authService.changePassword(
        currentPassword: current,
        newPassword: newPass,
      );
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      if (mounted) {
        AppSnackbar.show(context, 'Đổi mật khẩu thành công!');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        final msg = e.code == 'wrong-password' || e.code == 'invalid-credential'
            ? 'Mật khẩu hiện tại không đúng'
            : 'Không thể đổi mật khẩu, vui lòng thử lại';
        AppSnackbar.show(context, msg, isError: true);
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.show(context, 'Không thể đổi mật khẩu, vui lòng thử lại', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isChangingPassword = false);
    }
  }

  Future<void> _sendResetEmail() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null) return;
    try {
      await _authService.sendPasswordResetEmail(email);
      if (mounted) {
        AppSnackbar.show(context, 'Đã gửi email đặt lại mật khẩu tới $email');
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.show(context, 'Không thể gửi email, vui lòng thử lại', isError: true);
      }
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon, {String? hint, Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.inter(color: AppColors.textSecondary),
      hintText: hint,
      hintStyle: GoogleFonts.inter(color: AppColors.textSecondary),
      prefixIcon: Icon(icon, color: AppColors.textSecondary),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppColors.card,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, _, __) {
        if (_isLoading || _user == null) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              backgroundColor: AppColors.background,
              elevation: 0,
              title: Text('Thông tin cá nhân',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final isEmailProvider = FirebaseAuth.instance.currentUser?.providerData
            .any((p) => p.providerId == 'password') ?? false;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            title: Text('Thông tin cá nhân',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                      backgroundImage: _avatarImage(),
                      child: _avatarImage() == null
                          ? const Icon(Icons.person, size: 50, color: AppColors.primary)
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),

            // Name
            Text('Họ tên hiển thị', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              style: GoogleFonts.inter(fontSize: 15),
              decoration: _inputDecoration('Họ tên hiển thị', Icons.badge_outlined, hint: 'Nguyễn Văn A'),
            ),
            const SizedBox(height: 20),

            // Email (read-only)
            Text('Email', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              readOnly: true,
              controller: TextEditingController(text: _user!.email),
              style: GoogleFonts.inter(fontSize: 15, color: AppColors.textSecondary),
              decoration: _inputDecoration('Email', Icons.email_outlined).copyWith(
                fillColor: Colors.grey.shade100,
              ),
            ),
            const SizedBox(height: 20),

            // Occupation
            Text('Nghề nghiệp', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _occupationController,
              style: GoogleFonts.inter(fontSize: 15),
              decoration: _inputDecoration('Nghề nghiệp', Icons.work_outline, hint: 'Lập trình viên'),
            ),
            const SizedBox(height: 20),

            // Monthly income
            Text('Thu nhập hàng tháng (VNĐ)', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _incomeController,
              keyboardType: TextInputType.number,
              style: GoogleFonts.inter(fontSize: 15),
              decoration: _inputDecoration('Thu nhập hàng tháng', Icons.monetization_on_outlined, hint: 'vd: 12000000'),
            ),
            const SizedBox(height: 20),

            const SizedBox(height: 28),

            // Save profile button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isSavingProfile ? null : _saveProfile,
                child: _isSavingProfile
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Lưu thay đổi',
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),

            const SizedBox(height: 32),

            // Password section wrapped in a styled card Container
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Đổi mật khẩu',
                      style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  const SizedBox(height: 16),

                  if (!isEmailProvider) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: AppColors.warning),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Tài khoản đang đăng nhập bằng Google, không thể đổi mật khẩu tại đây.',
                              style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: _currentPasswordController,
                      obscureText: _obscureCurrent,
                      style: GoogleFonts.inter(fontSize: 15),
                      decoration: _inputDecoration(
                        'Mật khẩu hiện tại',
                        Icons.lock_outline,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureCurrent ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _newPasswordController,
                      obscureText: _obscureNew,
                      style: GoogleFonts.inter(fontSize: 15),
                      decoration: _inputDecoration(
                        'Mật khẩu mới',
                        Icons.lock_reset,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: () => setState(() => _obscureNew = !_obscureNew),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirm,
                      style: GoogleFonts.inter(fontSize: 15),
                      decoration: _inputDecoration(
                        'Xác nhận mật khẩu mới',
                        Icons.lock_outline,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isChangingPassword ? null : _changePassword,
                        child: _isChangingPassword
                            ? const SizedBox(width: 22, height: 22,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text('Cập nhật mật khẩu',
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: _sendResetEmail,
                        child: Text(
                          'Quên mật khẩu hiện tại?',
                          style: GoogleFonts.inter(
                            color: AppColors.primary,
                            fontSize: 14,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  },
);
  }
}
