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

/// 13. Ví của tôi — Danh sách, Thêm, Sửa, Ẩn/Xóa ví
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
          appBar: AppBar(title: const Text('Ví của tôi')),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
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

              // Lọc ví active ở client
              final activeWallets = wallets.where((w) => w.isActive).toList();
              final totalAssets = activeWallets.fold<double>(0, (a, w) => a + w.balance);

              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: activeWallets.length + 1, // +1 cho Card TỔNG TÀI SẢN
                itemBuilder: (context, index) {
                  if (index == 0) {
                    // Card TỔNG TÀI SẢN
                    return Container(
                      margin: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TỔNG TÀI SẢN',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            AppFormatters.currency(totalAssets),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 24,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final wallet = activeWallets[index - 1];
                  final shareOfTotal = totalAssets == 0 ? 0.0 : (wallet.balance / totalAssets).clamp(0.0, 1.0);

                  return GestureDetector(
                    onLongPress: () => _handleDeleteWallet(
                      context,
                      firestoreService,
                      uid,
                      wallet,
                      activeWallets,
                    ),
                    child: WalletCard(
                      wallet: wallet,
                      shareOfTotal: shareOfTotal,
                      onTap: () => _showWalletDialog(context, firestoreService, uid, wallet: wallet),
                      onLongPress: () => _handleDeleteWallet(
                        context,
                        firestoreService,
                        uid,
                        wallet,
                        activeWallets,
                      ),
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

  Future<void> _handleDeleteWallet(
    BuildContext context,
    FirestoreService firestoreService,
    String uid,
    Wallet wallet,
    List<Wallet> activeWallets,
  ) async {
    try {
      final inUse = await firestoreService.checkWalletInUse(uid, wallet.walletId);
      if (!inUse) {
        if (!context.mounted) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Xóa ví?'),
            content: Text('Bạn có chắc chắn muốn xóa ví "${wallet.walletName}"? Hành động này không thể hoàn tác.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Xóa', style: TextStyle(color: AppColors.expense)),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await firestoreService.deleteWallet(wallet.walletId);
        }
        return;
      }

      // Ví đang được sử dụng -> Cung cấp 2 lựa chọn "Ẩn ví" hoặc "Chuyển & Xóa"
      if (!context.mounted) return;
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ví đang được sử dụng'),
          content: Text(
            'Ví "${wallet.walletName}" đang có giao dịch liên kết. Bạn có thể ẨN ví (giữ nguyên lịch sử giao dịch cũ, '
            'không hiện ví này khi tạo giao dịch mới) hoặc CHUYỂN toàn bộ giao dịch sang ví khác rồi xóa hẳn.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Hủy')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'hide'),
              child: const Text('Ẩn ví', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'reassign'),
              child: const Text('Chuyển & Xóa', style: TextStyle(color: AppColors.expense)),
            ),
          ],
        ),
      );

      if (action == 'hide') {
        await firestoreService.setWalletActive(wallet.walletId, false);
        return;
      }

      if (action == 'reassign') {
        final otherWallets = activeWallets.where((w) => w.walletId != wallet.walletId).toList();
        if (otherWallets.isEmpty) {
          if (context.mounted) {
            AppSnackbar.show(context, 'Không thể xóa ví duy nhất đang chứa giao dịch.', isError: true);
          }
          return;
        }

        String? selectedWalletId = otherWallets.first.walletId;
        if (!context.mounted) return;
        final confirmReassign = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            return StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                title: const Text('Chuyển giao dịch'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Vui lòng chọn ví để chuyển toàn bộ giao dịch sang trước khi xóa:'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedWalletId,
                      decoration: const InputDecoration(
                        labelText: 'Chuyển sang ví',
                        border: OutlineInputBorder(),
                      ),
                      items: otherWallets
                          .map((w) => DropdownMenuItem(value: w.walletId, child: Text(w.walletName)))
                          .toList(),
                      onChanged: (v) => setState(() => selectedWalletId = v),
                    ),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Xóa & Chuyển', style: TextStyle(color: AppColors.expense)),
                  ),
                ],
              ),
            );
          },
        );

        if (confirmReassign == true && selectedWalletId != null) {
          await firestoreService.reassignAndDeleteWallet(uid, wallet.walletId, selectedWalletId!);
          return;
        }
      }
    } catch (e) {
      debugPrint('❌ Lỗi khi xử lý xóa/ẩn ví: $e');
      if (context.mounted) {
        AppSnackbar.show(context, 'Không thể thực hiện thao tác. Vui lòng thử lại.', isError: true);
      }
    }
  }

  void _showWalletDialog(
    BuildContext context,
    FirestoreService firestoreService,
    String uid, {
    Wallet? wallet,
  }) {
    final nameController = TextEditingController(text: wallet?.walletName ?? '');
    final descController = TextEditingController(text: wallet?.description ?? '');
    final balanceController =
        TextEditingController(text: wallet != null ? wallet.balance.toStringAsFixed(0) : '');
    String type = wallet?.type ?? 'cash';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(wallet == null ? 'Thêm ví mới' : 'Sửa ví'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Tên ví'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'Mô tả (tùy chọn)',
                  hintText: 'VD: Chi tiêu sinh hoạt hàng ngày',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: balanceController,
                enabled: wallet == null, // Khóa field số dư khi sửa ví đã tồn tại
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: wallet == null ? 'Số dư ban đầu' : 'Số dư hiện tại',
                  helperText: wallet != null
                      ? 'Số dư tự động đồng bộ từ giao dịch, không thể chỉnh sửa tay'
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: type,
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
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          TextButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;

              final desc = descController.text.trim();
              final balance = AppFormatters.parseCurrencyInput(balanceController.text);

              try {
                if (wallet == null) {
                  await firestoreService.createWallet(Wallet(
                    walletId: '',
                    userId: uid,
                    walletName: name,
                    balance: balance,
                    initialBalance: balance,
                    type: type,
                    description: desc.isNotEmpty ? desc : null,
                    createdAt: DateTime.now(),
                  ));
                } else {
                  await firestoreService.updateWallet(wallet.walletId, {
                    'walletName': name,
                    'type': type,
                    'description': desc.isNotEmpty ? desc : null,
                    'updatedAt': DateTime.now().toIso8601String(),
                  });
                }
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                debugPrint('❌ Lỗi khi lưu ví: $e');
                if (ctx.mounted) {
                  AppSnackbar.show(context, 'Không thể lưu ví. Vui lòng thử lại.', isError: true);
                }
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }
}
