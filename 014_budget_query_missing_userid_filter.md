# TICKET 014 — Sửa lỗi query `budgets` thiếu filter `userId` gây `permission-denied` khi lưu giao dịch

**Loại:** Bug fix (nghiêm trọng — chặn luồng chính "Thêm giao dịch")
**Độ ưu tiên:** Cao nhất
**File bị ảnh hưởng:** `lib/services/firestore_service.dart`, `lib/utils/validation_utils.dart`, `lib/screens/home/add_transaction_screen.dart`, `lib/screens/management/budget_management_screen.dart`

---

## 1. Context (Bối cảnh)

Sau khi deploy `firestore.rules` đúng (thay rules test-mode hết hạn bằng rules phân quyền theo `userId`), luồng "Thêm giao dịch" bắt đầu báo lỗi **ngay cả khi OCR trích xuất hóa đơn thành công** (ML Kit + Gemini chạy đúng, không liên quan tới bug này):

```
Query(budgets where categoryId==nY0ckLD1TWQyNs4YRmAq and month==08/2026 ...)
Status{code=PERMISSION_DENIED, description=Missing or insufficient permissions.}
```
```
❌ Lỗi khi lưu giao dịch: [cloud_firestore/permission-denied] The caller does not have permission to execute the specified operation.
```

Người dùng thấy snackbar "Không thể lưu giao dịch. Vui lòng kiểm tra kết nối mạng và thử lại." — nhưng đây **không phải lỗi mạng**, message đó chỉ là nội dung mặc định trong khối `catch` của `_handleSave()`, che giấu lỗi thật là `permission-denied`.

## 2. Root Cause (Nguyên nhân gốc)

`firestore.rules` hiện tại yêu cầu, để `read`/`list` một document trong collection `budgets`:
```
match /budgets/{budgetId} {
  allow read, update, delete: if request.auth != null
    && request.auth.uid == resource.data.userId;
  ...
}
```

Đây là giới hạn kỹ thuật cố hữu của Firestore Security Rules: khi thực hiện một **query** (không phải `get()` theo doc ID cụ thể), Firestore phải kiểm tra rule đó **đúng với mọi document có thể khớp query**, mà không được phép "quét thử rồi lọc bớt". Nếu rule kiểm tra 1 field (`resource.data.userId`) nhưng field đó **không nằm trong điều kiện `.where()` của chính câu query**, Firestore không thể chứng minh trước rằng mọi kết quả trả về đều thỏa rule → nó **từ chối toàn bộ query**, bất kể dữ liệu thật có đúng của user đó hay không.

Rà soát `firestore_service.dart`, có **4 nơi** query/update `budgets` theo `categoryId` + `month` mà **thiếu điều kiện `where('userId', isEqualTo: ...)`**:

1. **`getCategoryBudget(String categoryId, {String? month})`** — thiếu tham số `userId` trong chữ ký hàm luôn, không chỉ thiếu trong query. Đây là hàm gây ra dòng log `"⚠️ Lỗi khi kiểm tra vượt số dư ví/ngân sách"` (gọi qua `ValidationUtils.exceedsCategoryBudget()`).

2. **`createTransaction(AppTransaction tx)`** — đoạn tìm `budgetQuery` bên trong hàm:
   ```dart
   final budgetQuery = await _db
       .collection('budgets')
       .where('categoryId', isEqualTo: tx.categoryId)
       .where('month', isEqualTo: monthStr)
       .limit(1)
       .get();
   ```
   Đây chính là dòng gây ra `"❌ Lỗi khi lưu giao dịch"` — exception văng thẳng ra `_handleSave()` ở `add_transaction_screen.dart`, rơi vào catch chung, hiện snackbar lỗi chung chung.

3. **`updateTransactionSafely(AppTransaction oldTx, AppTransaction newTx)`** — 2 query `oldBudgetQuery`/`newBudgetQuery` cùng lỗi tương tự.

4. **`adjustBudgetSpent(String categoryId, String month, double delta)`** — cũng thiếu `userId` trong cả chữ ký hàm lẫn query.

