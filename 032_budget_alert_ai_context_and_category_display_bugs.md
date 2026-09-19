# TICKET 032 — 3 vấn đề phát hiện khi test Ngân sách: cảnh báo gần hạn mức, AI Chat trả lời mã danh mục thay vì tên, danh mục hiện "Không rõ" sau khi xóa ngân sách

**Loại:** Bug fix + UX improvement (3 phần độc lập, xử lý theo đúng thứ tự đánh số)
**Độ ưu tiên:** Cao (Phần B là lỗi hiển thị sai với người dùng cuối; Phần C nếu đúng như mô tả là lỗi mất dữ liệu hiển thị nghiêm trọng)
**File bị ảnh hưởng:** liệt kê riêng trong từng phần

---

## PHẦN A — Không có cảnh báo "gần hạn mức" khi chi tiêu đạt đúng 100% ngân sách

### Hiện tượng test thực tế
- Thiết lập ngân sách "Ăn uống" = 2.000.000đ.
- Đã có sẵn 1 giao dịch Ăn uống 1.000.000đ (tạo **trước** khi thiết lập ngân sách).
- Tạo thêm 1 giao dịch Ăn uống 1.000.000đ nữa → tổng chi đúng bằng 2.000.000đ / 2.000.000đ (100%) → **không** thấy cảnh báo gì khi lưu giao dịch này.
- Tạo tiếp giao dịch Ăn uống thứ 3 (1.000.000đ, sẽ khiến tổng vượt 3.000.000đ) → lúc này mới thấy banner cảnh báo "Giao dịch sẽ vượt quá ngân sách danh mục" và bị chặn lưu.

### Giải thích nguyên nhân (theo đúng code hiện tại — không chắc chắn 100% là bug, cần agent xác nhận lại bước 1 trước khi sửa)

**1. Banner cảnh báo inline ở màn Thêm giao dịch** (`lib/screens/home/add_transaction_screen.dart` → `_runValidation()` → `ValidationUtils.exceedsCategoryBudget()` trong `lib/utils/validation_utils.dart`):
```dart
final projectedSpent = currentSpent + amount;
return projectedSpent > budget.limit; // CHỈ true khi VƯỢT HẲN, không tính bằng
```
Giao dịch thứ 2 khiến `projectedSpent == budget.limit` (2.000.000 == 2.000.000) → điều kiện `>` là `false` → banner **đúng theo thiết kế hiện tại** không hiện. Đây có thể là hành vi **cố ý đúng** (chỉ chặn khi thực sự vượt) hoặc **thiếu sót UX** (nên cảnh báo sớm hơn, ở ngưỡng 80% như `BudgetProgressCard`/`Budget.isNearLimit()` đã định nghĩa) — xem yêu cầu sửa bên dưới để thống nhất 2 nơi này.

**2. Thông báo hệ thống (chuông) khi vượt mốc 80%** — `firestore_service.dart.createTransaction()` có logic bắn `AppNotification` khi `newSpent >= limit * 0.8 && oldSpent < limit * 0.8`. Với kịch bản trên, giao dịch thứ 2 khiến `newSpent = 2.000.000` (bao gồm cả giao dịch cũ tạo trước khi có ngân sách, vì `getCategorySpentThisMonth()` tính tổng toàn bộ giao dịch expense trong tháng của category đó, không quan tâm ngân sách được tạo lúc nào) và `oldSpent = 1.000.000 < 1.600.000` → **về lý thuyết phải bắn đúng 1 thông báo** ở đúng giao dịch thứ 2. Cần xác nhận thực tế có thông báo này trong mục Thông báo (`NotificationScreen`) hay không.

### Yêu cầu sửa

