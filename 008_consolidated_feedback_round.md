# TICKET 008 — Tổng hợp phản hồi vòng test thực tế (9 vấn đề)

File này gộp toàn bộ feedback mới nhất. Mỗi mục có trạng thái rõ ràng:
- ✅ **Đã có ticket riêng** — không cần làm gì thêm ở đây
- 🔧 **Fix đề xuất sẵn** — có thể giao thẳng cho Antigravity
- ❓ **Cần bạn cung cấp thêm** — ghi rõ cần dán code/ảnh gì, ở đâu
- 💭 **Cần xác nhận hướng** — đề xuất 1-2 hướng, bạn chọn trước khi viết fix chi tiết

---

## Vấn đề 1 — Onboarding tạo ví/danh mục "tham khảo" gây thừa dữ liệu

**Trạng thái: 💭 Cần xác nhận hướng**

### Hiện trạng
`category_setup_screen.dart` mặc định **TẤT CẢ checkbox danh mục đều được tick sẵn**:
```dart
late List<bool> _incomeSelected = List.filled(DefaultIncomeCategories.categories.length, true);
late List<bool> _expenseSelected = List.filled(DefaultExpenseCategories.categories.length, true);
```
→ Nếu người dùng không để ý bỏ tick, bấm "Hoàn tất" luôn thì **toàn bộ 10 danh mục mặc định** đều được tạo, kể cả cái không dùng tới — đúng như cảm giác "tham khảo" bạn mô tả.

`wallet_setup_screen.dart` thì ngược lại — chỉ "Tiền mặt" mặc định tick sẵn, còn lại (MB Bank, Vietcombank, MoMo, ZaloPay) mặc định **không** tick.

### Hai hướng đề xuất — chọn 1

**Hướng A (tối thiểu, ít thay đổi code):** Đổi category setup giống cách wallet đang làm — chỉ tick sẵn 2-3 danh mục phổ biến nhất (VD "Ăn uống", "Lương"), còn lại để trống, buộc người dùng chủ động chọn thêm nếu cần.

**Hướng B (cải tiến rõ hơn):** Thêm dòng text hướng dẫn phía trên mỗi bước setup kiểu "Bạn có thể bỏ chọn các mục không cần thiết — có thể thêm/sửa lại sau ở phần Quản lý", để người dùng hiểu đây là bước có thể tùy chỉnh, không phải "phải chọn hết".

**→ Bạn chọn hướng A, B, hay cả 2 để mình viết ticket chi tiết.**

---

## Vấn đề 2 — Đổi tab Thu/Chi thủ công không xóa form cũ + xóa mẫu bằng long-press

**Trạng thái: ✅ Đã có ticket** — xem `007_form_reset_on_type_toggle_and_ocr.md` (phần đổi tab) và `006_dashboard_donut_and_template_delete_proposal.md` (phần B — long-press xóa mẫu).

---

## Vấn đề 3 — OCR: giữ dữ liệu mẫu cũ + cần trích chi tiết món hàng + địa chỉ

**Trạng thái: 🔧 Fix đề xuất sẵn (phần xóa dữ liệu cũ đã có ở ticket 007) + đề xuất cải tiến trích xuất**

### Phần đã có fix
Việc Ghi chú/Địa điểm giữ dữ liệu mẫu cũ khi chuyển sang chụp OCR → đã sửa trong `007_form_reset_on_type_toggle_and_ocr.md` mục 3.2.

### Phần còn thiếu: OCR chưa trích chi tiết món hàng và địa chỉ

Model `ReceiptInfo` (`lib/models/receipt_info.dart`) **đã có sẵn field `items`** (danh sách `ReceiptItem { description, amount }`) nhưng **chưa từng được dùng** — vì prompt gửi Gemini hiện tại chỉ yêu cầu `merchant/total/date`, không yêu cầu liệt kê từng món hàng, và cũng chưa có field `address`.

### Fix đề xuất

**Bước 1 — Thêm field `address` vào `ReceiptInfo`:**
```dart
class ReceiptInfo {
  final String merchant;
  final double total;
  final DateTime? date;
  final String? taxId;
  final String? address; // ✅ MỚI
  final List<ReceiptItem>? items;
  ...
  factory ReceiptInfo.fromJson(Map<String, dynamic> json) {
    return ReceiptInfo(
      merchant: json['merchant'] as String? ?? '',
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      date: json['date'] != null ? DateTime.parse(json['date'] as String) : null,
      taxId: json['taxId'] as String?,
      address: json['address'] as String?, // ✅ MỚI
      items: json['items'] != null
          ? (json['items'] as List).map((e) => ReceiptItem.fromJson(e as Map<String, dynamic>)).toList()
          : null,
    );
  }
  ...
}
```

