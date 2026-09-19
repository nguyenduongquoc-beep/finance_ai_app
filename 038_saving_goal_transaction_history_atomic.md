# TICKET 038 — Nâng cấp Nạp/Rút tiền mục tiêu tiết kiệm thành giao dịch có lịch sử đầy đủ (hiện trong Transaction List), xử lý atomic

**Loại:** Cải tiến kiến trúc (thay thế 1 phần quyết định của Ticket 037) — giải quyết vấn đề minh bạch dòng tiền
**Độ ưu tiên:** Cao — khắc phục lỗ hổng UX nghiêm trọng: người dùng không thể truy vết được tiền đã nạp/rút khỏi mục tiêu tiết kiệm đi đâu nếu không vào đúng màn Mục tiêu
**File bị ảnh hưởng:** `lib/models/transaction_model.dart`, `lib/services/firestore_service.dart`, `lib/screens/management/saving_goal_screen.dart`, `lib/widgets/transaction_card.dart`, `lib/screens/home/transaction_detail_screen.dart`

---

## 1. Context (Bối cảnh)

Ticket 037 (mục 2) đã chủ động quyết định **không** ghi Nạp/Rút mục tiêu tiết kiệm vào collection `transactions`, với lý do: loại giao dịch `transfer` hiện tại bắt buộc `toWalletId` phải trỏ tới 1 document **có thật** trong `wallets`, mà "mục tiêu tiết kiệm" không phải là 1 ví.

**Vấn đề phát sinh sau khi dùng thử thực tế:** vì không có bất kỳ bản ghi nào trong Lịch sử giao dịch, người dùng **không có cách nào tra cứu lại** được: "Hôm qua tiền còn bao nhiêu, sao hôm nay ví lại ít hơn — tiền đó đi đâu?" — trừ khi họ nhớ ra và tự vào đúng màn Mục tiêu tiết kiệm mới thấy được. Đây là lỗ hổng minh bạch dữ liệu nghiêm trọng đối với 1 ứng dụng quản lý tài chính cá nhân — vi phạm chính nguyên tắc cốt lõi của app: mọi biến động số dư ví phải có thể truy vết được qua Lịch sử giao dịch.

**Quyết định sửa lại:** thay vì né tránh giới hạn kỹ thuật cũ, ticket này **mở rộng mô hình dữ liệu** để hỗ trợ đúng nhu cầu — thêm 2 loại giao dịch mới `goal_deposit`/`goal_withdraw`, cho phép "mục tiêu tiết kiệm" trở thành 1 điểm đến/nguồn hợp lệ trong `transactions`, đồng thời tận dụng cơ hội này để làm cho thao tác Nạp/Rút **atomic thật sự** (hiện tại Ticket 034/037 gọi 2 lệnh ghi Firestore tách rời — `updateSavingGoal()` và `adjustWalletBalance()` — không đảm bảo cả 2 cùng thành công hoặc cùng thất bại, giống đúng vấn đề đã từng được sửa cho giao dịch thường ở Ticket 010).

## 2. Fix Requirements

### 2.1. `lib/models/transaction_model.dart` — mở rộng model

Thêm field mới `goalId` (nullable), mở rộng ý nghĩa của `type`:

