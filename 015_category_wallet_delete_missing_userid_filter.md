# TICKET 015 — Sửa lỗi 4 hàm còn lại thiếu filter `userId` khi kiểm tra/reassign danh mục & ví đang sử dụng

**Loại:** Bug fix (cùng root cause với ticket 014 — chưa lộ ra vì chưa test luồng xóa danh mục/ví)
**Độ ưu tiên:** Cao
**File bị ảnh hưởng:** `lib/services/firestore_service.dart`, `lib/screens/management/category_management_screen.dart`, `lib/screens/management/wallet_management_screen.dart`

---

## 1. Context (Bối cảnh)

Sau khi sửa ticket 014 (4 hàm liên quan tới `budgets` trong luồng tạo/sửa giao dịch), luồng "Thêm giao dịch" đã hoạt động đúng trở lại. Tuy nhiên, rà soát toàn bộ `firestore_service.dart` phát hiện **cùng một lỗi thiết kế query** còn tồn tại ở 4 hàm khác, thuộc luồng "Quản lý danh mục" và "Quản lý ví" — cụ thể là khi người dùng **long-press xóa 1 danh mục** hoặc **vuốt xóa 1 ví** đang chứa giao dịch/ngân sách.

Các hàm này chưa được test kỹ sau khi deploy `firestore.rules` mới, nên bug chưa lộ ra qua log thực tế — nhưng dựa trên đúng cơ chế đã xác nhận ở ticket 014 (Firestore từ chối toàn bộ query nếu field được rule kiểm tra không nằm trong điều kiện `.where()`), các hàm này **chắc chắn sẽ gặp lỗi `permission-denied` y hệt** khi được gọi.

**Rủi ro về UX còn nghiêm trọng hơn ticket 014:** hai nơi gọi các hàm này (`category_management_screen.dart` trong `onLongPress`, `wallet_management_screen.dart` trong `confirmDismiss`) **không có `try/catch`** bọc quanh lời gọi — nghĩa là khi lỗi xảy ra, không có snackbar hay dialog nào hiện lên báo lỗi. Người dùng bấm xóa/vuốt xóa sẽ chỉ thấy **giao diện không phản ứng gì**, rất khó nhận biết nguyên nhân nếu không xem log console.

## 2. Root Cause (Nguyên nhân gốc)

Cùng root cause với ticket 014: Firestore Security Rules yêu cầu field `userId` phải nằm trong chính điều kiện `.where()` của query thì mới cho phép `list`/`get` nhiều document — 4 hàm dưới đây trong `lib/services/firestore_service.dart` đều thiếu điều kiện đó:

**1. `checkCategoryInUse(String categoryId)`** — dùng khi long-press 1 danh mục để kiểm tra có đang được giao dịch/ngân sách nào tham chiếu không:
```dart
Future<bool> checkCategoryInUse(String categoryId) async {
  final txQuery = await _db.collection('transactions').where('categoryId', isEqualTo: categoryId).limit(1).get();
  if (txQuery.docs.isNotEmpty) return true;
  final budgetQuery = await _db.collection('budgets').where('categoryId', isEqualTo: categoryId).limit(1).get();
  return budgetQuery.docs.isNotEmpty;
}
```
Cả 2 query đều thiếu `where('userId', isEqualTo: ...)`.

**2. `checkWalletInUse(String walletId)`** — dùng khi vuốt xóa 1 ví:
```dart
Future<bool> checkWalletInUse(String walletId) async {
  final txQuery = await _db.collection('transactions').where('walletId', isEqualTo: walletId).limit(1).get();
  return txQuery.docs.isNotEmpty;
}
```
Thiếu `userId`.

**3. `reassignAndDeleteCategory(String oldCategoryId, String newCategoryId)`** — khi danh mục đang dùng, chuyển toàn bộ giao dịch/ngân sách sang danh mục khác trước khi xóa:
```dart
Future<void> reassignAndDeleteCategory(String oldCategoryId, String newCategoryId) async {
  final txQuery = await _db.collection('transactions').where('categoryId', isEqualTo: oldCategoryId).get();
  final budgetQuery = await _db.collection('budgets').where('categoryId', isEqualTo: oldCategoryId).get();
  ...
}
```
Cả 2 query đều thiếu `userId`, và hàm cũng thiếu tham số `userId` trong chữ ký.

**4. `reassignAndDeleteWallet(String oldWalletId, String newWalletId)`** — tương tự, cho ví:
```dart
Future<void> reassignAndDeleteWallet(String oldWalletId, String newWalletId) async {
  final txQuery = await _db.collection('transactions').where('walletId', isEqualTo: oldWalletId).get();
  ...
}
```
Thiếu `userId` trong query và chữ ký hàm.

