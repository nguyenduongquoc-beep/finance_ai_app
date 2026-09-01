import 'package:flutter/material.dart';
import '../models/wallet_model.dart';
import '../utils/constants.dart';
import '../utils/formatters.dart';

/// Widget hiển thị một ví tiền (dùng trong danh sách quản lý ví)
class WalletCard extends StatelessWidget {
  final Wallet wallet;
  final VoidCallback? onTap;

  const WalletCard({super.key, required this.wallet, this.onTap});

  IconData get _icon {
    switch (wallet.type) {
      case 'bank':
        return Icons.account_balance;
      case 'eWallet':
        return Icons.phone_iphone;
      case 'cash':
        return Icons.payments;
      default:
        return Icons.account_balance_wallet;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.card,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.15),
          child: Icon(_icon, color: AppColors.primary),
        ),
        title: Text(wallet.walletName, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: Text(
          AppFormatters.currency(wallet.balance),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
