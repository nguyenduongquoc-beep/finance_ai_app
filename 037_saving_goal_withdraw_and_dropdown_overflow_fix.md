# TICKET 037 — Bổ sung chức năng "Rút tiền" từ mục tiêu tiết kiệm, hoàn thiện mô hình "Giữ tiền hộ" + sửa lỗi giao diện dropdown chọn ví bị tràn chữ

**Loại:** Feature mới (hoàn thiện logic nghiệp vụ) + Bug fix UI nhỏ
**Độ ưu tiên:** Cao — hoàn thiện mô hình dữ liệu đã thống nhất cho Mục tiêu tiết kiệm, cần xong trước khi báo cáo
**File bị ảnh hưởng:** `lib/screens/management/saving_goal_screen.dart`

---

## 1. Context (Bối cảnh)

Sau khi thảo luận và thống nhất mô hình nghiệp vụ cho tính năng "Nạp tiền vào mục tiêu tiết kiệm" (đã triển khai ở Ticket 034), đã chốt chọn **mô hình "Giữ tiền hộ"**:

> Nạp tiền vào mục tiêu = **tạm khóa** số tiền đó lại (trừ khỏi ví, cộng vào `savedAmount` của mục tiêu). Người dùng có thể đổi ý **rút lại** bất cứ lúc nào (cộng lại vào 1 ví, trừ khỏi `savedAmount`). Về bản chất, đây là 1 dạng **chuyển tiền nội bộ** giữa "ví" và "mục tiêu" — tiền không hề rời khỏi tổng tài sản của người dùng, chỉ đổi trạng thái từ "sẵn sàng dùng" sang "đã khóa cho mục tiêu X".

Ticket 034 đã triển khai xong phần **Nạp tiền** (trừ ví nguồn, cộng `savedAmount`). Ticket này bổ sung phần còn thiếu để mô hình "Giữ tiền hộ" hoàn chỉnh: **Rút tiền** (chiều ngược lại).

Đồng thời sửa 1 lỗi giao diện nhỏ đã phát hiện khi test Ticket 034: dropdown "Nạp từ ví" bị tràn chữ ra ngoài khung dialog khi tên ví + số dư quá dài (báo lỗi "RIGHT OVERFLOWED BY 20 PIXELS" hiện trên UI thật).

## 2. Quyết định kiến trúc quan trọng — KHÔNG ghi vào collection `transactions`

Đã cân nhắc việc ghi lại mỗi lần Nạp/Rút thành 1 document trong Firestore `transactions` (loại `transfer`) để hiện trong Lịch sử giao dịch, nhưng **quyết định KHÔNG làm** ở ticket này vì lý do kỹ thuật cụ thể:

- Giao dịch loại `transfer` trong model hiện tại **bắt buộc** phải có `toWalletId` trỏ tới 1 document **có thật** trong collection `wallets` (`FirestoreService.createTransaction()` sẽ `throw Exception` nếu `toWalletId` rỗng khi `type == 'transfer'`).
- "Mục tiêu tiết kiệm" **không phải** là 1 ví — không có document tương ứng trong `wallets`, nên không thể gán làm `toWalletId`/`walletId` hợp lệ.
- Để ép được việc này vào `transactions` sẽ cần đổi cấu trúc dữ liệu (VD thêm field mới `goalId` vào `AppTransaction`, nới lỏng điều kiện bắt buộc `toWalletId`...) — đây là thay đổi schema lớn hơn phạm vi hợp lý của 1 ticket, và tiềm ẩn rủi ro ảnh hưởng tới toàn bộ logic atomic transaction đã ổn định (Ticket 010, 026).

**→ Quyết định:** giữ đúng như cách Ticket 034 đã làm — Nạp/Rút chỉ cập nhật trực tiếp `savedAmount` của mục tiêu và `balance` của ví liên quan qua `adjustWalletBalance()`, **không** tạo thêm document trong `transactions`. Sự minh bạch của dòng tiền được thể hiện qua chính card Mục tiêu tiết kiệm (luôn hiện rõ "Đã tiết kiệm: X / Mục tiêu: Y"), không cần trùng lặp thêm trong Lịch sử giao dịch. Đây là điểm cần nêu rõ khi báo cáo nếu được hỏi "vì sao nạp/rút tiền không hiện trong lịch sử giao dịch" — trả lời đúng bằng lý do kỹ thuật ở trên, không phải thiếu sót.

## 3. Fix Requirements

### 3.1. Sửa lỗi giao diện — dropdown "Nạp từ ví" bị tràn chữ

Trong `_addDeposit()` (đã có từ Ticket 034), sửa `DropdownButtonFormField` như sau:
```dart
DropdownButtonFormField<String>(
  initialValue: selectedWalletId,
  isExpanded: true, // MỚI — chặn tràn ngang, cho dropdown dùng hết chiều rộng khả dụng
  decoration: const InputDecoration(
    labelText: 'Nạp từ ví',
    prefixIcon: Icon(Icons.account_balance_wallet_outlined),
  ),
  items: activeWallets
      .map((w) => DropdownMenuItem(
            value: w.walletId,
            child: Text(
              '${w.walletName} (${AppFormatters.currency(w.balance)})',
              overflow: TextOverflow.ellipsis, // MỚI — cắt "..." nếu vẫn còn dài
              maxLines: 1,
            ),
          ))
      .toList(),
  onChanged: (v) => setDialogState(() => selectedWalletId = v),
),
```

### 3.2. Thêm UI nút "Rút tiền" trên card mục tiêu

