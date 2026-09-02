# TICKET 028 — Sửa lỗi mất số dư khi "Chuyển & Xóa" ví

**Loại:** Bug fix (nghiêm trọng nhất — gây mất tiền/sai lệch tổng tài sản)
**Độ ưu tiên:** Cao nhất
**File bị ảnh hưởng:** `lib/services/firestore_service.dart`

---

## 1. Context (Bối cảnh)

Test thực tế theo kịch bản sau:

- Khởi tạo: Tiền mặt 22.000.000đ (2tr có sẵn + 20tr lương), ví test 3.000.000đ, ví test 2 2.000.000đ → tổng 27.000.000đ.
- Tạo giao dịch "Ăn uống" 1.000.000đ từ "ví test" → ví test còn 2.000.000đ, tổng còn 26.000.000đ. **Đúng.**
- Sửa giao dịch trên, đổi ví từ "ví test" sang "ví test 2" → ví test về 3.000.000đ, ví test 2 về 1.000.000đ, tổng vẫn 26.000.000đ. **Đúng.**
- Xóa "ví test 2" (đang có 1.000.000đ, có giao dịch) → chọn "Chuyển & Xóa" sang "ví test" → giao dịch 1 triệu đổi tên đúng sang "ví test", nhưng **"ví test" vẫn chỉ hiện 3.000.000đ** (không cộng thêm 1 triệu) → **tổng tài sản tụt xuống 25.000.000đ**. **Sai — mất 1 triệu.**
- Tiếp tục xóa "ví test" (lúc này đang có 3.000.000đ) → chuyển sang "momo" (đang có 0đ) → giao dịch đổi tên đúng sang "momo", nhưng **"momo" vẫn 0đ** → **tổng tụt xuống 22.000.000đ**. **Sai — mất 3 triệu.**
- Tiếp tục xóa "Tiền mặt" (22.000.000đ) → chuyển sang "MB Bank" (0đ) → giao dịch lương 20 triệu đổi tên đúng sang "MB Bank", nhưng **"MB Bank" vẫn 0đ** → **tổng tài sản về 0đ**. **Sai — mất toàn bộ 22 triệu.**

Mỗi lần dùng chức năng "Chuyển & Xóa" ví, số dư của ví bị xóa biến mất vĩnh viễn khỏi tổng tài sản, dù bản thân các giao dịch liên quan vẫn còn nguyên (chỉ bị đổi tên ví).

## 2. Root Cause (Nguyên nhân gốc)

`reassignAndDeleteWallet()` trong `firestore_service.dart` hiện tại:

```dart
Future<void> reassignAndDeleteWallet(String userId, String oldWalletId, String newWalletId) async {
  final txQuery = await _db.collection('transactions')
      .where('userId', isEqualTo: userId)
      .where('walletId', isEqualTo: oldWalletId)
      .get();
  final batch = _db.batch();
  for (var doc in txQuery.docs) {
    batch.update(doc.reference, {'walletId': newWalletId}); // chỉ đổi NHÃN giao dịch
  }
  batch.delete(_db.collection('wallets').doc(oldWalletId)); // xóa cả document ví -> mất luôn balance
  await batch.commit();
}
```

Hàm này chỉ **đổi nhãn** (`walletId`) trên các giao dịch cũ sang ví mới, rồi **xóa thẳng document ví cũ** — bao gồm cả field `balance` bên trong. Nó **không hề cộng số dư hiện tại của ví cũ sang ví mới** trước khi xóa. Tiền không thực sự được "chuyển" — chỉ có cái tên trên giao dịch bị đổi, còn số dư thật nằm trong document ví bị xóa vĩnh viễn theo.

Ngoài ra, hàm hiện chỉ query giao dịch có `walletId == oldWalletId` (ví là nguồn/thực hiện giao dịch), **bỏ sót** giao dịch có `toWalletId == oldWalletId` (ví là đích của 1 giao dịch `transfer`, đã thêm ở ticket 026). Nếu ví bị xóa từng là ví đích của 1 giao dịch chuyển tiền, giao dịch đó sẽ mãi trỏ tới `toWalletId` không còn tồn tại.

## 3. Fix Requirements (Yêu cầu sửa)

Viết lại `reassignAndDeleteWallet()`:

```dart
Future<void> reassignAndDeleteWallet(String userId, String oldWalletId, String newWalletId) async {
  final oldWalletDoc = await _db.collection('wallets').doc(oldWalletId).get();
  if (!oldWalletDoc.exists) {
    throw Exception('Ví nguồn không tồn tại');
  }
  final oldBalance = (oldWalletDoc.data()!['balance'] as num).toDouble();

  // Giao dịch mà ví này là ví thực hiện (walletId)
  final txQuery = await _db
      .collection('transactions')
      .where('userId', isEqualTo: userId)
      .where('walletId', isEqualTo: oldWalletId)
      .get();

  // Giao dịch chuyển tiền mà ví này là ví ĐÍCH (toWalletId)
  final transferToQuery = await _db
      .collection('transactions')
      .where('userId', isEqualTo: userId)
      .where('toWalletId', isEqualTo: oldWalletId)
      .get();

  final batch = _db.batch();
  for (var doc in txQuery.docs) {
    batch.update(doc.reference, {'walletId': newWalletId});
  }
  for (var doc in transferToQuery.docs) {
    batch.update(doc.reference, {'toWalletId': newWalletId});
  }

  // QUAN TRỌNG: chuyển toàn bộ số dư ví cũ sang ví mới TRƯỚC khi xóa,
  // để tiền không biến mất khỏi tổng tài sản.
  if (oldBalance != 0) {
    batch.update(_db.collection('wallets').doc(newWalletId), {
      'balance': FieldValue.increment(oldBalance),
    });
  }

  batch.delete(_db.collection('wallets').doc(oldWalletId));
  await batch.commit();
}
```

**Nguyên tắc:** không cần tính lại từng giao dịch — chỉ cần cộng **toàn bộ số dư hiện tại** của ví cũ (đã phản ánh đúng mọi lịch sử tăng/giảm của nó) sang ví mới là đủ đảm bảo tổng tài sản không đổi. Việc đổi `walletId`/`toWalletId` trên giao dịch chỉ phục vụ mục đích hiển thị/lịch sử đúng, tách biệt hoàn toàn khỏi phần cộng số dư.

**Cân nhắc thêm (mức độ thấp hơn, cùng loại bug):** khi xóa ví **chưa có giao dịch nào** (nhánh xóa vĩnh viễn, không qua "Chuyển & Xóa"), nếu ví đó có `balance != 0` (VD người dùng tạo ví có số dư ban đầu nhưng chưa từng dùng tới), dialog xác nhận nên nêu rõ số dư sẽ mất, ví dụ:

```
"Ví này còn ${AppFormatters.currency(wallet.balance)}. Xóa sẽ mất số dư này khỏi Tổng tài sản. Bạn có chắc chắn?"
```

thay vì chỉ nói chung chung "Hành động này không thể hoàn tác."

## 4. Không đổi (Out of scope)

- Không đổi `checkWalletInUse()`, không đổi luồng dialog "Ẩn ví"/"Chuyển & Xóa" ở UI (`wallet_management_screen.dart`) — chỉ sửa đúng hàm `reassignAndDeleteWallet()` trong `firestore_service.dart`.
- Không đổi `createTransaction`/`updateTransactionSafely`/`deleteTransaction` — các hàm này đã đúng (đã tự kiểm chứng qua test tay ở bước đổi ví cho giao dịch expense/transfer).

## 5. Acceptance Criteria (Tiêu chí hoàn thành)

- [ ] Tái hiện đúng kịch bản: Tiền mặt 22tr, ví test 3tr, ví test 2 2tr. Tạo giao dịch ăn uống 1tr từ ví test → ví test còn 2tr, tổng 26tr.
- [ ] Sửa giao dịch đổi ví từ "ví test" sang "ví test 2" → ví test về 3tr, ví test 2 về 1tr, tổng vẫn 26tr (đã đúng từ trước, xác nhận không bị ảnh hưởng bởi fix).
- [ ] Xóa "ví test 2" (1tr, có giao dịch) → chọn "Chuyển & Xóa" sang "ví test" → **ví test phải thành 3tr + 1tr = 4tr**, tổng tài sản **vẫn giữ nguyên 26tr** (không còn tụt xuống 25tr).
- [ ] Tiếp tục xóa "ví test" (giờ có 4tr) → chuyển sang "momo" (0đ) → **momo phải thành 4tr**, tổng vẫn 26tr.
- [ ] Tiếp tục xóa "Tiền mặt" (22tr) → chuyển sang "MB Bank" (0đ) → **MB Bank phải thành 22tr**, tổng vẫn 26tr (không tụt về 0).
- [ ] Vào xem chi tiết giao dịch lương 20tr sau khi đã chuyển qua nhiều ví → tên ví hiển thị đúng là ví cuối cùng nhận, không lỗi "Không rõ".
- [ ] Test dựng lại từ đầu (tạo ví mới, KHÔNG dùng dữ liệu đã bị lỗi ở trên) để xác nhận số liệu sạch, không nhầm lẫn với dữ liệu cũ đã sai từ trước khi fix.

---

## ⚠️ Lưu ý quan trọng về dữ liệu hiện có

Toàn bộ ví/giao dịch dùng để test kịch bản trên **đã bị sai số dư vĩnh viễn** trên Firestore thật (tổng tài sản hiện đang là 0 hoặc gần 0 do bug). Sau khi fix xong code, cần **xóa sạch dữ liệu test này** (xóa các ví momo/MB Bank/tiền mặt/ví test còn sai số) và tạo lại từ đầu để verify — **không sửa tay số dư trên Console**, vì dễ tạo thêm sai lệch mới. Nếu app đã có người dùng thật từng dùng tính năng "Chuyển & Xóa" ví, cần kiểm tra thủ công dữ liệu của họ.