**A.1. Bắt buộc: kiểm tra lại trước khi sửa** — Agent thực thi vào `NotificationScreen` kiểm tra sau khi tái hiện đúng kịch bản (tạo giao dịch khiến tổng đạt đúng 80-99% hạn mức) có xuất hiện thông báo "Cảnh báo ngân sách" hay không:
- Nếu **có** thông báo → mục 2 hoạt động đúng, chỉ cần làm A.2 (cải thiện UX banner inline) bên dưới.
- Nếu **không có** thông báo → đây là bug thật ở logic `createTransaction()`/`updateTransactionSafely()`, cần debug thêm `getCategorySpentThisMonth()` và `budgetRef` query (khả năng do sai lệch định dạng `month` hoặc do budget được tạo sau khi giao dịch cũ tồn tại khiến query tìm sai) — báo cáo lại phát hiện trước khi tự ý sửa sâu vào 2 hàm atomic transaction này (rủi ro cao nếu sửa sai, xem `context/ARCHITECTURE.md` mục 3.2).

**A.2. Cải thiện: thêm banner cảnh báo "sắp đạt hạn mức" (80–99%), phân biệt với banner "đã vượt"**

Trong `add_transaction_screen.dart`, hiện chỉ có 1 biến `_budgetExceeded` (bool) dùng cho cả kiểm tra và hiển thị banner đỏ "sẽ vượt". Đổi sang phân 2 mức, đồng bộ đúng ngưỡng đã dùng ở `Budget.isNearLimit()` (80%):

1. Sửa `ValidationUtils.exceedsCategoryBudget()` — đổi tên hàm thành trả về kết quả chi tiết hơn thay vì `bool` đơn thuần (hoặc thêm hàm mới `checkCategoryBudgetStatus()` trả về enum `{ok, nearLimit, exceeded}`), tính dựa trên `projectedSpent` so với `budget.limit`:
   ```dart
   // ok: projectedSpent < limit * 0.8
   // nearLimit: limit * 0.8 <= projectedSpent <= limit
   // exceeded: projectedSpent > limit
   ```
2. Trong `_runValidation()` ở `add_transaction_screen.dart`, lưu kết quả vào 1 biến enum (VD `_budgetStatus`) thay cho `_budgetExceeded`.
3. Ở UI, hiện 2 loại banner khác nhau:
   - `nearLimit` → banner màu `AppColors.warning` (cam), text: `"Giao dịch này sẽ khiến bạn đạt ${percent}% ngân sách danh mục"`, **không chặn lưu** (giữ nguyên hành vi cho phép lưu khi mới gần hạn mức, chỉ cảnh báo).
   - `exceeded` → giữ nguyên banner đỏ hiện tại + vẫn chặn lưu như cũ (không đổi hành vi này).
4. Nút "Lưu giao dịch" chỉ bị khóa (`onPressed: null`) khi trạng thái là `exceeded`, không khóa khi `nearLimit`.

### Không đổi (Out of scope)
- Không đổi ngưỡng bắn `AppNotification` (giữ 80% như đã có, trừ khi bước A.1 phát hiện đây thực sự là bug).
- Không đổi cách tính `Budget.isNearLimit()`/`isOverBudget()` trong model — chỉ tái sử dụng đúng ngưỡng 80% đã có sẵn ở đó cho nhất quán.

### Acceptance Criteria
- [ ] Xác nhận rõ ràng: thông báo "Cảnh báo ngân sách" (mục Thông báo) có bắn đúng khi giao dịch khiến tổng đạt 80-99% hạn mức hay không — ghi rõ kết quả kiểm tra trong báo cáo.
- [ ] Tạo giao dịch khiến ngân sách đạt khoảng 80-99% → hiện banner cam cảnh báo, **vẫn lưu được** giao dịch bình thường.
- [ ] Tạo giao dịch khiến ngân sách vượt quá 100% → hiện banner đỏ, **chặn lưu** như hành vi hiện tại (không regression).
- [ ] Tạo giao dịch khi ngân sách còn dưới 80% → không hiện banner nào, lưu bình thường.

---

## PHẦN B — AI Chat trả lời mã `categoryId` (Firestore ID) thay vì tên danh mục

### Hiện tượng test thực tế
Hỏi AI Chat: *"Ngân sách nào sắp vượt hạn mức?"* → AI trả lời: *"Danh mục **BQdwDW2XqIARcLdE4K18** đã chi 2.000.000/2.000.000 đ..."* — hiện thẳng document ID của Firestore thay vì tên danh mục "Ăn uống".

