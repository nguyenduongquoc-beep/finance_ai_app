import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/wallet_model.dart';
import '../../services/firestore_service.dart';
import '../../services/theme_controller.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/wallet_card.dart';
import '../../widgets/stream_error_widget.dart';
import '../../widgets/app_snackbar.dart';

/// 13. Quản lý ví - Danh sách, Thêm, Sửa, Xóa
class WalletManagementScreen extends StatelessWidget {
  const WalletManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, _, __) {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        final firestoreService = FirestoreService();

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(title: const Text('Quản lý ví')),
          floatingActionButton: FloatingActionButton(
            backgroundColor: AppColors.primary,
            onPressed: () => _showWalletDialog(context, firestoreService, uid),
            child: const Icon(Icons.add, color: Colors.white),
          ),
          body: StreamBuilder<List<Wallet>>(
            stream: firestoreService.streamWallets(uid),
            builder: (context, snap) {
              if (snap.hasError) return StreamErrorWidget(error: snap.error.toString());
              final wallets = snap.data ?? [];
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              if (wallets.isEmpty) {
                return Center(
                    child: Text('Chưa có ví nào', style: TextStyle(color: AppColors.textSecondary)));
              }
              return ListView.builder(
                padding: const EdgeInsets.only(top: 12, bottom: 80),
                itemCount: wallets.length,
                itemBuilder: (context, i) {
                  final wallet = wallets[i];
                  return Dismissible(
                    key: Key(wallet.walletId),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: AppColors.expense,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    confirmDismiss: (direction) async {
                      try {
                        final inUse = await firestoreService.checkWalletInUse(uid, wallet.walletId);
                        if (!inUse) {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Xóa ví?'),
                              content: const Text('Bạn có chắc chắn muốn xóa ví này? Hành động này không thể hoàn tác.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa', style: TextStyle(color: AppColors.expense))),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await firestoreService.deleteWallet(wallet.walletId);
                            return true;
                          }
                          return false;
                        }
                        
                        final defaultWallet = wallets.firstWhere((w) => w.walletId != wallet.walletId, orElse: () => wallet);
                        if (defaultWallet.walletId == wallet.walletId) {
                          if (context.mounted) {
                            AppSnackbar.show(context, 'Không thể xóa ví duy nhất đang chứa giao dịch.', isError: true);
                          }
                          return false;
                        }
                        
                        String? selectedWalletId = defaultWallet.walletId;
                        final confirmReassign = await showDialog<bool>(
                          context: context,
                          builder: (ctx) {
                            return StatefulBuilder(
                              builder: (context, setState) => AlertDialog(
                                title: const Text('Ví đang được sử dụng'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Ví này đang chứa giao dịch. Vui lòng chọn ví để chuyển các giao dịch này sang trước khi xóa:'),
                                    const SizedBox(height: 12),
                                    DropdownButtonFormField<String>(
                                      value: selectedWalletId,
                                      decoration: const InputDecoration(labelText: 'Chuyển sang ví', border: OutlineInputBorder()),
                                      items: wallets
                                          .where((w) => w.walletId != wallet.walletId)
                                          .map((w) => DropdownMenuItem(value: w.walletId, child: Text(w.walletName)))
                                          .toList(),
                                      onChanged: (v) => setState(() => selectedWalletId = v),
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa & Chuyển', style: TextStyle(color: AppColors.expense))),
                                ],
                              ),
                            );
                          },
                        );
                        
                        if (confirmReassign == true && selectedWalletId != null) {
                          await firestoreService.reassignAndDeleteWallet(uid, wallet.walletId, selectedWalletId!);
                          return true;
                        }
                        return false;
                      } catch (e) {
                        debugPrint('❌ Lỗi khi kiểm tra/xóa ví: $e');
                        if (context.mounted) {
                          AppSnackbar.show(context, 'Không thể xóa ví. Vui lòng kiểm tra kết nối và thử lại.', isError: true);
                        }
                        return false;
                      }
                    },
                    onDismissed: (_) {},
                    child: WalletCard(
                      wallet: wallet,
                      onTap: () => _showWalletDialog(context, firestoreService, uid, wallet: wallet),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  void _showWalletDialog(
    BuildContext context,
    FirestoreService firestoreService,
    String uid, {
    Wallet? wallet,
  }) {
    final nameController = TextEditingController(text: wallet?.walletName ?? '');
    final balanceController =
        TextEditingController(text: wallet != null ? wallet.balance.toStringAsFixed(0) : '');
    String type = wallet?.type ?? 'cash';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(wallet == null ? 'Thêm ví' : 'Sửa ví'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Tên ví'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: balanceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Số dư'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: type,
              decoration: const InputDecoration(labelText: 'Loại ví'),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Tiền mặt')),
                DropdownMenuItem(value: 'bank', child: Text('Ngân hàng')),
                DropdownMenuItem(value: 'eWallet', child: Text('Ví điện tử')),
                DropdownMenuItem(value: 'other', child: Text('Khác')),
              ],
              onChanged: (v) => type = v ?? 'cash',
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          TextButton(
            onPressed: () async {
              final balance = AppFormatters.parseCurrencyInput(balanceController.text);
              if (wallet == null) {
                await firestoreService.createWallet(Wallet(
                  walletId: '',
                  userId: uid,
                  walletName: nameController.text.trim(),
                  balance: balance,
                  type: type,
                  createdAt: DateTime.now(),
                ));
              } else {
                await firestoreService.updateWallet(wallet.walletId, {
                  'walletName': nameController.text.trim(),
                  'balance': balance,
                  'type': type,
                });
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }
}