**Bước 2 — Sửa prompt trong `ai_service.dart` (cả 2 nhánh: gửi raw text từ ML Kit, và fallback gửi ảnh thẳng) để yêu cầu thêm `address` và `items`:**
```dart
final prompt = '''
Dưới đây là văn bản được trích xuất từ ảnh hóa đơn bằng OCR (có thể còn nhiễu/sai sót):
---
$rawText
---
Hãy phân tích và trả về JSON gồm:
- merchant: tên cửa hàng
- total: tổng tiền (số)
- date: ngày (ISO string hoặc null)
- address: địa chỉ cửa hàng ghi trên hóa đơn (nếu có, hoặc null)
- items: danh sách các món đã mua, mỗi món gồm { "description": "tên món + số lượng", "amount": đơn giá x số lượng }
Chỉ trả về JSON thuần túy, không markdown fence.''';
```
(Áp dụng thay đổi tương tự cho prompt ở nhánh fallback ảnh thẳng.)

**Bước 3 — Sửa `_parseReceipt()` trong `add_transaction_screen.dart` để dùng `items` xây ghi chú chi tiết, và `address` điền vào Địa điểm:**
```dart
Future<void> _parseReceipt() async {
  if (_receiptImageBytes == null) return;
  setState(() => _isParsing = true);
  final ai = AiService();
  try {
    final info = await ai.extractReceiptInfo(_receiptImageBytes!);
    if (info != null) {
      // Ghi chú: liệt kê món hàng nếu có, fallback về tên cửa hàng nếu không có items
      if (info.items != null && info.items!.isNotEmpty) {
        final itemLines = info.items!
            .map((it) => '${it.description}: ${AppFormatters.number(it.amount)}đ')
            .join('\n');
        _noteController.text = itemLines;
      } else if (info.merchant.isNotEmpty) {
        _noteController.text = info.merchant;
      }
      if (info.total > 0) _amountController.text = AppFormatters.number(info.total);
      if (info.date != null) _selectedDate = info.date!;
      if (info.address != null && info.address!.isNotEmpty) {
        _locationController.text = info.address!;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã trích xuất thông tin hoá đơn')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể trích xuất thông tin hoá đơn')));
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi khi trích xuất hoá đơn: $e')));
  }
  setState(() => _isParsing = false);
  await _runValidation();
}
```

### Về việc Ví/Danh mục không tự điền được — đây KHÔNG phải bug

Hóa đơn giấy **không có thông tin** "bạn trả bằng ví nào" hay "thuộc danh mục chi tiêu nào trong app của bạn" — đây là thông tin chỉ tồn tại trong đầu người dùng, không thể suy ra từ ảnh. Việc luôn cần chọn tay Ví + Danh mục sau khi OCR là **thiết kế đúng**, không cần sửa.

### Acceptance Criteria
- [ ] Quét 1 hóa đơn có nhiều món hàng (như ảnh "Trạm dừng Minh Phát 2" có 2 món) → Ghi chú hiện đúng 2 dòng liệt kê tên món + giá tiền, không chỉ tên cửa hàng.
- [ ] Địa điểm tự điền đúng địa chỉ ghi trên hóa đơn (VD "Mỹ Đức Đông, Cái Bè, Đồng Tháp").
- [ ] Hóa đơn không có địa chỉ rõ ràng → Địa điểm để trống, không lỗi.

---

## Vấn đề 4 — Lọc lịch sử giao dịch Ngày/Tuần/Tháng phi logic

**Trạng thái: 💭 Cần xác nhận hướng**

### Giải thích nguyên nhân (không phải bug ngẫu nhiên)
`transaction_list_screen.dart` hiện tại:
```dart
DateTime get _fromDate {
  switch (_filter) {
    case _FilterRange.day: return DateTime(now.year, now.month, now.day);
    case _FilterRange.week: return now.subtract(Duration(days: now.weekday - 1));
    case _FilterRange.month: return DateTime(now.year, now.month, 1);
  }
}
```
"Tháng" = chỉ tính từ ngày 1 tháng hiện tại trở đi — **không** bao gồm tháng trước. "Tuần" tính từ Thứ 2 tuần này — nếu tuần hiện tại "bắc cầu" qua 2 tháng (VD Thứ 2 là 27/7, hôm nay là 2/8), thì bộ lọc Tuần **vô tình** hiện được vài ngày cuối tháng 7 — đây chính là điều bạn thấy gây cảm giác "phi logic" (Tuần thấy được dữ liệu cũ mà Tháng lại không thấy).

