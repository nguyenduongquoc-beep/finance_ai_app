import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/wallet_model.dart';
import '../../services/firestore_service.dart';
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
  final TextEditingController controller = TextEditingController();
  bool selected;
  _SetupWallet(this.name, this.type, {this.selected = false});
}

class _WalletSetupScreenState extends State<WalletSetupScreen> {
  final _firestoreService = FirestoreService();
  bool _isLoading = false;

  final List<_SetupWallet> _suggestedWallets = [
    _SetupWallet('Tiền mặt', 'cash', selected: true),
    _SetupWallet('MB Bank', 'bank'),
    _SetupWallet('Vietcombank', 'bank'),
    _SetupWallet('MoMo', 'eWallet'),
    _SetupWallet('ZaloPay', 'eWallet'),
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Tạo ví tiền'), automaticallyImplyLeading: false),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStepIndicator(step: 2, total: 3),
                const SizedBox(height: 12),
                const Text('Chọn các ví bạn muốn sử dụng và nhập số dư hiện tại',
                    style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: _suggestedWallets.length,
              itemBuilder: (context, i) {
                final wallet = _suggestedWallets[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: CheckboxListTile(
                    value: wallet.selected,
                    onChanged: (v) => setState(() => wallet.selected = v ?? false),
                    title: Text(wallet.name),
                    subtitle: wallet.selected
                        ? TextField(
                            controller: wallet.controller,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: 'Số dư hiện tại (đ)',
                              isDense: true,
                            ),
                          )
                        : null,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
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
          ),
        ],
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