**Vì sao trước đây không phát hiện ra bug này:** rules test-mode cũ (`allow read, write: if request.time < timestamp.date(...)`) không kiểm tra `userId` gì cả, nên mọi query — kể cả query thiếu filter — đều được cho qua. Bug tồn tại từ đầu nhưng bị rules lỏng che giấu; chỉ lộ ra sau khi rules được deploy đúng theo `userId`.

## 3. Fix Requirements (Yêu cầu sửa)

### 3.1. Sửa `getCategoryBudget()` — thêm tham số `userId` bắt buộc

Trong `lib/services/firestore_service.dart`:
```dart
/// Lấy budget cho danh mục trong tháng hiện tại (hoặc tháng chỉ định)
Future<Budget?> getCategoryBudget(String userId, String categoryId, {String? month}) async {
  final now = DateTime.now();
  final monthStr = month ?? DateFormat('MM/yyyy').format(now);
  final query = await _db
      .collection('budgets')
      .where('userId', isEqualTo: userId)       // ✅ thêm filter userId
      .where('categoryId', isEqualTo: categoryId)
      .where('month', isEqualTo: monthStr)
      .limit(1)
      .get();
  if (query.docs.isEmpty) return null;
  final doc = query.docs.first;
  return Budget.fromMap(doc.data(), doc.id);
}
```

### 3.2. Sửa `getCategoryBudgetSpent()` — truyền `userId` xuống

```dart
/// Lấy số tiền đã chi tiêu của một danh mục (budget) hiện tại
Future<double> getCategoryBudgetSpent(String userId, String categoryId) async {
  final budget = await getCategoryBudget(userId, categoryId);
  return budget?.spent ?? 0;
}
```

### 3.3. Sửa `createTransaction()` — thêm filter `userId` vào `budgetQuery`

```dart
if (tx.type == 'expense') {
  final budgetQuery = await _db
      .collection('budgets')
      .where('userId', isEqualTo: tx.userId)    // ✅ thêm filter userId
      .where('categoryId', isEqualTo: tx.categoryId)
      .where('month', isEqualTo: monthStr)
      .limit(1)
      .get();
  if (budgetQuery.docs.isNotEmpty) {
    budgetRef = budgetQuery.docs.first.reference;
  }
}
```
`tx.userId` đã có sẵn trong `AppTransaction`, không cần truyền thêm tham số.

### 3.4. Sửa `updateTransactionSafely()` — thêm filter `userId` vào cả 2 query

```dart
final oldBudgetQuery = await _db
    .collection('budgets')
    .where('userId', isEqualTo: oldTx.userId)   // ✅ thêm
    .where('categoryId', isEqualTo: oldTx.categoryId)
    .where('month', isEqualTo: monthStrOld)
    .limit(1)
    .get();

final newBudgetQuery = await _db
    .collection('budgets')
    .where('userId', isEqualTo: newTx.userId)   // ✅ thêm
    .where('categoryId', isEqualTo: newTx.categoryId)
    .where('month', isEqualTo: monthStrNew)
    .limit(1)
    .get();
```
Đoạn `updatedBudgetQuery` ở cuối hàm (dùng để kiểm tra cảnh báo vượt 90% sau khi update) cũng cần thêm `.where('userId', isEqualTo: newTx.userId)` tương tự.

### 3.5. Sửa `adjustBudgetSpent()` — thêm tham số `userId`

```dart
/// Cập nhật số tiền đã chi tiêu của ngân sách (khi có giao dịch mới/xóa)
Future<void> adjustBudgetSpent(String userId, String categoryId, String month, double delta) async {
  final query = await _db
      .collection('budgets')
      .where('userId', isEqualTo: userId)        // ✅ thêm filter userId
      .where('categoryId', isEqualTo: categoryId)
      .where('month', isEqualTo: month)
      .limit(1)
      .get();
  // ... phần còn lại giữ nguyên
}
```

### 3.6. Cập nhật tất cả nơi gọi các hàm trên để truyền `userId`

**`lib/utils/validation_utils.dart`** — `exceedsCategoryBudget()`:
```dart
static Future<bool> exceedsCategoryBudget({
  required String userId,          // ✅ thêm tham số
  required String categoryId,
  required double amount,
  required FirestoreService firestoreService,
}) async {
  final budget = await firestoreService.getCategoryBudget(userId, categoryId);
  if (budget == null) return false;
  final projectedSpent = budget.spent + amount;
  return projectedSpent > budget.limit;
}
```

