# TICKET 034 — Sửa lỗi logic "Nạp tiền" mục tiêu tiết kiệm: hiện chỉ cộng số ảo, chưa trừ tiền thật từ ví

**Loại:** Bug fix (lỗ hổng logic nghiệp vụ — không phải crash, nhưng sai bản chất dữ liệu)
**Độ ưu tiên:** Cao (Nhóm 2 — rủi ro trung bình, giá trị sửa cao vì đây là điểm dễ bị hỏi khi bảo vệ: "tiền tiết kiệm này lấy từ đâu ra?")
**File bị ảnh hưởng:** `lib/screens/management/saving_goal_screen.dart`

---

## 1. Context (Bối cảnh)

Đã rà soát lại đúng code thật đang chạy (`_addDeposit()` trong `_GoalCardState`) và xác nhận: chức năng "Nạp tiền" vào 1 mục tiêu tiết kiệm hiện tại **chỉ mở dialog hỏi số tiền, không có bước chọn ví**, và khi xác nhận chỉ thực hiện đúng 1 việc:

```dart
final newSaved = (widget.goal.savedAmount + deposit).clamp(0, widget.goal.targetAmount);
await widget.firestoreService.updateSavingGoal(
  widget.goal.goalId,
  {'savedAmount': newSaved},
);
```

Nghĩa là số tiền "đã tiết kiệm" hiển thị trên mục tiêu chỉ là **con số người dùng tự gõ vào, không hề được trừ ra khỏi bất kỳ ví nào thật sự**. Về bản chất, tính năng này hiện đang cho phép tạo ra tiền "từ không khí" — người dùng có thể bấm nạp 100 triệu vào mục tiêu dù tổng tài sản trong app chỉ có 1 triệu, mà không có cảnh báo hay ràng buộc nào.

Đây là lỗ hổng logic nghiêm trọng về mặt ý nghĩa nghiệp vụ của 1 ứng dụng quản lý tài chính — rất dễ bị giảng viên hỏi xoáy khi demo tính năng này ("Số tiền tiết kiệm 8 triệu đó lấy từ ví nào, sao tổng tài sản không đổi?").

## 2. Root Cause (Nguyên nhân gốc)

Thiếu bước liên kết giữa hành động "Nạp tiền" (ghi nhận tiến độ mục tiêu) và "trừ tiền" (giảm số dư 1 ví thật) — 2 việc này về bản chất phải luôn đi cùng nhau, giống hệt cách app đã xử lý đúng cho giao dịch `expense` (luôn trừ ví khi ghi nhận chi tiêu). Khi viết tính năng "Nạp tiền" ban đầu, chỉ implement phần cập nhật `savedAmount`, bỏ sót phần trừ ví.

## 3. Fix Requirements

### 3.1. Sửa `_addDeposit()` — thêm bước chọn ví + validate số dư + trừ ví khi xác nhận

Thay toàn bộ thân hàm hiện tại bằng:

```dart
Future<void> _addDeposit() async {
  final amountController = TextEditingController();
  String? selectedWalletId;

  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final wallets = await widget.firestoreService.streamWallets(uid).first;
  final activeWallets = wallets.where((w) => w.isActive).toList();

  if (activeWallets.isEmpty) {
    if (mounted) {
      AppSnackbar.show(context, 'Bạn chưa có ví nào để nạp tiền. Vui lòng tạo ví trước.', isError: true);
    }
    return;
  }

  selectedWalletId = activeWallets.first.walletId;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Nạp tiền vào "${widget.goal.name}"'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: selectedWalletId,
              decoration: const InputDecoration(
                labelText: 'Nạp từ ví',
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
              items: activeWallets
                  .map((w) => DropdownMenuItem(
                        value: w.walletId,
                        child: Text('${w.walletName} (${AppFormatters.currency(w.balance)})'),
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
                labelText: 'Số tiền nạp (đ)',
                prefixIcon: Icon(Icons.add_circle_outline),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Nạp'),
          ),
        ],
      ),
    ),
  );

  if (confirmed != true) return;

  final deposit = AppFormatters.parseCurrencyInput(amountController.text);
  if (deposit <= 0 || selectedWalletId == null) {
    if (mounted) {
      AppSnackbar.show(context, 'Vui lòng nhập số tiền hợp lệ', isError: true);
    }
    return;
  }

  final wallet = activeWallets.firstWhere((w) => w.walletId == selectedWalletId);
  if (deposit > wallet.balance) {
    if (mounted) {
      AppSnackbar.show(context, 'Số tiền vượt quá số dư ví đã chọn', isError: true);
    }
    return;
  }

  try {
    final newSaved = (widget.goal.savedAmount + deposit).clamp(0, widget.goal.targetAmount);
    await widget.firestoreService.updateSavingGoal(widget.goal.goalId, {'savedAmount': newSaved});
    await widget.firestoreService.adjustWalletBalance(selectedWalletId, -deposit);
    if (mounted) {
      AppSnackbar.show(context, 'Đã nạp ${AppFormatters.currency(deposit)} vào mục tiêu');
    }
  } catch (e) {
    debugPrint('❌ Lỗi khi nạp tiền mục tiêu tiết kiệm: $e');
    if (mounted) {
      AppSnackbar.show(context, 'Không thể nạp tiền. Vui lòng thử lại.', isError: true);
    }
  }
}
```