## 3. Fix Requirements (Yêu cầu sửa)

### 3.1. Sửa `checkCategoryInUse()` — thêm tham số `userId`

```dart
Future<bool> checkCategoryInUse(String userId, String categoryId) async {
  final txQuery = await _db
      .collection('transactions')
      .where('userId', isEqualTo: userId)
      .where('categoryId', isEqualTo: categoryId)
      .limit(1)
      .get();
  if (txQuery.docs.isNotEmpty) return true;
  final budgetQuery = await _db
      .collection('budgets')
      .where('userId', isEqualTo: userId)
      .where('categoryId', isEqualTo: categoryId)
      .limit(1)
      .get();
  return budgetQuery.docs.isNotEmpty;
}
```

### 3.2. Sửa `checkWalletInUse()` — thêm tham số `userId`

```dart
Future<bool> checkWalletInUse(String userId, String walletId) async {
  final txQuery = await _db
      .collection('transactions')
      .where('userId', isEqualTo: userId)
      .where('walletId', isEqualTo: walletId)
      .limit(1)
      .get();
  return txQuery.docs.isNotEmpty;
}
```

### 3.3. Sửa `reassignAndDeleteCategory()` — thêm tham số `userId`

```dart
Future<void> reassignAndDeleteCategory(String userId, String oldCategoryId, String newCategoryId) async {
  final txQuery = await _db
      .collection('transactions')
      .where('userId', isEqualTo: userId)
      .where('categoryId', isEqualTo: oldCategoryId)
      .get();
  final budgetQuery = await _db
      .collection('budgets')
      .where('userId', isEqualTo: userId)
      .where('categoryId', isEqualTo: oldCategoryId)
      .get();

  final batch = _db.batch();
  for (var doc in txQuery.docs) {
    batch.update(doc.reference, {'categoryId': newCategoryId});
  }
  for (var doc in budgetQuery.docs) {
    batch.update(doc.reference, {'categoryId': newCategoryId});
  }
  batch.delete(_db.collection('categories').doc(oldCategoryId));
  await batch.commit();
}
```

### 3.4. Sửa `reassignAndDeleteWallet()` — thêm tham số `userId`

```dart
Future<void> reassignAndDeleteWallet(String userId, String oldWalletId, String newWalletId) async {
  final txQuery = await _db
      .collection('transactions')
      .where('userId', isEqualTo: userId)
      .where('walletId', isEqualTo: oldWalletId)
      .get();
  final batch = _db.batch();
  for (var doc in txQuery.docs) {
    batch.update(doc.reference, {'walletId': newWalletId});
  }
  batch.delete(_db.collection('wallets').doc(oldWalletId));
  await batch.commit();
}
```

### 3.5. Cập nhật `category_management_screen.dart` — truyền `userId` + thêm try/catch

Trong `_buildCategoryList()`, phần `onLongPress`, hiện tại gọi trực tiếp không bọc lỗi:
```dart
onLongPress: () async {
  final inUse = await _firestoreService.checkCategoryInUse(c.categoryId);
  ...
},
```

Sửa thành — thêm `userId` (đã có sẵn biến `uid` trong scope `build()`) và bọc `try/catch` để lỗi bất kỳ (permission, mạng...) đều hiện thông báo thay vì im lặng:
```dart
onLongPress: () async {
  try {
    final inUse = await _firestoreService.checkCategoryInUse(uid, c.categoryId);
    if (!inUse) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Xóa danh mục?'),
          content: const Text('Bạn có chắc chắn muốn xóa danh mục này? Hành động này không thể hoàn tác.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa', style: TextStyle(color: AppColors.expense))),
          ],
        ),
      );
      if (confirm == true) {
        await _firestoreService.deleteCategory(c.categoryId);
      }
      return;
    }

    final defaultCategory = categories.firstWhere((cat) => cat.categoryId != c.categoryId, orElse: () => c);
    if (defaultCategory.categoryId == c.categoryId) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể xóa danh mục duy nhất đang chứa giao dịch/ngân sách.')));
      }
      return;
    }

    String? selectedCategoryId = defaultCategory.categoryId;
    final confirmReassign = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Danh mục đang được sử dụng'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Danh mục này đang chứa giao dịch hoặc ngân sách. Vui lòng chọn danh mục để chuyển các dữ liệu này sang trước khi xóa:'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedCategoryId,
                  decoration: const InputDecoration(labelText: 'Chuyển sang', border: OutlineInputBorder()),
                  items: categories
                      .where((cat) => cat.categoryId != c.categoryId)
                      .map((cat) => DropdownMenuItem(value: cat.categoryId, child: Text(cat.name)))
                      .toList(),
                  onChanged: (v) => setState(() => selectedCategoryId = v),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa & Chuyển', style: TextStyle(color: AppColors.expense))),
            ],
          )
        );
      }
    );

    if (confirmReassign == true && selectedCategoryId != null) {
      await _firestoreService.reassignAndDeleteCategory(uid, c.categoryId, selectedCategoryId!);
    }
  } catch (e) {
    debugPrint('❌ Lỗi khi kiểm tra/xóa danh mục: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể xóa danh mục. Vui lòng kiểm tra kết nối và thử lại.')),
      );
    }
  }
},
```
Cần thêm `import 'package:flutter/foundation.dart' show debugPrint;` ở đầu file nếu chưa có.

