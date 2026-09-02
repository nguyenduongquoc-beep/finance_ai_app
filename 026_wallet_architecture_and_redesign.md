# TICKET 026 — Kiến trúc lại Wallet (initialBalance, ẩn ví, Transfer) + Redesign màn "Ví của tôi"

**Loại:** Refactor kiến trúc (Wallet + Transaction) + UI/UX redesign
**Độ ưu tiên:** Cao (thay đổi model + logic tài chính cốt lõi — cần làm cẩn thận, đúng thứ tự Phần A → B → C)
**File bị ảnh hưởng:** `lib/models/wallet_model.dart`, `lib/models/transaction_model.dart`, `lib/services/firestore_service.dart`, `lib/screens/management/wallet_management_screen.dart`, `lib/widgets/wallet_card.dart`, `lib/screens/setup/wallet_setup_screen.dart`, `lib/screens/home/home_dashboard_screen.dart`, `lib/screens/ai/ai_chat_screen.dart`

---

## 0. Nguyên tắc kiến trúc đã chốt (đọc trước khi code)

```
WALLET   → Tôi đang có bao nhiêu tiền và tiền nằm ở đâu?
BUDGET   → Tôi được phép chi bao nhiêu cho từng loại?
TRANSACTION → Tiền thực tế đã đi đâu / đến từ đâu?
```

- Mỗi `Wallet` có `initialBalance` (số dư ban đầu, cố định khi tạo). `balance` là **giá trị cache số dư hiện tại**, luôn được đồng bộ tự động qua `Transaction` — người dùng **không được** sửa `balance` trực tiếp sau khi ví đã tồn tại (chỉ nhập lúc tạo mới, lúc đó `balance == initialBalance`).
- `Transaction` có 3 loại: `income` (+ số dư ví), `expense` (− số dư ví), **`transfer`** (MỚI — chuyển giữa 2 ví, không tính vào thu/chi/ngân sách).
- Sửa/xóa/đổi ví của 1 Transaction → phải **hoàn tác đúng ảnh hưởng cũ rồi áp dụng ảnh hưởng mới** (nguyên tắc đã áp dụng cho income/expense ở ticket 010, giờ mở rộng thêm cho transfer).
- **Không xóa cứng** ví đã có giao dịch — dùng `isActive = false` để "ẩn" thay vì xóa, giữ nguyên lịch sử giao dịch cũ.
- **Tổng tài sản** = tổng `balance` của các ví có `isActive == true`, luôn tính tự động, không cho nhập tay.
- **Không** xây thêm "hạn mức chi tiêu theo ví" — app đã có `Budget` theo danh mục, tránh trùng chức năng. Dòng "Hạn mức sử dụng %" trong bản thiết kế cũ được thay bằng **"Tỷ lệ trong tổng tài sản"** (Phương án A).

---

## PHẦN A — Cập nhật Model

### A.1. `lib/models/wallet_model.dart`