### Root Cause (đã xác nhận, không cần điều tra thêm)

Trong `lib/screens/ai/ai_chat_screen.dart`, hàm `_buildFinancialContext()`:
```dart
if (budgets.isNotEmpty) {
  final Map<String, double> spentByCategory = {};
  for (final t in transactions.where((t) => t.type == 'expense')) {
    spentByCategory[t.categoryId] = (spentByCategory[t.categoryId] ?? 0) + t.amount;
  }
  buffer.writeln('\nTình trạng ngân sách:');
  for (final b in budgets) {
    final spent = spentByCategory[b.categoryId] ?? 0;
    final percent = b.limit > 0 ? (spent / b.limit * 100).round() : 0;
    buffer.writeln('- Danh mục ${b.categoryId}: đã chi ${AppFormatters.number(spent)}/${AppFormatters.number(b.limit)} đ ($percent%)');
  }
}
```
Dòng `'- Danh mục ${b.categoryId}: ...'` ghi thẳng `categoryId` (document ID dạng string ngẫu nhiên của Firestore) vào đoạn context text gửi cho Gemini. Gemini chỉ lặp lại đúng nguyên văn những gì nó nhận được trong prompt — không có lỗi gì ở phía model, lỗi nằm ở dữ liệu context được xây dựng sai.

Hàm này **đã fetch sẵn** `categories` ở phía trên trong cùng hàm (dùng để tính `walletId`/context khác), nhưng đoạn build "Tình trạng ngân sách" quên tra tên qua danh sách đó trước khi ghi vào buffer.

### Fix Requirements

Sửa đúng dòng `buffer.writeln` trong đoạn `budgets.isNotEmpty`, tra tên category theo `categoryId`, fallback `'Danh mục'` nếu không tìm thấy (đồng nhất với pattern `orElse` đã dùng ở nhiều nơi khác trong dự án, VD `financial_analytics_service.dart`):

```dart
if (budgets.isNotEmpty) {
  final Map<String, double> spentByCategory = {};
  for (final t in transactions.where((t) => t.type == 'expense')) {
    spentByCategory[t.categoryId] = (spentByCategory[t.categoryId] ?? 0) + t.amount;
  }
  buffer.writeln('\nTình trạng ngân sách:');
  for (final b in budgets) {
    final spent = spentByCategory[b.categoryId] ?? 0;
    final percent = b.limit > 0 ? (spent / b.limit * 100).round() : 0;
    final categoryName = categories
        .where((c) => c.categoryId == b.categoryId)
        .firstOrNull
        ?.name ?? 'Danh mục';
    buffer.writeln('- $categoryName: đã chi ${AppFormatters.number(spent)}/${AppFormatters.number(b.limit)} đ ($percent%)');
  }
}
```

Kiểm tra biến `categories` đã có sẵn đúng tên biến trong scope hàm `_buildFinancialContext()` (đã được fetch ở đầu hàm cho mục đích khác) — nếu tên biến khác, dùng đúng tên đã khai báo, không fetch lại lần 2 (tránh thêm 1 lần gọi Firestore không cần thiết).

### Không đổi (Out of scope)
- Không đổi prompt hệ thống hay cấu trúc `_chatHistory` của AI Chat.
- Không đổi cách `AiInsightScreen`/`FinancialIssue` hiển thị tên danh mục — các nơi đó đã tra tên đúng từ trước, chỉ riêng `ai_chat_screen.dart` bị sót.
- Rà thêm 1 lượt toàn bộ `_buildFinancialContext()` (grep `categoryId` trong file này) để chắc chắn không còn chỗ nào khác lỡ ghi thẳng ID thay vì tên — nếu tìm thấy, sửa theo đúng cùng 1 pattern trên.

