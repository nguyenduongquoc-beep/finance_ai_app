# TICKET 007 — Reset form khi đổi tab Thu/Chi thủ công & xóa dữ liệu mẫu cũ trước khi OCR

**Loại:** Bug fix
**Độ ưu tiên:** Trung bình-Cao
**File bị ảnh hưởng:** `lib/screens/home/add_transaction_screen.dart`

---

## 1. Context (Bối cảnh)

Test thực tế phát hiện 2 hiện tượng cùng gốc rễ: **form không được dọn dẹp đúng lúc khi người dùng chuyển ngữ cảnh nhập liệu.**

- **Hiện tượng A:** Áp dụng 1 mẫu giao dịch (VD mẫu "Lương" — Thu nhập), sau đó **tự tay** bấm chuyển tab sang "Chi tiêu" → chỉ có Danh mục bị xóa, còn Số tiền/Ví/Ghi chú/Địa điểm **vẫn giữ nguyên** dữ liệu của mẫu Thu nhập, dù giao dịch giờ đã là loại khác hẳn.
- **Hiện tượng B** (thấy rõ trong ảnh test): Áp dụng mẫu "lương tháng" (có địa điểm "công ty abc") → sau đó chụp ảnh hóa đơn mới để OCR → sau khi OCR xong, trường **Địa điểm vẫn hiển thị "công ty abc"** dù hóa đơn scan chẳng liên quan gì tới địa điểm đó.

## 2. Root Cause (Nguyên nhân gốc)

**Hiện tượng A:**
```dart
Widget _typeToggleButton(String label, String type, Color color) {
  ...
  onPressed: () => setState(() {
    _type = type;
    _selectedCategoryId = null; // ❌ chỉ xóa mỗi Danh mục
  }),
  ...
}
```
Chỉ `_selectedCategoryId` được reset, các field khác (`_amountController`, `_selectedWalletId`, `_noteController`, `_locationController`, `_receiptImageBytes`) không hề bị đụng tới.

**Hiện tượng B:**
```dart
Future<void> _parseReceipt() async {
  ...
  final info = await ai.extractReceiptInfo(_receiptImageBytes!);
  if (info != null) {
    if (info.merchant.isNotEmpty) _noteController.text = info.merchant;
    if (info.total > 0) _amountController.text = AppFormatters.number(info.total);
    if (info.date != null) _selectedDate = info.date!;
    // ❌ Không có dòng nào chạm tới _locationController
  }
  ...
}
```
`_parseReceipt()` chỉ **ghi đè** field nếu OCR trích xuất được giá trị mới (`if (info.merchant.isNotEmpty)`), nhưng **không bao giờ xóa** giá trị cũ nếu OCR không trả về gì cho field đó (`location`) — vì `ReceiptInfo` hiện tại còn chưa có field `address`/`location` (xem ticket 008 để bổ sung).

## 3. Fix Requirements (Yêu cầu sửa)

### 3.1. Sửa `_typeToggleButton` — reset toàn bộ form khi đổi tab thủ công

```dart
Widget _typeToggleButton(String label, String type, Color color) {
  final selected = _type == type;
  return OutlinedButton(
    onPressed: () => setState(() {
      _type = type;
      _amountController.clear();
      _selectedWalletId = null;
      _selectedCategoryId = null;
      _noteController.clear();
      _locationController.clear();
      _receiptImageBytes = null;
      _walletBalanceExceeded = false;
      _budgetExceeded = false;
    }),
    style: OutlinedButton.styleFrom(
      backgroundColor: selected ? color.withOpacity(0.12) : null,
      side: BorderSide(color: selected ? color : Colors.grey.shade300),
      padding: const EdgeInsets.symmetric(vertical: 12),
    ),
    child: Text(label, style: TextStyle(color: selected ? color : AppColors.textSecondary)),
  );
}
```
**Lưu ý:** giữ nguyên `_selectedDate` — ngày không cần reset khi đổi tab (người dùng có thể đang cố ý chọn 1 ngày cụ thể trước khi quyết định loại giao dịch).

### 3.2. Sửa `_pickImage()` / gallery picker — xóa ghi chú & địa điểm cũ TRƯỚC khi chạy OCR

Áp dụng cho cả 2 nơi gọi `_parseReceipt()` (camera trong `_pickImage()`, và gallery trong `IconButton.onPressed`):

```dart
Future<void> _pickImage() async {
  final ImageSource source = ImageSource.camera;
  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
    var status = await Permission.camera.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quyền truy cập camera bị từ chối')));
      return;
    }
  }
  final picked = await _picker.pickImage(source: source, imageQuality: 70);
  if (picked != null) {
    final bytes = await picked.readAsBytes();
    setState(() {
      _receiptImageBytes = bytes;
      _noteController.clear();     // ✅ xóa ghi chú cũ (có thể từ mẫu) trước khi OCR điền lại
      _locationController.clear(); // ✅ xóa địa điểm cũ trước khi OCR điền lại
    });
    await _parseReceipt();
  }
}
```
Áp dụng tương tự cho nhánh gallery (`IconButton` chọn ảnh từ thư viện) — thêm 2 dòng `.clear()` trước khi gọi `_parseReceipt()`.

## 4. Không đổi (Out of scope)

- Không đổi `_runValidation()`, `_handleSave()` (đã fix ở ticket 002/005).
- Không đổi logic chọn mẫu (`onSelect` của `QuickTemplateChip`) — mẫu vẫn áp dụng đủ field như ticket 002 đã sửa, chỉ có việc **đổi tab thủ công sau đó** hoặc **chụp ảnh mới sau đó** mới cần reset.

## 5. Acceptance Criteria (Tiêu chí hoàn thành)

- [ ] Áp dụng mẫu Thu nhập → bấm tab "Chi tiêu" → toàn bộ form (số tiền, ví, danh mục, ghi chú, địa điểm, ảnh) về trống.
- [ ] Áp dụng mẫu bất kỳ (có ghi chú/địa điểm) → chụp ảnh hóa đơn mới → sau khi OCR xong, Ghi chú/Địa điểm phải là dữ liệu **mới từ hóa đơn** (hoặc trống nếu OCR không trích được), không còn dữ liệu mẫu cũ.
- [ ] Test cả 2 trường hợp trên tối thiểu 2 lần.