```dart
class Wallet {
  final String walletId;
  final String userId;
  final String walletName;
  final double balance;         // Số dư HIỆN TẠI — cache, đồng bộ qua Transaction
  final double initialBalance;  // MỚI — số dư ban đầu lúc tạo ví, không đổi sau đó
  final String type;            // cash | bank | eWallet | other
  final String? description;    // MỚI — optional, VD "Chi tiêu sinh hoạt"
  final String currency;        // MỚI — mặc định 'VND'
  final bool isActive;          // MỚI — mặc định true; false = đã ẩn (soft-delete)
  final DateTime createdAt;
  final DateTime? updatedAt;    // MỚI

  Wallet({
    required this.walletId,
    required this.userId,
    required this.walletName,
    required this.balance,
    double? initialBalance,
    required this.type,
    this.description,
    this.currency = 'VND',
    this.isActive = true,
    required this.createdAt,
    this.updatedAt,
  }) : initialBalance = initialBalance ?? balance;

  factory Wallet.fromMap(Map<String, dynamic> map, String id) {
    return Wallet(
      walletId: id,
      userId: map['userId'] ?? '',
      walletName: map['walletName'] ?? '',
      balance: (map['balance'] ?? 0).toDouble(),
      initialBalance: (map['initialBalance'] ?? map['balance'] ?? 0).toDouble(),
      type: map['type'] ?? 'cash',
      description: map['description'],
      currency: map['currency'] ?? 'VND',
      isActive: map['isActive'] ?? true, // ví cũ chưa có field này -> mặc định active
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null ? DateTime.parse(map['updatedAt']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'walletName': walletName,
      'balance': balance,
      'initialBalance': initialBalance,
      'type': type,
      'description': description,
      'currency': currency,
      'isActive': isActive,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  Wallet copyWith({
    String? walletName,
    double? balance,
    String? type,
    String? description,
    bool? isActive,
  }) {
    return Wallet(
      walletId: walletId,
      userId: userId,
      walletName: walletName ?? this.walletName,
      balance: balance ?? this.balance,
      initialBalance: initialBalance,
      type: type ?? this.type,
      description: description ?? this.description,
      currency: currency,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
```
**Lưu ý tương thích ngược:** ví cũ trong Firestore chưa có `initialBalance`/`isActive` → `fromMap` đã có fallback an toàn (`initialBalance` fallback về `balance`, `isActive` fallback `true`), không cần chạy script backfill.

### A.2. `lib/models/transaction_model.dart`

```dart
class AppTransaction {
  final String transactionId;
  final String userId;
  final String walletId;      // Với type='transfer': đây là VÍ NGUỒN
  final String categoryId;    // Với type='transfer': để rỗng '' (không áp dụng)
  final double amount;
  final String type;          // income | expense | transfer  <- MỚI thêm 'transfer'
  final String? toWalletId;   // MỚI — chỉ có giá trị khi type == 'transfer' (VÍ ĐÍCH)
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
      'note': note,
      'image': image,
      'location': location,
      'date': date.toIso8601String(),
    };
  }
}
```
Mọi nơi trong code đang lọc `t.type == 'income'`/`t.type == 'expense'` (Dashboard, `AiReportScreen`, `AiInsightScreen`, `FinancialAnalyticsService`, `AiChatScreen`) **tự động loại trừ** giao dịch `transfer` mà không cần sửa gì thêm — đây chính là lý do vì sao Transfer phải là 1 giá trị `type` riêng, không được ghi giả thành `income`/`expense`.

---

## PHẦN B — `lib/services/firestore_service.dart`: tổng quát hóa cho Transfer

### B.1. `createTransaction()` — thêm nhánh `transfer`, chuyển sang dùng `FieldValue.increment` nhất quán