### Acceptance Criteria
- [ ] Hỏi AI Chat "Ngân sách nào sắp vượt hạn mức?" → câu trả lời nêu đúng **tên danh mục** (VD "Ăn uống"), không còn hiện chuỗi ID Firestore.
- [ ] Test với ít nhất 2 danh mục có ngân sách khác nhau → AI phân biệt đúng tên từng danh mục trong câu trả lời.
- [ ] Trường hợp danh mục của 1 budget đã bị xóa (xem Phần C) → AI trả lời fallback "Danh mục" thay vì lỗi/crash hoặc hiện ID.

---

## PHẦN C — Danh mục hiện "Không rõ danh mục" ở mọi nơi sau khi xóa Ngân sách (không phải xóa Danh mục)

### Hiện tượng test thực tế
Vào màn Thiết lập ngân sách → xóa dòng ngân sách "Ăn uống" → bấm "Lưu" → quay lại các màn khác (Danh sách giao dịch, Dashboard):
- Tên danh mục ở các giao dịch cũ (vốn thuộc category "Ăn uống") hiển thị thành **"Không rõ dan..."**
- Biểu đồ donut top danh mục chi tiêu: lát "Ăn uống" biến mất, gộp hết vào lát **"Khác"**

### Phân tích rủi ro (⚠️ CẦN AGENT XÁC NHẬN LẠI TRƯỚC KHI SỬA — không tự ý đoán mò)

Đây là hiện tượng **bất thường về mặt kiến trúc**, vì theo đúng code hiện tại:
- `deleteBudget(String budgetId)` trong `firestore_service.dart` **chỉ** xóa document trong collection `budgets`:
  ```dart
  Future<void> deleteBudget(String budgetId) {
    return _db.collection('budgets').doc(budgetId).delete();
  }
  ```
- `BudgetSetupScreen._saveBudgets()` (nơi gọi khi bấm "Lưu") cũng **chỉ** gọi `deleteBudget()`/`updateBudget()`/`createBudget()` cho các dòng ngân sách — không có bất kỳ dòng code nào chạm tới collection `categories` hay `transactions`.
- Xóa `budgets/{budgetId}` **không thể** khiến `categories/{categoryId}` biến mất, vì đây là 2 document hoàn toàn độc lập, chỉ liên kết lỏng lẻo qua field `categoryId` (không có cascade delete kiểu SQL foreign key trong Firestore, và code cũng không tự viết cascade nào cho trường hợp này).

Vì vậy hiện tượng "Không rõ danh mục" **chỉ có thể xảy ra nếu category "Ăn uống" thực sự đã bị xóa khỏi collection `categories`**, hoặc đây là lỗi hiển thị tạm thời do dữ liệu stream chưa đồng bộ đúng lúc.

### Yêu cầu bắt buộc — Bước 1: Xác minh trước khi code bất kỳ dòng nào

Agent thực thi phải làm rõ đúng 1 trong 2 khả năng sau trước khi sửa:

**Khả năng 1 — Category thực sự bị xóa:**
- Vào **Quản lý danh mục** (`CategoryManagementScreen`) ngay sau khi tái hiện lỗi → kiểm tra danh mục "Ăn uống" (tab Chi tiêu) còn tồn tại trong danh sách hay không.
- Nếu **mất thật** → grep toàn bộ codebase tìm mọi lời gọi `deleteCategory(` — xác nhận `budget_setup_screen.dart`/`budget_management_screen.dart` có vô tình gọi nhầm hàm này ở đâu đó thay vì `deleteBudget()` không (dễ nhầm vì tên hàm gần giống nhau). Nếu tìm thấy, sửa đúng lời gọi.
- Nếu vẫn không tìm ra lời gọi sai, kiểm tra kỹ `categoryId` được truyền vào lúc xóa budget — có khả năng `draft.categoryId` ở `_BudgetItemDraft` bị gán nhầm giá trị (VD gán nhầm `budgetId` vào field `categoryId` ở đâu đó) khiến 1 thao tác tưởng là xóa budget lại vô tình trúng đúng ID của category do trùng lặp logic — cần debug bằng cách in log `categoryId`/`budgetId` trước mỗi lệnh xóa trong `_saveBudgets()`.

