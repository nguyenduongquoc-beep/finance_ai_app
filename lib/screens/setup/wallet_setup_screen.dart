import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/wallet_model.dart';
import '../../services/firestore_service.dart';
import '../../services/theme_controller.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import 'category_setup_screen.dart';

/// 7. Tạo ví đầu tiên - Tiền mặt / MB Bank / MoMo / ...
class WalletSetupScreen extends StatefulWidget {
  const WalletSetupScreen({super.key});

  @override
  State<WalletSetupScreen> createState() => _WalletSetupScreenState();
}

class _SetupWallet {
  final String name;
  final String type;
  final IconData icon;
  final Color color;
  final TextEditingController controller = TextEditingController();
  bool selected;
  _SetupWallet(this.name, this.type, this.icon, this.color, {this.selected = false});
}

class _WalletSetupScreenState extends State<WalletSetupScreen> {
  final _firestoreService = FirestoreService();
  bool _isLoading = false;

  final List<_SetupWallet> _suggestedWallets = [
    _SetupWallet('Tiền mặt', 'cash', Icons.money_rounded, Colors.green, selected: true),
    _SetupWallet('MB Bank', 'bank', Icons.account_balance_rounded, Colors.blue),
    _SetupWallet('Vietcombank', 'bank', Icons.account_balance_rounded, Colors.teal),
    _SetupWallet('MoMo', 'eWallet', Icons.account_balance_wallet_rounded, Colors.pink),
    _SetupWallet('ZaloPay', 'eWallet', Icons.account_balance_wallet_rounded, Colors.blueAccent),
  ];

  Future<void> _handleContinue() async {
    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final selectedWallets = _suggestedWallets.where((w) => w.selected).toList();

      for (final w in selectedWallets) {
        final balance = AppFormatters.parseCurrencyInput(w.controller.text);
        final wallet = Wallet(
          walletId: '',
          userId: uid,
          walletName: w.name,
          balance: balance,
          type: w.type,
          createdAt: DateTime.now(),
        );
        await _firestoreService.createWallet(wallet);
      }
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const CategorySetupScreen()),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
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
                      'BƯỚC 2/3',
                      style: GoogleFonts.inter(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Title
                  Text(
                    'Thiết lập ví',
                    style: GoogleFonts.inter(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Chọn ví bạn đang dùng và nhập số dư hiện tại để quản lý chi tiêu.',
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: _suggestedWallets.length,
                itemBuilder: (context, i) {
                  final wallet = _suggestedWallets[i];
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: wallet.selected ? AppColors.primary : Colors.grey.shade200,
                        width: wallet.selected ? 1.5 : 1.0,
                      ),
                      boxShadow: wallet.selected
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.08),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ]
                          : null,
                    ),
                    child: Column(
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: CircleAvatar(
                            backgroundColor: wallet.color.withOpacity(0.1),
                            child: Icon(wallet.icon, color: wallet.color),
                          ),
                          title: Text(
                            wallet.name,
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            wallet.type == 'cash'
                                ? 'Tiền mặt thủ công'
                                : wallet.type == 'bank'
                                    ? 'Tài khoản ngân hàng'
                                    : 'Ví điện tử',
                            style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                          ),
                          trailing: Switch(
                            value: wallet.selected,
                            activeThumbColor: AppColors.primary,
                            activeTrackColor: AppColors.primary.withOpacity(0.2),
                            onChanged: (v) => setState(() => wallet.selected = v),
                          ),
                        ),
                        if (wallet.selected) ...[
                          Padding(
                            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
                            child: TextFormField(
                              controller: wallet.controller,
                              keyboardType: TextInputType.number,
                              style: GoogleFonts.inter(fontSize: 14),
                              decoration: InputDecoration(
                                hintText: 'Số dư hiện tại (VNĐ)',
                                isDense: true,
                                prefixIcon: const Icon(Icons.wallet_outlined, size: 20, color: Colors.grey),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: Colors.grey.shade200),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: Colors.grey.shade200),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
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
            ),
          ],
        ),
      ),
    );
  },
);
  }
}