**`lib/screens/home/add_transaction_screen.dart`** — trong `_runValidation()`, nơi gọi `exceedsCategoryBudget`:
```dart
if (_selectedCategoryId != null) {
  final exceed = await ValidationUtils.exceedsCategoryBudget(
    userId: uid,                    // ✅ thêm — dùng biến uid đã lấy sẵn từ FirebaseAuth ở đầu class
    categoryId: _selectedCategoryId!,
    amount: amount,
    firestoreService: _firestoreService,
  );
  setState(() => _budgetExceeded = exceed);
}
```
Lưu ý: hàm `_runValidation()` hiện không có sẵn biến `uid` cục bộ — cần lấy từ `FirebaseAuth.instance.currentUser?.uid` (đã được dùng ở `_handleSave()` trong cùng file, dùng lại đúng pattern đó).

**`lib/screens/management/budget_management_screen.dart`** — trong `_showBudgetDialog()`, đoạn kiểm tra trùng budget khi tạo mới:
```dart
final existing = await firestoreService.getCategoryBudget(uid, selectedCategory!.categoryId, month: month);
```
(`uid` đã có sẵn trong scope của `build()` ở màn này.)

Rà soát toàn bộ codebase (`grep -r "getCategoryBudget\|adjustBudgetSpent\|exceedsCategoryBudget"`) để đảm bảo không bỏ sót lời gọi nào khác ngoài các file đã liệt kê.

## 4. Không đổi (Out of scope)

- Không đổi `firestore.rules` — rules hiện tại (phân quyền theo `userId`) là đúng và cần thiết, đây là code phía client cần khớp theo rules, không phải nới lỏng rules để né bug.
- Không đổi cấu trúc collection `budgets` trong Firestore, không cần migration dữ liệu cũ — mỗi document `budgets` đã có sẵn field `userId` từ khi tạo (`createBudget()` đã ghi đúng qua `Budget.toMap()`), chỉ là query đọc lại thiếu điều kiện lọc.
- Không đổi `_handleSave()` ở `add_transaction_screen.dart` (logic try/catch đã đúng từ ticket 005) — lỗi hiện tại được bắt đúng chỗ, chỉ là nguyên nhân gốc (query bên trong) chưa được sửa.

## 5. Acceptance Criteria (Tiêu chí hoàn thành)

- [ ] Chụp ảnh hóa đơn → OCR trích xuất thành công → chọn ví + danh mục có ngân sách đã thiết lập cho tháng hiện tại → bấm "Lưu giao dịch" → lưu thành công, không còn lỗi `permission-denied` trong log.
- [ ] Tạo giao dịch chi tiêu cho danh mục **có** ngân sách tháng này → `budgets.spent` được cộng dồn đúng số tiền, kiểm tra lại qua Firebase Console.
- [ ] Tạo giao dịch chi tiêu cho danh mục **chưa có** ngân sách nào → vẫn lưu thành công bình thường (không lỗi), không tạo budget mới ngoài ý muốn.
- [ ] Sửa 1 giao dịch đã có (đổi số tiền hoặc đổi danh mục) → `updateTransactionSafely()` cập nhật đúng `spent` cũ và mới, không còn lỗi permission.
- [ ] Ở màn "Thêm giao dịch", khi nhập số tiền gần/vượt ngân sách danh mục đã chọn → cảnh báo "Giao dịch sẽ vượt quá ngân sách" hiện đúng lại như trước (xác nhận `_runValidation()`/`exceedsCategoryBudget()` hoạt động, không còn bị lỗi permission âm thầm khiến cảnh báo không hiện).
- [ ] Ở màn "Quản lý ngân sách", tạo ngân sách mới cho 1 danh mục đã có ngân sách tháng đó → hiện đúng thông báo "đã tồn tại, chuyển sang chế độ sửa" như thiết kế cũ (xác nhận `getCategoryBudget()` với `userId` mới vẫn hoạt động đúng).
- [ ] Test với 2 tài khoản user khác nhau (nếu có thể) → xác nhận user A không đọc/ghi nhầm budget của user B (đúng mục đích ban đầu của rules).