### Hai hướng đề xuất — chọn 1

**Hướng A (đúng ý bạn mô tả):** Đổi hẳn thiết kế màn Lịch sử giao dịch — bỏ khái niệm "lọc theo khoảng ngắn hạn", thay bằng hiển thị **toàn bộ lịch sử, nhóm theo từng tháng** (giống cách `ListView` nhóm theo ngày hiện tại đang làm trong `_groupByDay()`, nhưng đổi thành nhóm theo tháng, sắp xếp mới nhất lên đầu). 3 nút Ngày/Tuần/Tháng có thể đổi thành 1 cách hiển thị duy nhất, hoặc giữ 3 nút nhưng đổi nghĩa: "Ngày" = hôm nay, "Tuần" = 7 ngày gần nhất, "Tháng" = **toàn bộ lịch sử nhóm theo tháng** (không giới hạn tháng hiện tại).

**Hướng B (ít thay đổi hơn):** Giữ nguyên 3 bộ lọc như hiện tại (đúng nghĩa "khoảng thời gian ngắn hạn"), chỉ **đổi tên nút** cho rõ nghĩa hơn (VD "Tháng này" thay vì "Tháng"), và **thêm 1 màn/nút riêng "Xem toàn bộ lịch sử"** để không lẫn 2 khái niệm vào chung 3 nút cũ.

**→ Đây là thay đổi tương đối lớn về UX, ảnh hưởng cả `TransactionListScreen` lẫn cách nhóm hiển thị. Bạn chọn hướng A hay B, mình viết ticket chi tiết kèm code.**

---

## Vấn đề 5 — "Số dư tháng này" nên là tổng số dư hiện tại

**Trạng thái: 🔧 Fix đề xuất sẵn**

### Root cause
`home_dashboard_screen.dart` hiện tính:
```dart
final balance = income - expense; // chỉ tính riêng tháng hiện tại
```
và gán label "Số dư tháng này" — đúng như bạn nói, không hợp lý vì số dư thật phải là **tổng tất cả ví cộng lại** (đã có sẵn field `Wallet.balance`, được cập nhật qua `FieldValue.increment` mỗi lần có giao dịch — đây chính là số dư thật, không cần tính lại từ transactions).

### Fix đề xuất
Thêm `StreamBuilder<List<Wallet>>` trong `HomeDashboardScreen` để lấy tổng số dư thật:
```dart
// Bên trong build(), lồng thêm 1 StreamBuilder cho wallets
StreamBuilder<List<Wallet>>(
  stream: firestoreService.streamWallets(uid),
  builder: (context, walletSnap) {
    final wallets = walletSnap.data ?? [];
    final totalBalance = wallets.fold<double>(0, (a, w) => a + w.balance);
    // Dùng totalBalance thay cho `balance` (income - expense) khi build header
    ...
  },
)
```
Và đổi label:
```dart
Text('Số dư hiện tại', ...)  // thay vì 'Số dư tháng này'
```
Giữ nguyên `income`/`expense` và label "Thu tháng này"/"Chi tháng này" — 2 cái này đúng theo bạn xác nhận.

### Acceptance Criteria
- [ ] Header hiển thị đúng tổng số dư của **tất cả ví cộng lại**, không phụ thuộc tháng.
- [ ] Tạo giao dịch mới → số dư cập nhật đúng ngay (income cộng, expense trừ).
- [ ] Label đổi thành "Số dư hiện tại".

---

## Vấn đề 6 — Biểu đồ AI Insight xấu/lệch số

**Trạng thái: ❓ Cần bạn gửi lại ảnh**

Trong 6 ảnh bạn gửi, **không có ảnh nào là màn hình "AI Insight"** (biểu đồ trend 6 tháng trong `trend_chart_card.dart`) — 6 ảnh là: form thêm giao dịch (x2), hóa đơn giấy, dashboard chính, danh sách giao dịch, dialog thêm ngân sách bị crash.

**→ Bạn vào lại màn AI → AI Insight, chụp màn hình biểu đồ bị lệch/xấu đó, gửi lại cho mình.** Không đoán mò sửa khi chưa thấy hình thật — code hiện tại (`trend_chart_card.dart`) đã có `interval: 1` cho trục X, nên cần xem đúng ảnh mới biết bug nằm ở đâu (trục Y chồng chữ? Card quá nhỏ bị nén? Label bị cắt?).