**Lưu ý về `.clamp()` trên số tiền tiết kiệm:** nếu `deposit` khiến `savedAmount` vượt `targetAmount`, phần dư sẽ bị "mất" khỏi `savedAmount` (bị giới hạn đúng bằng `targetAmount`) nhưng **toàn bộ `deposit` vẫn bị trừ khỏi ví** — đây là hành vi có chủ đích kế thừa từ code cũ (không đổi), nhưng cần lưu ý khi demo: nạp dư có thể khiến người dùng thắc mắc "tiền nạp dư đi đâu". Nếu muốn xử lý chặt hơn, có thể cân nhắc ở ticket khác (ngoài phạm vi bug fix này) giới hạn `amountController` chỉ cho nhập tối đa đúng phần còn thiếu của mục tiêu.

### 3.2. Import cần thêm (nếu chưa có sẵn trong file)

Đảm bảo đầu file đã có:
```dart
import '../../utils/formatters.dart';
import '../../widgets/app_snackbar.dart';
```
(2 import này nhiều khả năng đã có sẵn trong file do dùng chung style với các màn khác — kiểm tra trước khi thêm để tránh trùng lặp import.)

### 3.3. Không cần thêm hàm mới ở `FirestoreService`

`adjustWalletBalance(walletId, delta)` đã tồn tại sẵn và đúng cơ chế (`FieldValue.increment`) — dùng lại trực tiếp, không viết hàm mới.

## 4. Không đổi (Out of scope)

- Không đổi `SavingGoal` model, không thêm field liên kết `walletId` vào mục tiêu tiết kiệm (1 mục tiêu vẫn có thể được nạp từ nhiều ví khác nhau qua nhiều lần, không cố định 1 ví duy nhất).
- Không tạo thêm 1 `AppTransaction` để ghi nhận việc nạp tiền vào lịch sử giao dịch (cân nhắc là ý tưởng hay nhưng thay đổi phạm vi lớn hơn — nên để ngỏ như 1 hướng phát triển tương lai, không làm trong ticket bug fix này).
- Không đổi phần AI Kế hoạch tiết kiệm (`_loadAiPlan`) hay giao diện card mục tiêu.
- Không đổi cách tạo mục tiêu mới (`_showGoalDialog`).

## 5. Acceptance Criteria

- [ ] Bấm "Nạp tiền" vào 1 mục tiêu → dialog hiện dropdown chọn ví (kèm số dư hiện tại của từng ví) + ô nhập số tiền.
- [ ] Không có ví nào (`isActive`) → hiện thông báo yêu cầu tạo ví trước, không mở được dialog nạp tiền.
- [ ] Nạp số tiền lớn hơn số dư ví đã chọn → báo lỗi rõ ràng, không cho nạp, không đổi dữ liệu gì.
- [ ] Nạp hợp lệ (VD 500.000đ từ Ví A đang có 2.000.000đ) → `savedAmount` của mục tiêu tăng đúng 500.000đ, đồng thời **số dư Ví A giảm đúng 500.000đ** — kiểm tra lại ở Dashboard/Wallet Management xác nhận tổng tài sản đã giảm tương ứng.
- [ ] Nạp tiền khiến mục tiêu đạt/vượt 100% → `savedAmount` giới hạn đúng bằng `targetAmount`, badge "Hoàn thành! 🎉" hiện đúng, nhưng ví vẫn bị trừ đủ số tiền đã nạp.
- [ ] Test với 2-3 ví khác nhau, nạp từ từng ví vào cùng 1 mục tiêu qua nhiều lần → tổng `savedAmount` cộng dồn đúng, mỗi ví bị trừ đúng phần đã dùng để nạp.
- [ ] `flutter analyze` không phát sinh lỗi/warning mới.