Trong `_GoalCardState.build()`, ngay sau khối hiển thị "Đã tiết kiệm: X / Còn: Y" hiện có, thêm 1 dòng nút nhỏ — **chỉ hiện khi `goal.savedAmount > 0`**:
```dart
if (goal.savedAmount > 0) ...[
  const SizedBox(height: 6),
  Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: _withdrawFromGoal,
      icon: const Icon(Icons.undo_rounded, size: 14),
      label: const Text('Rút tiền về ví', style: TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 0),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
  ),
],
```

### 3.3. Thêm hàm `_withdrawFromGoal()` — đối xứng với `_addDeposit()`

```dart
Future<void> _withdrawFromGoal() async {
  final amountController = TextEditingController();
  String? selectedWalletId;

  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final wallets = await widget.firestoreService.streamWallets(uid).first;
  final activeWallets = wallets.where((w) => w.isActive).toList();

  if (activeWallets.isEmpty) {
    if (mounted) {
      AppSnackbar.show(context, 'Bạn chưa có ví nào để nhận lại tiền. Vui lòng tạo ví trước.', isError: true);
    }
    return;
  }

  selectedWalletId = activeWallets.first.walletId;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Rút tiền từ "${widget.goal.name}"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Đang có ${AppFormatters.currency(widget.goal.savedAmount)} trong mục tiêu này.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedWalletId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Nhận về ví',
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
              items: activeWallets
                  .map((w) => DropdownMenuItem(
                        value: w.walletId,
                        child: Text(
                          '${w.walletName} (${AppFormatters.currency(w.balance)})',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ))
                  .toList(),
              onChanged: (v) => setDialogState(() => selectedWalletId = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Số tiền rút (đ)',
                prefixIcon: Icon(Icons.remove_circle_outline),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rút'),
          ),
        ],
      ),
    ),
  );

  if (confirmed != true) return;

  final withdrawAmount = AppFormatters.parseCurrencyInput(amountController.text);
  if (withdrawAmount <= 0 || selectedWalletId == null) {
    if (mounted) {
      AppSnackbar.show(context, 'Vui lòng nhập số tiền hợp lệ', isError: true);
    }
    return;
  }

  // Không cho rút nhiều hơn số tiền hiện đang có trong mục tiêu
  if (withdrawAmount > widget.goal.savedAmount) {
    if (mounted) {
      AppSnackbar.show(context, 'Số tiền rút vượt quá số tiền đã tiết kiệm trong mục tiêu này', isError: true);
    }
    return;
  }

  try {
    final newSaved = (widget.goal.savedAmount - withdrawAmount).clamp(0, widget.goal.targetAmount);
    await widget.firestoreService.updateSavingGoal(widget.goal.goalId, {'savedAmount': newSaved});
    await widget.firestoreService.adjustWalletBalance(selectedWalletId, withdrawAmount);
    if (mounted) {
      AppSnackbar.show(context, 'Đã rút ${AppFormatters.currency(withdrawAmount)} về ví');
    }
  } catch (e) {
    debugPrint('❌ Lỗi khi rút tiền mục tiêu tiết kiệm: $e');
    if (mounted) {
      AppSnackbar.show(context, 'Không thể rút tiền. Vui lòng thử lại.', isError: true);
    }
  }
}
```

**Lưu ý về `adjustWalletBalance(selectedWalletId, withdrawAmount)`:** dùng dấu **dương** (khác với lúc Nạp tiền dùng dấu âm `-deposit`) — vì rút tiền là **cộng lại** vào ví, đúng chiều ngược lại của nạp tiền.

## 4. Không đổi (Out of scope)

- Không tạo document trong `transactions` cho Nạp/Rút (xem lý do kỹ thuật ở mục 2).
- Không thêm field `walletId` cố định vào `SavingGoal` model để "nhớ" tiền đã nạp từ ví nào — giữ đúng thiết kế đơn giản đã thống nhất: rút tiền có thể chọn **bất kỳ ví nào** để nhận lại, không bắt buộc đúng ví đã dùng để nạp trước đó (tương tự cách tiền mặt hoạt động thật ngoài đời — không cần theo dõi "đồng tiền này tới từ đâu").
- Không đổi `_addDeposit()` (Ticket 034) ngoài việc sửa lỗi UI ở mục 3.1.
- Không đổi model `SavingGoal`, không đổi `FirestoreService`.

## 5. Acceptance Criteria

- [ ] Dropdown "Nạp từ ví" không còn hiện lỗi tràn chữ/overflow với tên ví dài (VD "ZaloPay (0 VNĐ)"), chữ dài tự động bị cắt "..." nếu cần.
- [ ] Mục tiêu có `savedAmount == 0` → **không hiện** nút "Rút tiền về ví" (không có gì để rút).
- [ ] Mục tiêu có `savedAmount > 0` → hiện đúng nút "Rút tiền về ví", bấm vào mở dialog chọn ví nhận + nhập số tiền.
- [ ] Rút số tiền **lớn hơn** `savedAmount` hiện có → báo lỗi rõ ràng, không cho rút.
- [ ] Rút hợp lệ (VD rút 500.000đ từ mục tiêu đang có 800.000đ, chọn nhận về Ví A) → `savedAmount` giảm đúng còn 300.000đ, **số dư Ví A tăng đúng** 500.000đ — kiểm tra lại ở Dashboard xác nhận tổng tài sản không đổi (chỉ chuyển trạng thái từ "trong mục tiêu" sang "trong ví").
- [ ] Rút hết toàn bộ `savedAmount` → mục tiêu về lại 0%, nút "Rút tiền về ví" tự động ẩn đi (đúng điều kiện `savedAmount > 0`).
- [ ] Test chu trình đầy đủ: Nạp 1 triệu → Rút 400 nghìn → Nạp thêm 200 nghìn → xác nhận `savedAmount` cuối cùng và số dư ví ở mỗi bước đều khớp đúng phép tính cộng trừ thủ công.
- [ ] `flutter analyze` không phát sinh lỗi/warning mới.