---

## Vấn đề 7 — Nạp tiền mục tiêu tiết kiệm không trừ ví

**Trạng thái: 💭 Cần xác nhận hướng**

### Giải thích (bạn nói đúng, đây là lỗ hổng thiết kế thật)
`saving_goal_screen.dart._addDeposit()` hiện tại chỉ tăng `savedAmount` của mục tiêu, **không hề đụng tới ví nào** — tức là "nạp tiền" chỉ là con số ảo, không phải tiền thật di chuyển từ ví sang. Bạn hoàn toàn đúng khi nói điều này vô lý.

### Hướng đề xuất
Sửa dialog "Nạp tiền" — thêm dropdown chọn Ví (tương tự dropdown Ví ở màn Thêm giao dịch), validate số tiền nạp không vượt quá số dư ví đó, và khi xác nhận:
1. Trừ số dư ví đã chọn (`adjustWalletBalance(walletId, -deposit)`)
2. Cộng `savedAmount` của mục tiêu (như hiện tại)

Về bản chất, đây giống 1 giao dịch "chuyển tiền nội bộ" (không phải income/expense thường, không ảnh hưởng biểu đồ thu/chi) — cần cân nhắc có nên tạo thêm 1 `AppTransaction` ghi nhận việc này để hiện trong lịch sử hay không.

**→ Bạn xác nhận: có muốn làm ngay tính năng này không, hay để sau khi các bug ưu tiên cao hơn đã ổn định? Đây là thay đổi vừa phải (1 dialog + logic trừ ví), không quá lớn, có thể làm sớm nếu bạn muốn.**

---

## Vấn đề 8 — Donut tương tác theo cột tháng

**Trạng thái: ✅ Đã có ticket** — xem `006_dashboard_donut_and_template_delete_proposal.md` phần A.

---

## Vấn đề 9 — Quản lý ngân sách: crash khi thêm + làm rõ mục đích tính năng

**Trạng thái: ❓ Cần bạn dán code hiện tại**

### Trả lời phần "mục này có tác dụng gì"
Tính năng Ngân sách cho phép đặt **hạn mức chi tiêu theo tháng cho từng danh mục** (VD "Ăn uống: tối đa 3.000.000đ/tháng"). Khi bạn thêm giao dịch chi tiêu thuộc danh mục đó, app tự cộng dồn vào `spent` và cảnh báo khi gần/vượt hạn mức (badge "Sắp vượt!"/"Vượt hạn mức!" đã thấy ở `BudgetProgressCard`, và tự tạo thông báo trong `notifications` khi vượt 90%). Đây là tính năng có thật, không phải thừa — chỉ là bạn chưa dùng tới nên chưa thấy tác dụng.

### Về lỗi crash
Ảnh lỗi cho thấy:
```
'There should be exactly one item with [DropdownButtonFormField]'s value: Instance of 'Category'...'
```
Đây là lỗi kinh điển của `DropdownButtonFormField` khi `value:` không khớp đúng 1 phần tử trong `items:` — nhưng theo code gốc mình có trong tay (`budget_management_screen.dart`), dropdown Danh mục ở dialog "Thêm ngân sách" **không hề set `value:`** (mặc định null), nên về lý thuyết không thể gây lỗi này. Có khả năng file này đã được chỉnh sửa ở đâu đó ngoài các ticket đã giao (có thể do 1 lần Antigravity tự ý sửa thêm, hoặc bạn/AI tool khác từng đụng vào), khiến code thực tế khác với bản mình đang lưu.

**→ Bạn mở file `lib/screens/management/budget_management_screen.dart`, copy toàn bộ hàm `_showBudgetDialog()` (từ `void _showBudgetDialog(` tới dấu `}` đóng hàm, khoảng 80-100 dòng), dán vào đây cho mình xem đúng code đang chạy thật, mình mới xác định chính xác được chỗ nào gây lỗi.**

---

## Tóm tắt việc cần bạn làm ngay

1. **Trả lời 3 câu hỏi hướng thiết kế:** vấn đề 1 (A/B), vấn đề 4 (A/B), vấn đề 7 (làm ngay hay để sau)
2. **Gửi 1 ảnh:** màn hình AI Insight bị lệch (vấn đề 6)
3. **Dán 1 đoạn code:** hàm `_showBudgetDialog()` trong `budget_management_screen.dart` (vấn đề 9)
4. **Có thể giao ngay cho Antigravity** (không cần chờ gì thêm): ticket 007 (đã tạo) + phần fix trong ticket 008 mục 3, mục 5 ở trên