```dart
class AppTransaction {
  final String transactionId;
  final String userId;
  final String walletId; // Với goal_deposit/goal_withdraw: ví liên quan (bị trừ/được cộng)
  final String categoryId; // Không áp dụng cho transfer/goal_deposit/goal_withdraw — để rỗng ''
  final double amount;
  final String type; // income | expense | transfer | goal_deposit | goal_withdraw
  final String? toWalletId; // Chỉ dùng khi type == 'transfer'
  final String? goalId; // MỚI — chỉ dùng khi type == 'goal_deposit' hoặc 'goal_withdraw'
  final String? note;
  final String? image;
  final String? location;
  final DateTime date;

  AppTransaction({
    required this.transactionId,
    required this.userId,
    required this.walletId,
    required this.categoryId,
    required this.amount,
    required this.type,
    this.toWalletId,
    this.goalId, // MỚI
    this.note,
    this.image,
    this.location,
    required this.date,
  });

  factory AppTransaction.fromMap(Map<String, dynamic> map, String id) {
    return AppTransaction(
      transactionId: id,
      userId: map['userId'] ?? '',
      walletId: map['walletId'] ?? '',
      categoryId: map['categoryId'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      type: map['type'] ?? 'expense',
      toWalletId: map['toWalletId'],
      goalId: map['goalId'], // MỚI
      note: map['note'],
      image: map['image'],
      location: map['location'],
      date: map['date'] != null ? DateTime.parse(map['date']) : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'walletId': walletId,
      'categoryId': categoryId,
      'amount': amount,
      'type': type,
      'toWalletId': toWalletId,
      'goalId': goalId, // MỚI
      'note': note,
      'image': image,
      'location': location,
      'date': date.toIso8601String(),
    };
  }
}
```
Tương thích ngược: document cũ chưa có field `goalId` → `fromMap` trả về `null` an toàn (không throw lỗi).

### 2.2. `lib/services/firestore_service.dart` — mở rộng `createTransaction()` xử lý atomic cho 2 loại mới

Thêm đoạn chuẩn bị `goalRef` **trước** khối `runTransaction` (song song với đoạn chuẩn bị `budgetRef`/`toWalletRef` đã có):
```dart
DocumentReference? goalRef;
if (tx.type == 'goal_deposit' || tx.type == 'goal_withdraw') {
  if (tx.goalId == null || tx.goalId!.isEmpty) {
    throw Exception('Giao dịch mục tiêu tiết kiệm cần chỉ định mục tiêu');
  }
  goalRef = _db.collection('savingGoals').doc(tx.goalId);
}
```

Trong khối `await _db.runTransaction((transaction) async { ... })`, thêm đọc `goalSnap` **cùng chỗ** với các lượt đọc khác (bắt buộc mọi `.get()` phải nằm trước mọi `.set()`/`.update()` trong Firestore transaction):
```dart
DocumentSnapshot? goalSnap;
if (goalRef != null) {
  goalSnap = await transaction.get(goalRef);
  if (!goalSnap.exists) throw Exception('Mục tiêu tiết kiệm không tồn tại');
}
```

Mở rộng khối `switch (tx.type)` thêm 2 case mới:
```dart
case 'goal_deposit':
  final goalData = goalSnap!.data() as Map<String, dynamic>;
  final currentSaved = (goalData['savedAmount'] as num? ?? 0).toDouble();
  final targetAmount = (goalData['targetAmount'] as num? ?? 0).toDouble();
  final walletData = walletSnap.data() as Map<String, dynamic>;
  final currentBalance = (walletData['balance'] as num? ?? 0).toDouble();
  if (tx.amount > currentBalance) {
    throw Exception('Số dư ví không đủ để nạp vào mục tiêu');
  }
  transaction.update(walletRef, {'balance': FieldValue.increment(-tx.amount)});
  transaction.update(goalRef!, {
    'savedAmount': (currentSaved + tx.amount).clamp(0, targetAmount),
  });
  break;
case 'goal_withdraw':
  final goalDataW = goalSnap!.data() as Map<String, dynamic>;
  final currentSavedW = (goalDataW['savedAmount'] as num? ?? 0).toDouble();
  if (tx.amount > currentSavedW) {
    throw Exception('Số tiền rút vượt quá số tiền đã tiết kiệm trong mục tiêu');
  }
  transaction.update(walletRef, {'balance': FieldValue.increment(tx.amount)});
  transaction.update(goalRef!, {
    'savedAmount': currentSavedW - tx.amount,
  });
  break;
```
**Lưu ý quan trọng:** validate số dư đủ/không vượt được thực hiện **bên trong** Firestore Transaction (đọc dữ liệu mới nhất tại thời điểm commit), không chỉ validate phía client trước đó — đảm bảo đúng ngay cả khi có 2 thao tác xảy ra gần như đồng thời (race condition), nhất quán với nguyên tắc atomic đã áp dụng cho toàn bộ `createTransaction()`.