**Khả năng 2 — Category vẫn còn, chỉ là lỗi hiển thị (nhiều khả năng hơn):**
- Nếu category "Ăn uống" **vẫn còn** trong Quản lý danh mục nhưng Dashboard/Danh sách giao dịch vẫn hiện "Không rõ danh mục" → đây là lỗi **tra cứu sai `categoryId`**, không phải mất dữ liệu. Kiểm tra các nơi hiển thị tên danh mục từ `categoryId` của giao dịch (`transaction_card.dart`, `home_dashboard_screen.dart._buildCategoryPie()`, `transaction_list_screen.dart`) — các hàm này đều dùng `categories.where((c) => c.categoryId == tx.categoryId).firstOrNull` nên nếu category vẫn tồn tại với đúng ID, phải tìm ra được, **trừ khi** `categoryId` lưu trong giao dịch không khớp với `categoryId` thật của category (dữ liệu bị lệch từ trước, không liên quan tới hành động xóa budget vừa test — có thể là trùng hợp phát hiện ra 1 bug cũ khác trong lúc test cái mới).

### Yêu cầu sửa (áp dụng SAU KHI đã xác định đúng nguyên nhân ở bước 1)

- Nếu là **Khả năng 1** (xóa nhầm category): sửa đúng lời gọi hàm bị nhầm, thêm test tái hiện chính xác kịch bản "xóa 1 dòng ngân sách trong màn Thiết lập → Lưu" và xác nhận category không bị đụng tới.
- Nếu là **Khả năng 2** (lệch categoryId có từ trước): đây là bug độc lập, không thuộc phạm vi "logic thiết lập ngân sách" như bạn nghi ngờ — báo cáo lại rõ ràng để tách thành ticket riêng, không sửa lẫn vào logic Budget.

**Dù nguyên nhân là gì, bổ sung thêm 1 lớp phòng vệ UX** (áp dụng luôn, không phụ thuộc kết quả điều tra): khi 1 `Budget` có `categoryId` không khớp với bất kỳ `Category` nào trong danh sách hiện tại (dấu hiệu category đã bị xóa hợp lệ qua luồng "Chuyển & Xóa danh mục" ở nơi khác — xem ticket 015), `BudgetProgressCard`/`BudgetSetupScreen` nên tự ẩn hoặc đánh dấu rõ ràng "Danh mục đã bị xóa" thay vì hiển thị im lặng gây hiểu lầm, và gợi ý người dùng dọn budget mồ côi đó.

### Không đổi (Out of scope)
- Không đổi `reassignAndDeleteCategory()`/luồng xóa danh mục ở `CategoryManagementScreen` — luồng đó có cơ chế reassign riêng, đã đúng từ ticket 015, không liên quan tới luồng xóa Budget đang bị nghi vấn ở đây.
- Không tự ý viết lại `deleteBudget()`/`_saveBudgets()` khi chưa xác nhận rõ nguyên nhân — tránh sửa nhầm chỗ đang hoạt động đúng.

### Acceptance Criteria
- [ ] Báo cáo rõ ràng: category "Ăn uống" còn tồn tại trong Quản lý danh mục hay đã mất, sau khi tái hiện đúng chính xác kịch bản (xóa dòng ngân sách trong `BudgetSetupScreen` → bấm Lưu).
- [ ] Tái hiện lại đúng 2-3 lần để loại trừ yếu tố ngẫu nhiên/cache trước khi kết luận nguyên nhân.
- [ ] Sau khi sửa (theo đúng nhánh nguyên nhân xác định được): xóa 1 dòng ngân sách bất kỳ trong `BudgetSetupScreen` → Lưu → toàn bộ giao dịch cũ thuộc danh mục đó ở Dashboard/Danh sách giao dịch **vẫn hiển thị đúng tên danh mục**, biểu đồ donut vẫn tách đúng lát riêng cho danh mục đó (không gộp vào "Khác").
- [ ] `flutter analyze` không phát sinh lỗi/warning mới sau khi sửa.