```dart
Future<String> createTransaction(AppTransaction tx) async {
  final txRef = _db.collection('transactions').doc();
  final walletRef = _db.collection('wallets').doc(tx.walletId);
  DocumentReference? toWalletRef;

  if (tx.type == 'transfer') {
    if (tx.toWalletId == null || tx.toWalletId!.isEmpty) {
      throw Exception('Giao dịch chuyển tiền cần chỉ định ví đích');
    }
    if (tx.toWalletId == tx.walletId) {
      throw Exception('Ví nguồn và ví đích không được trùng nhau');
    }
    toWalletRef = _db.collection('wallets').doc(tx.toWalletId);
  }

  DocumentReference? budgetRef;
  final monthStr = DateFormat('MM/yyyy').format(tx.date);
  if (tx.type == 'expense') {
    final budgetQuery = await _db
        .collection('budgets')
        .where('userId', isEqualTo: tx.userId)
        .where('categoryId', isEqualTo: tx.categoryId)
        .where('month', isEqualTo: monthStr)
        .limit(1)
        .get();
    if (budgetQuery.docs.isNotEmpty) budgetRef = budgetQuery.docs.first.reference;
  }

  await _db.runTransaction((transaction) async {
    final walletSnap = await transaction.get(walletRef);
    if (!walletSnap.exists) throw Exception('Ví không tồn tại');
    if (toWalletRef != null) {
      final toWalletSnap = await transaction.get(toWalletRef);
      if (!toWalletSnap.exists) throw Exception('Ví đích không tồn tại');
    }
    DocumentSnapshot? budgetSnap;
    if (budgetRef != null) budgetSnap = await transaction.get(budgetRef);

    transaction.set(txRef, tx.toMap());

    switch (tx.type) {
      case 'income':
        transaction.update(walletRef, {'balance': FieldValue.increment(tx.amount)});
        break;
      case 'expense':
        transaction.update(walletRef, {'balance': FieldValue.increment(-tx.amount)});
        if (budgetRef != null && budgetSnap != null && budgetSnap.exists) {
          transaction.update(budgetRef, {'spent': FieldValue.increment(tx.amount)});
        }
        break;
      case 'transfer':
        transaction.update(walletRef, {'balance': FieldValue.increment(-tx.amount)});
        transaction.update(toWalletRef!, {'balance': FieldValue.increment(tx.amount)});
        break;
    }
  });

  // Cảnh báo vượt ngân sách — GIỮ NGUYÊN đúng logic cũ, chỉ chạy khi type == 'expense'
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

**Điểm quan trọng:** đổi từ cách cũ (đọc `currentBalance` rồi tự cộng/trừ rồi ghi lại) sang **`FieldValue.increment()`** cho mọi thao tác số dư ví/ngân sách. Đây là cách làm an toàn hơn (atomic ở tầng server, không phụ thuộc giá trị đọc được tại thời điểm transaction) và giúp tổng quát hóa dễ dàng cho `updateTransactionSafely()` bên dưới — tránh phải tự tính toán số dư trung gian khi có nhiều thao tác hoàn tác/áp dụng chồng lên nhau trên cùng 1 ví.

### B.2. `updateTransactionSafely()` — tổng quát hóa hoàn tác/áp dụng cho cả 3 loại

```dart
Future<void> updateTransactionSafely(AppTransaction oldTx, AppTransaction newTx) async {
  final monthStrOld = DateFormat('MM/yyyy').format(oldTx.date);
  final monthStrNew = DateFormat('MM/yyyy').format(newTx.date);

  DocumentReference? oldBudgetRef;
  if (oldTx.type == 'expense') {
    final q = await _db
        .collection('budgets')
        .where('userId', isEqualTo: oldTx.userId)
        .where('categoryId', isEqualTo: oldTx.categoryId)
        .where('month', isEqualTo: monthStrOld)
        .limit(1)
        .get();
    if (q.docs.isNotEmpty) oldBudgetRef = q.docs.first.reference;
  }
  DocumentReference? newBudgetRef;
  if (newTx.type == 'expense') {
    final q = await _db
        .collection('budgets')
        .where('userId', isEqualTo: newTx.userId)
        .where('categoryId', isEqualTo: newTx.categoryId)
        .where('month', isEqualTo: monthStrNew)
        .limit(1)
        .get();
    if (q.docs.isNotEmpty) newBudgetRef = q.docs.first.reference;
  }

  await _db.runTransaction((txn) async {
    // 1. Hoàn tác ảnh hưởng của oldTx
    switch (oldTx.type) {
      case 'expense':
        txn.update(_db.collection('wallets').doc(oldTx.walletId),
            {'balance': FieldValue.increment(oldTx.amount)});
        if (oldBudgetRef != null) {
          txn.update(oldBudgetRef, {'spent': FieldValue.increment(-oldTx.amount)});
        }
        break;
      case 'income':
        txn.update(_db.collection('wallets').doc(oldTx.walletId),
            {'balance': FieldValue.increment(-oldTx.amount)});
        break;
      case 'transfer':
        txn.update(_db.collection('wallets').doc(oldTx.walletId),
            {'balance': FieldValue.increment(oldTx.amount)});
        txn.update(_db.collection('wallets').doc(oldTx.toWalletId),
            {'balance': FieldValue.increment(-oldTx.amount)});
        break;
    }

    // 2. Áp dụng ảnh hưởng của newTx
    switch (newTx.type) {
      case 'expense':
        txn.update(_db.collection('wallets').doc(newTx.walletId),
            {'balance': FieldValue.increment(-newTx.amount)});
        if (newBudgetRef != null) {
          txn.update(newBudgetRef, {'spent': FieldValue.increment(newTx.amount)});
        }
        break;
      case 'income':
        txn.update(_db.collection('wallets').doc(newTx.walletId),
            {'balance': FieldValue.increment(newTx.amount)});
        break;
      case 'transfer':
        txn.update(_db.collection('wallets').doc(newTx.walletId),
            {'balance': FieldValue.increment(-newTx.amount)});
        txn.update(_db.collection('wallets').doc(newTx.toWalletId),
            {'balance': FieldValue.increment(newTx.amount)});
        break;
    }

    txn.update(_db.collection('transactions').doc(newTx.transactionId), newTx.toMap());
  });

  // Cảnh báo vượt ngân sách sau update — GIỮ NGUYÊN logic cũ, chỉ áp dụng khi newTx.type == 'expense'
  if (newTx.type == 'expense') {
    final updatedBudgetQuery = await _db
        .collection('budgets')
        .where('userId', isEqualTo: newTx.userId)
        .where('categoryId', isEqualTo: newTx.categoryId)
        .where('month', isEqualTo: monthStrNew)
        .limit(1)
        .get();
    if (updatedBudgetQuery.docs.isNotEmpty) {
      final doc = updatedBudgetQuery.docs.first;
      final limit = (doc.data()['limit'] as num).toDouble();
      final spent = (doc.data()['spent'] as num).toDouble();
      if (spent > limit * 0.9 && spent - newTx.amount <= limit * 0.9) {
        await createNotification(AppNotification(
          notificationId: '',
          userId: doc.data()['userId'],
          title: 'Cảnh báo ngân sách',
          content: 'Giao dịch vừa sửa đã làm bạn tiêu vượt 90% ngân sách tháng $monthStrNew cho danh mục này.',
          status: 'unread',
          type: 'budget',
          createdAt: DateTime.now(),
        ));
      }
    }
  }
}
```
Nhờ dùng `FieldValue.increment()` (cộng dồn tương đối, không phụ thuộc giá trị đọc trước), trường hợp **đổi ví của giao dịch** hoặc **oldTx/newTx cùng ảnh hưởng 1 ví** đều tự động cộng trừ đúng — không cần code riêng cho case đó.

### B.3. `deleteTransaction()` — thêm nhánh `transfer`

```dart
Future<void> deleteTransaction(AppTransaction tx) async {
  await _db.collection('transactions').doc(tx.transactionId).delete();

  switch (tx.type) {
    case 'income':
      await adjustWalletBalance(tx.walletId, -tx.amount);
      break;
    case 'expense':
      await adjustWalletBalance(tx.walletId, tx.amount);
      final monthStr = DateFormat('MM/yyyy').format(tx.date);
      await adjustBudgetSpent(tx.userId, tx.categoryId, monthStr, -tx.amount);
      break;
    case 'transfer':
      await adjustWalletBalance(tx.walletId, tx.amount);
      if (tx.toWalletId != null) {
        await adjustWalletBalance(tx.toWalletId!, -tx.amount);
      }
      break;
  }

  if (tx.image != null && tx.image!.isNotEmpty) {
    try {
      await StorageService().deleteImageByUrl(tx.image!);
    } catch (_) {}
  }
}
```

### B.4. Thêm hàm ẩn/hiện ví (soft-delete)

```dart
/// Ẩn hoặc khôi phục hiển thị 1 ví — dùng thay cho xóa cứng khi ví đã có
/// giao dịch, để giữ nguyên lịch sử giao dịch cũ (xem RULES.md nguyên tắc Wallet).
Future<void> setWalletActive(String walletId, bool isActive) {
  return _db.collection('wallets').doc(walletId).update({
    'isActive': isActive,
    'updatedAt': DateTime.now().toIso8601String(),
  });
}
```

### B.5. `streamWallets()` — **không** thêm `where('isActive', ...)` vào query

```dart
Stream<List<Wallet>> streamWallets(String userId) {
  return _db
      .collection('wallets')
      .where('userId', isEqualTo: userId)
      .snapshots()
      .map((snap) {
    final list = snap.docs.map((d) => Wallet.fromMap(d.data(), d.id)).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  });
}
```
**Giữ nguyên signature/không đổi hàm này.** Lý do quan trọng: ví cũ trong Firestore chưa có field `isActive` — nếu thêm `.where('isActive', isEqualTo: true)` vào query, Firestore sẽ loại bỏ hoàn toàn các document **thiếu field đó** (không match điều kiện tồn tại), khiến toàn bộ ví cũ biến mất khỏi danh sách dù `Wallet.fromMap` đã có fallback `isActive: true`. Việc lọc theo `isActive` phải làm **ở phía client** sau khi nhận dữ liệu (đúng pattern đã áp dụng cho lọc category theo `type` ở ticket 004): `wallets.where((w) => w.isActive).toList()`.

---

## PHẦN C — Redesign UI màn "Ví của tôi" (`wallet_management_screen.dart`, `wallet_card.dart`)

### C.1. AppBar

Đổi tiêu đề từ **"Quản lý ví"** → **"Ví của tôi"**.

### C.2. Tính toán hiển thị (Dart thuần)

```dart
final activeWallets = wallets.where((w) => w.isActive).toList();
final totalAssets = activeWallets.fold<double>(0, (a, w) => a + w.balance);
```
`shareOfTotal` cho từng ví: `totalAssets == 0 ? 0.0 : (wallet.balance / totalAssets).clamp(0.0, 1.0)`.

Danh sách hiển thị trong `ListView` chỉ gồm `activeWallets` (ví đã ẩn không hiện trong danh sách chính — xem mục C.5 để xem lại ví đã ẩn).

### C.3. Card "TỔNG TÀI SẢN" (nền trắng, không phải nền tối như Budget/AI Report)

```dart
Container(
  margin: const EdgeInsets.fromLTRB(20, 16, 20, 20),
  padding: const EdgeInsets.all(20),
  decoration: BoxDecoration(
    color: AppColors.card,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Colors.grey.shade200),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('TỔNG TÀI SẢN',
          style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold,
              fontSize: 12, letterSpacing: 0.5)),
      const SizedBox(height: 8),
      Text(AppFormatters.currency(totalAssets),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
    ],
  ),
)
```

### C.4. Redesign `WalletCard` (`lib/widgets/wallet_card.dart`)

Thêm tham số `double shareOfTotal` (bắt buộc) vào constructor. Đổi màu icon theo `type` (thay vì luôn `AppColors.primary`):

```dart
Color _typeColor(String type) {
  switch (type) {
    case 'cash':
      return AppColors.income; // xanh lá
    case 'bank':
      return Colors.blueAccent; // TODO: chuẩn hóa theo AppColors khi có bảng màu chính thức
    case 'eWallet':
      return Colors.pinkAccent; // TODO: chuẩn hóa theo AppColors khi có bảng màu chính thức
    default:
      return AppColors.textSecondary;
  }
}
```

Bố cục card mới:
```dart
Container(
  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: AppColors.card,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: Colors.grey.shade200),
  ),
  child: InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _typeColor(wallet.type).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_icon, color: _typeColor(wallet.type)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(wallet.walletName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  if (wallet.description != null && wallet.description!.isNotEmpty)
                    Text(wallet.description!,
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Text(AppFormatters.currency(wallet.balance),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: shareOfTotal,
            minHeight: 6,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(_typeColor(wallet.type)),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Tỷ lệ trong tổng tài sản',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            Text('${(shareOfTotal * 100).round()}%',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ],
    ),
  ),
)
```
**Xóa hoàn toàn** khái niệm "Hạn mức sử dụng" khỏi widget này — không dùng `LinearPercentIndicator` gắn với `percentUsed` như Budget (vì Wallet không có hạn mức chi tiêu riêng), chỉ dùng `LinearProgressIndicator` biểu diễn tỷ trọng `shareOfTotal`.

### C.5. Xử lý xóa/ẩn ví (`confirmDismiss` trong `wallet_management_screen.dart`)

Giữ nguyên luồng hiện có khi ví **không** có giao dịch (`checkWalletInUse == false`) → xóa thẳng như cũ. Khi ví **đang có giao dịch** (`checkWalletInUse == true`), đổi dialog để cung cấp **2 lựa chọn** thay vì chỉ 1:

```dart
final action = await showDialog<String>( // 'hide' | 'reassign' | null (hủy)
  context: context,
  builder: (ctx) => AlertDialog(
    title: const Text('Ví đang được sử dụng'),
    content: const Text(
      'Ví này đang có giao dịch liên kết. Bạn có thể ẨN ví (giữ nguyên lịch sử giao dịch cũ, '
      'không hiện ví này khi tạo giao dịch mới) hoặc CHUYỂN toàn bộ giao dịch sang ví khác rồi xóa hẳn.',
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Hủy')),
      TextButton(onPressed: () => Navigator.pop(ctx, 'hide'), child: const Text('Ẩn ví')),
      TextButton(
        onPressed: () => Navigator.pop(ctx, 'reassign'),
        child: const Text('Chuyển & Xóa', style: TextStyle(color: AppColors.expense)),
      ),
    ],
  ),
);