### 2.3. Mở rộng `deleteTransaction()` — hoàn tác đúng cho 2 loại mới

Thêm 2 case vào khối `switch (tx.type)` hiện có:
```dart
case 'goal_deposit':
  await adjustWalletBalance(tx.walletId, tx.amount); // hoàn lại tiền cho ví
  if (tx.goalId != null) {
    final goalDoc = await _db.collection('savingGoals').doc(tx.goalId).get();
    if (goalDoc.exists) {
      final saved = (goalDoc.data()!['savedAmount'] as num? ?? 0).toDouble();
      await _db.collection('savingGoals').doc(tx.goalId).update({
        'savedAmount': (saved - tx.amount).clamp(0, double.infinity),
      });
    }
  }
  break;
case 'goal_withdraw':
  await adjustWalletBalance(tx.walletId, -tx.amount); // hoàn lại tiền cho mục tiêu
  if (tx.goalId != null) {
    final goalDoc = await _db.collection('savingGoals').doc(tx.goalId).get();
    if (goalDoc.exists) {
      final saved = (goalDoc.data()!['savedAmount'] as num? ?? 0).toDouble();
      final target = (goalDoc.data()!['targetAmount'] as num? ?? 0).toDouble();
      await _db.collection('savingGoals').doc(tx.goalId).update({
        'savedAmount': (saved + tx.amount).clamp(0, target),
      });
    }
  }
  break;
```

### 2.4. `lib/screens/management/saving_goal_screen.dart` — đổi `_addDeposit()`/`_withdrawFromGoal()` sang gọi `createTransaction()`

Thay toàn bộ đoạn xác nhận cuối của **cả 2 hàm** (đã viết ở Ticket 034/037) từ gọi trực tiếp `updateSavingGoal()` + `adjustWalletBalance()` sang gọi đúng 1 lệnh atomic:

**Trong `_addDeposit()`, thay đoạn xác nhận:**
```dart
try {
  final tx = AppTransaction(
    transactionId: '',
    userId: uid,
    walletId: selectedWalletId,
    categoryId: '',
    amount: deposit,
    type: 'goal_deposit',
    goalId: widget.goal.goalId,
    note: 'Nạp vào mục tiêu tiết kiệm: ${widget.goal.name}',
    date: DateTime.now(),
  );
  await widget.firestoreService.createTransaction(tx);
  if (mounted) {
    AppSnackbar.show(context, 'Đã nạp ${AppFormatters.currency(deposit)} vào mục tiêu');
  }
} catch (e) {
  debugPrint('❌ Lỗi khi nạp tiền mục tiêu tiết kiệm: $e');
  if (mounted) {
    AppSnackbar.show(context, 'Không thể nạp tiền. Vui lòng thử lại.', isError: true);
  }
}
```

**Trong `_withdrawFromGoal()`, thay đoạn xác nhận tương tự:**
```dart
try {
  final tx = AppTransaction(
    transactionId: '',
    userId: uid,
    walletId: selectedWalletId,
    categoryId: '',
    amount: withdrawAmount,
    type: 'goal_withdraw',
    goalId: widget.goal.goalId,
    note: 'Rút từ mục tiêu tiết kiệm: ${widget.goal.name}',
    date: DateTime.now(),
  );
  await widget.firestoreService.createTransaction(tx);
  if (mounted) {
    AppSnackbar.show(context, 'Đã rút ${AppFormatters.currency(withdrawAmount)} về ví');
  }
} catch (e) {
  debugPrint('❌ Lỗi khi rút tiền mục tiêu tiết kiệm: $e');
  if (mounted) {
    AppSnackbar.show(context, 'Không thể rút tiền. Vui lòng thử lại.', isError: true);
  }
}
```
**Bỏ hẳn** các bước validate số dư thủ công ở tầng UI trước đó (đã chuyển vào bên trong `createTransaction()` ở mục 2.2, tránh trùng lặp logic 2 nơi) — chỉ giữ lại validate cơ bản: số tiền >0, đã chọn ví.

