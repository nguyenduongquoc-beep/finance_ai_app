import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import 'wallet_setup_screen.dart';

/// 6. Khởi tạo hồ sơ - Tên, Thu nhập, Nghề nghiệp, Mục tiêu tiết kiệm
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

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final displayName = FirebaseAuth.instance.currentUser?.displayName;
    if (displayName != null) _nameController.text = displayName;
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
        createdAt: DateTime.now(),
      );
      await _firestoreService.createUserProfile(appUser);
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Khởi tạo hồ sơ'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStepIndicator(step: 1, total: 3),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Tên hiển thị',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Vui lòng nhập tên' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _incomeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Thu nhập hàng tháng (đ)',
                  prefixIcon: Icon(Icons.attach_money),
                  hintText: 'vd: 12000000',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _occupationController,
                decoration: const InputDecoration(
                  labelText: 'Nghề nghiệp',
                  prefixIcon: Icon(Icons.work_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _goalController,
                decoration: const InputDecoration(
                  labelText: 'Mục tiêu tiết kiệm (vd: Mua xe)',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _isLoading ? null : _handleContinue,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Tiếp tục', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator({required int step, required int total}) {
    return Row(
      children: List.generate(total, (i) {
        final active = i < step;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i == total - 1 ? 0 : 6),
            height: 5,
            decoration: BoxDecoration(
              color: active ? AppColors.primary : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }),
    );
  }
}
