# TICKET 010 — Sửa lỗi ghi giao dịch không toàn vẹn (atomic write) & note field không hiện nhiều dòng

**Loại:** Bug fix (nghiêm trọng — mất tính toàn vẹn dữ liệu)
**Độ ưu tiên:** Cao nhất
**File bị ảnh hưởng:** `lib/services/firestore_service.dart`, `lib/screens/home/add_transaction_screen.dart`

---

## PHẦN A — Ghi giao dịch không atomic (nghiêm trọng nhất)

### Context
Test thực tế: tạo 2 giao dịch liên tiếp qua OCR → cả 2 đều báo lỗi "Không thể lưu giao dịch" → nhưng khi vào lịch sử vẫn thấy 1-2 giao dịch xuất hiện, biểu đồ cộng dồn không khớp số lượng giao dịch thực tế đã tạo.

### Root Cause
```dart
Future<String> createTransaction(AppTransaction tx) async {
  final ref = await _db.collection('transactions').add(tx.toMap()); // (1) ghi doc
  final delta = tx.type == 'income' ? tx.amount : -tx.amount;
  await adjustWalletBalance(tx.walletId, delta);                     // (2) cập nhật ví
  if (tx.type == 'expense') {
    final monthStr = DateFormat('MM/yyyy').format(tx.date);
    await adjustBudgetSpent(tx.categoryId, monthStr, tx.amount);     // (3) cập nhật ngân sách
  }
  return ref.id;
}
```
3 bước là 3 lệnh ghi Firestore **độc lập, tuần tự**, không nằm trong 1 transaction. Nếu (2) hoặc (3) lỗi (mất mạng giữa chừng), (1) **đã commit vĩnh viễn** — kết quả: document giao dịch tồn tại nhưng số dư ví/ngân sách sai lệch, đồng thời app báo lỗi khiến người dùng tưởng nhầm không có gì được lưu.

### Fix Requirements
Viết lại `createTransaction()` dùng `_db.runTransaction()`:
```dart
Future<String> createTransaction(AppTransaction tx) async {
  final txRef = _db.collection('transactions').doc(); // tạo ref trước, chưa ghi
  final walletRef = _db.collection('wallets').doc(tx.walletId);

  DocumentReference? budgetRef;
  final monthStr = DateFormat('MM/yyyy').format(tx.date);
  if (tx.type == 'expense') {
    final budgetQuery = await _db
        .collection('budgets')
        .where('categoryId', isEqualTo: tx.categoryId)
        .where('month', isEqualTo: monthStr)
        .limit(1)
        .get();
    if (budgetQuery.docs.isNotEmpty) {
      budgetRef = budgetQuery.docs.first.reference;
    }
  }

  await _db.runTransaction((transaction) async {
    // Đọc trước khi ghi (yêu cầu bắt buộc của Firestore transaction)
    final walletSnap = await transaction.get(walletRef);
    if (!walletSnap.exists) {
      throw Exception('Ví không tồn tại');
    }

    DocumentSnapshot? budgetSnap;
    if (budgetRef != null) {
      budgetSnap = await transaction.get(budgetRef);
    }

    // Ghi document giao dịch
    transaction.set(txRef, tx.toMap());

    // Cập nhật số dư ví
    final delta = tx.type == 'income' ? tx.amount : -tx.amount;
    final currentBalance = (walletSnap.data() as Map<String, dynamic>)['balance'] as num;
    transaction.update(walletRef, {'balance': currentBalance + delta});

    // Cập nhật ngân sách nếu có
    if (budgetRef != null && budgetSnap != null && budgetSnap.exists) {
      final currentSpent = (budgetSnap.data() as Map<String, dynamic>)['spent'] as num;
      transaction.update(budgetRef, {'spent': currentSpent + tx.amount});
    }
  });

  // Kiểm tra cảnh báo vượt ngân sách SAU KHI transaction đã commit thành công
  if (tx.type == 'expense' && budgetRef != null) {
    final updatedBudget = await budgetRef.get();
    final data = updatedBudget.data() as Map<String, dynamic>?;
    if (data != null) {
      final limit = (data['limit'] as num).toDouble();
      final spent = (data['spent'] as num).toDouble();
      if (spent > limit * 0.9 && spent - tx.amount <= limit * 0.9) {
        await createNotification(AppNotification(
          notificationId: '',
          userId: data['userId'],
          title: 'Cảnh báo ngân sách',
          content: 'Bạn đã tiêu vượt 90% ngân sách tháng $monthStr cho danh mục này.',
          status: 'unread',
          type: 'budget',
          createdAt: DateTime.now(),
        ));
      }
    }
  }

  return txRef.id;
}
```

**Nguyên tắc quan trọng:** mọi lệnh `.get()` phải nằm **trước** mọi lệnh `.set()`/`.update()` bên trong `runTransaction` (giới hạn bắt buộc của Firestore). Notification cảnh báo vượt ngân sách tách ra **ngoài** transaction (đọc lại budget sau khi commit) vì đây không phải dữ liệu cốt lõi cần atomic.

### Acceptance Criteria
- [ ] Giả lập mất mạng ngay giữa lúc lưu giao dịch → **hoặc** giao dịch được lưu đầy đủ đúng cả 3 phần (doc + số dư ví + ngân sách), **hoặc** không có gì được lưu — không còn trạng thái nửa vời.
- [ ] Tạo liên tiếp 2-3 giao dịch (kể cả qua OCR) → tất cả xuất hiện đầy đủ trong lịch sử và biểu đồ, không thiếu giao dịch nào.
- [ ] Số dư ví sau khi tạo giao dịch phải khớp chính xác với tổng các giao dịch đã tạo thành công (đối chiếu thủ công).

---

## PHẦN B — Note field không hiển thị nhiều dòng

### Root Cause
```dart
TextField(
  controller: _noteController,
  decoration: const InputDecoration(labelText: 'Ghi chú', prefixIcon: Icon(Icons.notes_outlined)),
)
```
Không set `maxLines` → mặc định `1` → dù `_noteController.text` chứa `\n` (nhiều dòng từ OCR items), UI chỉ hiện được 1 dòng.

### Fix Requirements
```dart
TextField(
  controller: _noteController,
  maxLines: null,        // cho phép mở rộng theo nội dung
  minLines: 1,            // cao tối thiểu như input thường khi chưa có nhiều nội dung
  decoration: const InputDecoration(
    labelText: 'Ghi chú',
    prefixIcon: Icon(Icons.notes_outlined),
    alignLabelWithHint: true, // căn label đúng khi field nhiều dòng
  ),
),
```

### Acceptance Criteria
- [ ] Ghi chú có nội dung nhiều dòng (từ OCR items) → hiển thị đầy đủ tất cả các dòng, ô tự giãn cao ra, không bị cắt.
- [ ] Ghi chú ngắn 1 dòng (nhập tay bình thường) → hiển thị như cũ, không bị giãn bất thường.