### 2.5. `lib/widgets/transaction_card.dart` — hiển thị đúng 2 loại mới trong danh sách

Mở rộng logic phân loại hiện có (`isTransfer`/`isIncome`) thêm nhánh riêng:
```dart
final isGoalDeposit = transaction.type == 'goal_deposit';
final isGoalWithdraw = transaction.type == 'goal_withdraw';
final isTransfer = transaction.type == 'transfer' || isGoalDeposit || isGoalWithdraw;
final isIncome = transaction.type == 'income';
final color = isTransfer
    ? AppColors.textSecondary
    : (isIncome ? AppColors.income : AppColors.expense);

final categoryLabel = isGoalDeposit
    ? 'Nạp mục tiêu tiết kiệm'
    : isGoalWithdraw
        ? 'Rút mục tiêu tiết kiệm'
        : isTransfer
            ? 'Chuyển tiền'
            : (category?.name ?? 'Không rõ danh mục');
```
Icon leading: dùng `Icons.savings_outlined` cho cả `goal_deposit`/`goal_withdraw` (thay vì `Icons.swap_horiz` của transfer thường), màu vẫn theo `AppColors.textSecondary` — trung tính như transfer, không dùng +/- đỏ/xanh (đúng bản chất: đây là chuyển tiền nội bộ, không phải thu/chi thật).

### 2.6. `lib/screens/home/transaction_detail_screen.dart` — hiển thị chi tiết đúng cho 2 loại mới

Mở rộng `_loadDetails()` (đã được tối ưu song song hóa ở Ticket 036) — thêm đọc tên mục tiêu khi cần:
```dart
Future<Map<String, dynamic>> _loadDetails() async {
  final isTransfer = transaction.type == 'transfer' &&
      transaction.toWalletId != null && transaction.toWalletId!.isNotEmpty;
  final isGoalTx = (transaction.type == 'goal_deposit' || transaction.type == 'goal_withdraw') &&
      transaction.goalId != null && transaction.goalId!.isNotEmpty;

  final results = await Future.wait([
    FirebaseFirestore.instance.collection('wallets').doc(transaction.walletId).get(),
    FirebaseFirestore.instance.collection('categories').doc(transaction.categoryId).get(),
    if (isTransfer)
      FirebaseFirestore.instance.collection('wallets').doc(transaction.toWalletId).get(),
    if (isGoalTx)
      FirebaseFirestore.instance.collection('savingGoals').doc(transaction.goalId).get(),
  ]);

  final walletDoc = results[0];
  final categoryDoc = results[1];
  final toWalletDoc = isTransfer ? results[2] : null;
  final goalDoc = isGoalTx ? results[isTransfer ? 3 : 2] : null;

  return {
    'walletName': walletDoc.exists ? (walletDoc.data()?['walletName'] ?? 'Không rõ') : 'Không rõ',
    'categoryName': categoryDoc.exists ? (categoryDoc.data()?['name'] ?? 'Không rõ') : 'Không rõ',
    'categoryColor': categoryDoc.exists ? (categoryDoc.data()?['color'] as int?) : null,
    'categoryIcon': categoryDoc.exists ? (categoryDoc.data()?['icon'] as String?) : null,
    'toWalletName': toWalletDoc != null
        ? (toWalletDoc.exists ? (toWalletDoc.data()?['walletName'] ?? 'Không rõ') : 'Không rõ')
        : null,
    'goalName': goalDoc != null
        ? (goalDoc.exists ? (goalDoc.data()?['name'] ?? 'Không rõ') : 'Không rõ')
        : null,
  };
}
```