### 3.6. Cập nhật `wallet_management_screen.dart` — truyền `userId` + thêm try/catch

Trong `_buildWalletList` (hoặc tên tương ứng), phần `confirmDismiss`, hiện tại gọi trực tiếp không bọc lỗi:
```dart
confirmDismiss: (direction) async {
  final inUse = await firestoreService.checkWalletInUse(wallet.walletId);
  ...
},
```

Sửa thành — thêm `userId` và bọc `try/catch`. Vì `confirmDismiss` phải trả về `bool` (Dismissible yêu cầu), khi có lỗi phải trả `false` để không xóa nhầm giao diện trong khi dữ liệu chưa được xử lý đúng:
```dart
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể xóa ví duy nhất đang chứa giao dịch.')));
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
          )
        );
      }
    );

    if (confirmReassign == true && selectedWalletId != null) {
      await firestoreService.reassignAndDeleteWallet(uid, wallet.walletId, selectedWalletId!);
      return true;
    }
    return false;
  } catch (e) {
    debugPrint('❌ Lỗi khi kiểm tra/xóa ví: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể xóa ví. Vui lòng kiểm tra kết nối và thử lại.')),
      );
    }
    return false;
  }
},
```
Cần thêm `import 'package:flutter/foundation.dart' show debugPrint;` ở đầu file nếu chưa có. `uid` đã có sẵn trong scope `build()` của `WalletManagementScreen`.

## 4. Không đổi (Out of scope)

- Không đổi `firestore.rules` — vẫn giữ nguyên rules đã deploy đúng, chỉ sửa code client để khớp đúng yêu cầu của rules.
- Không đổi `deleteCategory()`, `deleteWallet()` — 2 hàm này chỉ xóa theo `documentId` cụ thể (`.doc(id).delete()`), không phải query nhiều document, nên **không** bị lỗi giới hạn rules kiểu này — không cần sửa.
- Không đổi giao diện `AlertDialog`/`StatefulBuilder` bên trong 2 hàm `onLongPress`/`confirmDismiss` — chỉ bọc thêm try/catch bên ngoài và thêm tham số `userId` vào các lời gọi service, không đổi UX/luồng dialog đã có.
- Không xử lý retry tự động — chỉ đảm bảo người dùng biết có lỗi để tự thử lại (đúng nguyên tắc đã áp dụng ở ticket 005).

## 5. Acceptance Criteria (Tiêu chí hoàn thành)

- [ ] Long-press 1 danh mục **không** có giao dịch/ngân sách nào → hiện đúng dialog xác nhận xóa, xóa thành công.
- [ ] Long-press 1 danh mục **đang có** giao dịch/ngân sách → hiện đúng dialog "Danh mục đang được sử dụng" kèm dropdown chọn danh mục thay thế, không còn bị treo/im lặng.
- [ ] Xác nhận "Xóa & Chuyển" ở dialog trên → toàn bộ giao dịch/ngân sách thuộc danh mục cũ được chuyển đúng sang danh mục mới, danh mục cũ bị xóa, không còn lỗi `permission-denied` trong log.
- [ ] Vuốt xóa 1 ví **không** có giao dịch nào → hiện đúng dialog xác nhận, xóa thành công.
- [ ] Vuốt xóa 1 ví **đang có** giao dịch → hiện đúng dialog "Ví đang được sử dụng" kèm dropdown chọn ví thay thế; nếu hủy, item ví **không bị xóa khỏi UI** (do `confirmDismiss` trả về `false` đúng).
- [ ] Xác nhận "Xóa & Chuyển" ở dialog ví → toàn bộ giao dịch thuộc ví cũ chuyển đúng sang ví mới, ví cũ bị xóa.
- [ ] Giả lập lỗi (tắt mạng giữa lúc long-press/vuốt xóa) → hiện đúng snackbar báo lỗi rõ ràng, không còn tình trạng bấm mà giao diện không phản ứng gì.
- [ ] Test danh mục/ví là "danh mục/ví duy nhất đang chứa giao dịch" (không có lựa chọn thay thế) → hiện đúng snackbar "Không thể xóa danh mục/ví duy nhất...", không crash.