if (action == 'hide') {
  await firestoreService.setWalletActive(wallet.walletId, false);
  return false; // không xóa item khỏi UI dạng Dismissible, để StreamBuilder tự cập nhật do wallet biến mất khỏi activeWallets
}
if (action == 'reassign') {
  // Giữ nguyên luồng chọn ví thay thế + reassignAndDeleteWallet() đã có sẵn
  ...
}
return false; // action == null (Hủy)
```
Khuyến nghị đổi **"Ẩn ví"** thành lựa chọn được nhấn mạnh/đặt trước (theo đúng tinh thần đã thống nhất: ưu tiên ẩn hơn xóa thật để không mất dữ liệu lịch sử).

### C.6. Dialog "Thêm/Sửa ví" — thêm field `description`, khóa `balance` khi sửa

- Thêm `TextField` "Mô tả (tùy chọn)" vào `_showWalletDialog()`.
- Khi **tạo mới**: field "Số dư" vẫn nhập được như cũ — giá trị này sẽ được lưu đồng thời vào cả `balance` và `initialBalance` (đã xử lý tự động trong constructor `Wallet` ở mục A.1, không cần code thêm gì ở tầng UI).
- Khi **sửa ví đã tồn tại**: field "Số dư" chuyển thành **chỉ đọc** (`enabled: false` hoặc ẩn hẳn, chỉ hiện dòng text tĩnh "Số dư hiện tại: {balance}") — không cho sửa tay số dư sau khi ví đã có giao dịch phát sinh, đúng nguyên tắc "balance chỉ được thay đổi qua Transaction". Cho phép sửa tên ví, loại ví, mô tả.

### C.7. Cập nhật 2 nơi khác đang tính tổng số dư ví — áp dụng lọc `isActive`

- `lib/screens/home/home_dashboard_screen.dart` (biến `totalBalance`): đổi `wallets.fold(...)` thành `wallets.where((w) => w.isActive).fold(...)`.
- `lib/screens/ai/ai_chat_screen.dart` (`_buildFinancialContext()`, biến `totalBalance`): áp dụng đúng cách lọc tương tự trước khi tính tổng gửi cho Gemini.

### C.8. `lib/screens/setup/wallet_setup_screen.dart` — không đổi hành vi, chỉ đảm bảo tương thích

Không cần sửa gì ở màn Setup — `Wallet` constructor đã tự set `initialBalance = balance` khi không truyền tham số đó (xem mục A.1), nên các ví tạo trong Onboarding tự động có `initialBalance` đúng mà không cần đổi code hiện có.

---

## PHẦN D — (Khuyến nghị tách ticket riêng) Thêm loại giao dịch "Chuyển tiền" ở `AddTransactionScreen`

**Không triển khai trong ticket này** — chỉ ghi nhận yêu cầu để làm ticket kế tiếp, vì `add_transaction_screen.dart` là màn đã qua rất nhiều vòng sửa bug quan trọng (ticket 002, 004, 005, 007, 010) và cực kỳ nhạy cảm khi thay đổi cấu trúc (`_type` hiện chỉ có 2 giá trị `expense`/`income`, thêm giá trị thứ 3 sẽ chạm tới toggle button, validation, quick template, luồng OCR — rủi ro cao nếu làm chung với ticket kiến trúc Wallet).

Yêu cầu tóm tắt cho ticket kế tiếp:
- Thêm lựa chọn thứ 3 "Chuyển tiền" bên cạnh "Chi tiêu"/"Thu nhập".
- Khi chọn "Chuyển tiền": ẩn dropdown Danh mục (không áp dụng), hiện 2 dropdown **"Từ ví"** và **"Đến ví"** (validate 2 ví không được trùng nhau).
- Validate số dư ví nguồn đủ để chuyển (tái sử dụng `ValidationUtils.exceedsWalletBalance`).
- **Không** áp dụng kiểm tra ngân sách (`exceedsCategoryBudget`) cho loại `transfer`.
- Gọi `FirestoreService.createTransaction()` với `type: 'transfer'`, `categoryId: ''`, `toWalletId` = ví đích đã chọn (logic backend đã có sẵn từ Phần B của ticket này).

---

## Không đổi (Out of scope)

- Không đổi `firestore.rules`, `firestore.indexes.json` — không có query mới cần composite index (lọc `isActive` thực hiện ở client).
- Không thêm field `icon` tùy chỉnh cho từng ví — icon vẫn suy ra từ `type` như hiện tại.
- Không thêm màn chi tiết ví (Wallet Detail Screen — xem "Giao dịch gần đây theo ví", "Chỉnh sửa/Xóa ví" từ màn riêng) trong ticket này — để dành cho 1 ticket UI riêng nếu cần, tránh phình phạm vi.
- Không đổi `Budget`/`FinancialAnalyticsService` — 2 hệ thống Wallet và Budget vẫn tách biệt hoàn toàn như đã thống nhất.
- Không migrate/backfill dữ liệu ví cũ trên Firestore Console — nhờ cách xử lý fallback ở `fromMap`, không bắt buộc phải chạy migration.

## Acceptance Criteria

- [ ] Tạo ví mới với số dư ban đầu → `initialBalance` và `balance` bằng nhau, `isActive = true`.
- [ ] Tạo giao dịch Thu nhập/Chi tiêu → số dư ví đổi đúng như trước (không regression so với hành vi cũ).
- [ ] Tạo giao dịch Transfer (test tạm qua code/Firestore Console nếu Phần D chưa làm) → ví nguồn giảm đúng, ví đích tăng đúng, **không** ảnh hưởng tới thống kê thu/chi hay ngân sách.
- [ ] Sửa 1 giao dịch Transfer (đổi số tiền hoặc đổi ví nguồn/đích) → số dư cả 2 ví cũ và mới đều được hoàn tác/áp dụng đúng, không lệch.
- [ ] Xóa giao dịch Transfer → hoàn tác đúng số dư cả 2 ví liên quan.
- [ ] Màn "Ví của tôi" hiện đúng "TỔNG TÀI SẢN" = tổng số dư các ví **đang hoạt động**, mỗi card ví hiện đúng "Tỷ lệ trong tổng tài sản" (không còn "Hạn mức sử dụng").
- [ ] Ví chưa có giao dịch → xóa thẳng như cũ, không hỏi thêm.
- [ ] Ví đã có giao dịch → bấm xóa hiện đúng 2 lựa chọn "Ẩn ví"/"Chuyển & Xóa"; chọn "Ẩn ví" → ví biến mất khỏi danh sách + không còn tính vào Tổng tài sản, nhưng lịch sử giao dịch cũ của ví đó vẫn xem được bình thường (không lỗi "Không rõ" khi tra cứu tên ví trong `TransactionDetailScreen`/`TransactionCard`).
- [ ] Sửa ví đã tồn tại → không thể chỉnh tay `balance`, chỉ sửa được tên/loại/mô tả.
- [ ] Dashboard và AI Chat chỉ tính tổng số dư từ các ví đang hoạt động.
- [ ] Test với ví cũ (dữ liệu tạo trước khi có field `isActive`/`initialBalance`) → vẫn hiển thị đúng, không biến mất khỏi danh sách, không crash.
- [ ] `flutter analyze` không phát sinh lỗi/warning mới.

Bổ sung cho Ticket 026
Phần F — Đồng bộ hiển thị giao dịch transfer ở các màn đọc dữ liệu

Context: Ticket này thêm type == 'transfer' ở tầng service (createTransaction, updateTransactionSafely, deleteTransaction), nhưng UI tạo transfer để dành cho ticket sau. Vấn đề: TransactionCard và TransactionDetailScreen hiện đang phân loại nhị phân isIncome = type == 'income', mọi thứ không phải income đều bị coi là expense (màu đỏ, dấu trừ). Nếu có transaction transfer xuất hiện trong dữ liệu (kể cả do test thủ công), nó sẽ hiển thị sai thành khoản chi.

Fix Requirements:

lib/widgets/transaction_card.dart: thêm nhánh riêng cho type == 'transfer' — icon riêng (VD Icons.swap_horiz), màu trung tính (không dùng AppColors.income/expense), không hiện dấu +/- trước số tiền, có thể hiện dạng "Chuyển tiền" thay cho tên danh mục.
lib/screens/home/transaction_detail_screen.dart: tương tự — khi type == 'transfer', đổi tiêu đề "Số tiền đã thu/chi" thành "Số tiền đã chuyển", ẩn phần "Danh mục" (transfer không có category), hiện thêm "Từ ví" / "Đến ví".
lib/screens/home/transaction_list_screen.dart: _typeFilter (all/expense/income) giữ nguyên 3 lựa chọn này cho ticket này — khi _typeFilter == 'all', transfer vẫn hiện lẫn trong danh sách (chấp nhận được), không cần thêm tag lọc riêng ở ticket này.
Phần G — Cập nhật tài liệu

Theo đúng RULES.md mục 9 của dự án, mọi thay đổi schema phải phản ánh vào tài liệu:

context/SCHEMA.md mục 2.2 (wallets): thêm 5 field mới (initialBalance, description, currency, isActive, updatedAt) vào bảng.
context/SCHEMA.md mục 2.4 (transactions): thêm dòng cho toWalletId và giá trị transfer vào enum type.
context/ARCHITECTURE.md mục 3.2 (luồng ghi giao dịch): thêm 1 đoạn mô tả ngắn cách transfer được xử lý atomic trong runTransaction.
Phần H — Làm rõ phạm vi field currency

Field currency (mặc định 'VND') chỉ lưu trữ, không có UI nào đọc/hiển thị đa tiền tệ ở ticket này. Thêm comment // TODO: chưa hỗ trợ đa tiền tệ, mặc định VND ngay tại field trong model, tránh hiểu nhầm đây là tính năng đã hoàn chỉnh.