Trong phần `build()`, thêm điều kiện hiển thị riêng cho `goal_deposit`/`goal_withdraw`:
- Tiêu đề số tiền: `"Số tiền đã nạp"` (goal_deposit) / `"Số tiền đã rút"` (goal_withdraw), thay cho "đã thu/đã chi".
- Badge loại giao dịch: `"Nạp tiết kiệm"` / `"Rút tiết kiệm"`.
- Trong card thông tin: ẩn dòng "Danh mục", hiện dòng **"Ví"** (walletName) và dòng **"Mục tiêu tiết kiệm"** (`goalName`) thay cho "Từ ví"/"Đến ví".
- **Ẩn nút "Sửa"** (chỉ hiện nút "Xóa") cho 2 loại này — vì `Add Transaction Screen` chưa hỗ trợ chỉnh sửa `goal_deposit`/`goal_withdraw` (ngoài phạm vi ticket này, xem mục 3). Nội dung dialog xác nhận xóa cần nêu rõ: *"Xóa giao dịch này sẽ hoàn tác cả số dư ví lẫn tiến độ mục tiêu tiết kiệm liên quan."*

### 2.7. Xác nhận rõ: KHÔNG hiện trong biểu đồ Thu/Chi — vì sao đây là chủ đích đúng, không phải thiếu sót

Giao dịch `goal_deposit`/`goal_withdraw` **chủ động bị loại trừ** khỏi mọi biểu đồ và phép tính liên quan tới Thu nhập/Chi tiêu — biểu đồ cột 6 tháng ở Dashboard, biểu đồ tròn danh mục, biểu đồ xu hướng ở AI Report, Điểm sức khỏe tài chính/danh sách vấn đề ở AI Insight, cảnh báo Ngân sách, ngữ cảnh gửi cho AI Chat. **Không cần sửa gì thêm** ở các nơi này — vì toàn bộ đều lọc theo đúng chuỗi `t.type == 'expense'`/`t.type == 'income'`, tự động không khớp với 2 giá trị `type` mới, giống hệt cách `transfer` đã được loại trừ tự nhiên từ Ticket 026.

**Lý do bắt buộc phải loại trừ:** đây là chuyển khoản nội bộ (tiền chuyển từ ví sang "kho tiết kiệm" của chính người dùng, không hề rời khỏi tổng tài sản) — nếu tính vào Chi tiêu sẽ làm sai lệch nghiêm trọng: Điểm sức khỏe tài chính bị trừ oan, cảnh báo vượt ngân sách bị kích hoạt sai, AI phân tích thói quen chi tiêu đưa ra nhận định sai sự thật (tưởng người dùng đang tiêu nhiều hơn thực tế). Đây là nguyên tắc kế toán cơ bản, áp dụng nhất quán cho mọi hình thức chuyển khoản nội bộ trong app.

### 2.8. (Tùy chọn — bổ sung nếu muốn có nơi trực quan hóa riêng) Thêm chỉ số "Tổng đang tiết kiệm" tách biệt khỏi biểu đồ Thu/Chi

Nếu muốn có cách xem nhanh **tổng số tiền đang "khóa" trong tất cả mục tiêu tiết kiệm** mà không cần vào từng card riêng lẻ, có thể thêm 1 chỉ số **hoàn toàn tách biệt** khỏi biểu đồ Thu/Chi — không trộn chung, để không gây hiểu nhầm là số liệu chi tiêu:

**Vị trí đề xuất:** đầu `Saving Goal Screen`, phía trên danh sách các mục tiêu — thêm 1 card nhỏ:
```dart
Widget _buildTotalSavedCard(List<SavingGoal> goals) {
  final totalSaved = goals.fold<double>(0, (a, g) => a + g.savedAmount);
  if (totalSaved <= 0) return const SizedBox.shrink();
  return Container(
    margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.aiAccent.withOpacity(0.08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.aiAccent.withOpacity(0.2)),
    ),
    child: Row(
      children: [
        const Icon(Icons.savings_rounded, color: AppColors.aiAccent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tổng đang tiết kiệm', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              Text(AppFormatters.currency(totalSaved),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.aiAccent)),
            ],
          ),
        ),
      ],
    ),
  );
}
```
Gọi hàm này ngay trên `ListView.builder` hiện có trong `build()` (dùng `Column` bọc ngoài nếu cần), truyền vào danh sách `goals` đã có sẵn từ `StreamBuilder<List<SavingGoal>>`.

