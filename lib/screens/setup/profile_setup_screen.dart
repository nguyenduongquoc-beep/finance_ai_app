import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../services/theme_controller.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import 'wallet_setup_screen.dart';

/// 6. Khởi tạo hồ sơ - Tên, Thu nhập, Nghề nghiệp, Mục tiêu tiết kiệm, Chọn ảnh đại diện
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _incomeController = TextEditingController();
  final _occupationController = TextEditingController();
  final _goalController = TextEditingController();
  final _firestoreService = FirestoreService();
  final ImagePicker _picker = ImagePicker();

  File? _selectedAvatarFile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final displayName = FirebaseAuth.instance.currentUser?.displayName;
    if (displayName != null) _nameController.text = displayName;
  }

  Future<void> _pickAvatar() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (picked != null) {
        setState(() => _selectedAvatarFile = File(picked.path));
      }
    } catch (e) {
      debugPrint('Error picking avatar: $e');
    }
  }

  Future<void> _handleContinue() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      final appUser = AppUser(
        uid: user.uid,
        name: _nameController.text.trim(),
        email: user.email ?? '',
        monthlyIncome: AppFormatters.parseCurrencyInput(_incomeController.text),
        occupation: _occupationController.text.trim(),
        savingGoal: _goalController.text.trim(),
        avatar: null,
        createdAt: DateTime.now(),
      );
      await _firestoreService.createUserProfile(appUser);

      // Upload avatar locally if selected
      if (_selectedAvatarFile != null) {
        try {
          final path = await StorageService().uploadAvatar(user.uid, _selectedAvatarFile!);
          await _firestoreService.updateUserProfile(user.uid, {'avatar': path});
        } catch (avatarError) {
          debugPrint('Avatar upload failed: $avatarError');
        }
      }

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const WalletSetupScreen()),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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
            automaticallyImplyLeading: false,
          ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Step Indicator Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'BƯỚC 1/3',
                    style: GoogleFonts.inter(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Screen title
                Text(
                  'Thiết lập hồ sơ',
                  style: GoogleFonts.inter(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Để phục vụ bạn tốt hơn, hãy cho chúng tôi biết một số thông tin cơ bản.',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 28),

                // Editable Profile Avatar from gallery
                Center(
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey.shade200, width: 2),
                            color: Colors.grey.shade100,
                          ),
                          child: ClipOval(
                            child: _selectedAvatarFile != null
                                ? Image.file(_selectedAvatarFile!, fit: BoxFit.cover)
                                : Image.network(
                                    'https://api.dicebear.com/7.x/adventurer/png?seed=Felix&backgroundColor=b6e3f4',
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => const Icon(
                                      Icons.person,
                                      size: 50,
                                      color: AppColors.primary,
                                    ),
                                  ),
                          ),
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
                            child: const Icon(
                              Icons.camera_alt_outlined,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Họ tên hiển thị
                Text(
                  'Họ tên hiển thị',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameController,
                  style: GoogleFonts.inter(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Nguyễn Văn A',
                    hintStyle: GoogleFonts.inter(color: Colors.grey.shade400),
                    prefixIcon: const Icon(Icons.badge_outlined, color: Colors.grey),
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
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Vui lòng nhập tên' : null,
                ),
                const SizedBox(height: 20),

                // Nghề nghiệp
                Text(
                  'Nghề nghiệp',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _occupationController,
                  style: GoogleFonts.inter(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Lập trình viên',
                    hintStyle: GoogleFonts.inter(color: Colors.grey.shade400),
                    prefixIcon: const Icon(Icons.work_outline, color: Colors.grey),
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
                  ),
                ),
                const SizedBox(height: 20),

                // Thu nhập hàng tháng (VNĐ)
                Text(
                  'Thu nhập hàng tháng (VNĐ)',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _incomeController,
                  keyboardType: TextInputType.number,
                  style: GoogleFonts.inter(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'vd: 12000000',
                    hintStyle: GoogleFonts.inter(color: Colors.grey.shade400),
                    prefixIcon: const Icon(Icons.monetization_on_outlined, color: Colors.grey),
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
                  ),
                ),
                const SizedBox(height: 20),

                // Mục tiêu tiết kiệm
                Text(
                  'Mục tiêu tiết kiệm (vd: Mua xe máy)',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _goalController,
                  style: GoogleFonts.inter(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'vd: Mua xe máy',
                    hintStyle: GoogleFonts.inter(color: Colors.grey.shade400),
                    prefixIcon: const Icon(Icons.flag_outlined, color: Colors.grey),
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
                  ),
                ),
                const SizedBox(height: 36),

                // Continue Button
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
                    onPressed: _isLoading ? null : _handleContinue,
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            'Tiếp tục',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  },
);
  }
}