**Không thêm** chỉ số này vào Dashboard chính (Home Dashboard Screen) trong phạm vi ticket này — giữ đúng phạm vi tối thiểu, tránh làm phình quá nhiều nơi cùng lúc; đây là bổ sung **tùy chọn**, có thể bỏ qua nếu không cần thiết cho báo cáo.

## 3. Không đổi (Out of scope)

- Không thêm hỗ trợ **Sửa** giao dịch `goal_deposit`/`goal_withdraw` qua `Add Transaction Screen` — chỉ hỗ trợ Xóa (hoàn tác đầy đủ) hoặc tạo mới qua đúng luồng ở màn Mục tiêu tiết kiệm. Nếu cần sửa, người dùng xóa rồi tạo lại.
- Không đổi `TransactionListScreen._typeFilter` — giao dịch `goal_deposit`/`goal_withdraw` vẫn chỉ hiện ở tag "Tất cả" (không khớp "Thu nhập"/"Chi tiêu"), nhất quán với cách `transfer` đã hoạt động.
- Không đổi `updateTransactionSafely()` để hỗ trợ 2 loại mới — vì đã quyết định không cho Sửa (mục trên).
- **Không** thêm `goal_deposit`/`goal_withdraw` vào bất kỳ biểu đồ Thu/Chi nào (Dashboard, AI Report, AI Insight) — đây là quyết định kiến trúc có chủ đích (xem lý do ở mục 2.7), không phải phạm vi còn thiếu.
- Nếu chọn làm mục 2.8 (tùy chọn): không thêm chỉ số "Tổng đang tiết kiệm" vào Home Dashboard Screen — chỉ thêm ở Saving Goal Screen.

## 4. Acceptance Criteria

- [ ] Nạp tiền vào 1 mục tiêu → giao dịch mới **xuất hiện ngay** trong Transaction List (tag "Tất cả"), ghi đúng "Nạp mục tiêu tiết kiệm", đúng số tiền, đúng ngày.
- [ ] Bấm vào giao dịch nạp mục tiêu vừa tạo → Transaction Detail hiện đúng: "Số tiền đã nạp", tên Ví, tên Mục tiêu tiết kiệm, không hiện Danh mục, chỉ có nút "Xóa" (không có "Sửa").
- [ ] Rút tiền từ mục tiêu → tương tự, hiện đúng "Rút mục tiêu tiết kiệm" trong danh sách.
- [ ] Giao dịch `goal_deposit`/`goal_withdraw` **không** xuất hiện khi lọc tag "Thu nhập" hay "Chi tiêu", **không** ảnh hưởng tới bất kỳ số liệu Thu/Chi nào ở Dashboard, AI Report, hay Ngân sách.
- [ ] Nạp tiền vượt số dư ví hiện có → bị chặn ngay trong Firestore Transaction, không tạo giao dịch, không trừ ví, thông báo lỗi rõ ràng.
- [ ] Rút tiền vượt quá `savedAmount` hiện có của mục tiêu → bị chặn tương tự.
- [ ] Xóa 1 giao dịch "Nạp mục tiêu tiết kiệm" ở Transaction Detail → xác nhận: ví được hoàn lại đúng số tiền, `savedAmount` của mục tiêu giảm lại đúng số tiền đó, giao dịch biến mất khỏi Lịch sử.
- [ ] Xóa 1 giao dịch "Rút mục tiêu tiết kiệm" → hoàn tác đúng chiều ngược lại.
- [ ] Test chu trình đầy đủ: Nạp 1 triệu → kiểm tra Lịch sử có đúng 1 dòng → Rút 400 nghìn → kiểm tra Lịch sử có đúng 2 dòng, số dư ví và `savedAmount` khớp đúng phép tính thủ công ở mọi bước.
- [ ] Test giả lập mất mạng giữa lúc nạp tiền (tắt mạng ngay sau khi bấm "Nạp") → xác nhận **hoặc** cả ví lẫn mục tiêu cùng cập nhật đúng, **hoặc** không có gì thay đổi — không còn trạng thái nửa vời (đúng nguyên tắc atomic).
- [ ] `flutter analyze` không phát sinh lỗi/warning mới.
