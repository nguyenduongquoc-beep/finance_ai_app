# TICKET 015 — Áp dụng thiết kế Figma cho 3 màn hình: Add Transaction, Transaction Detail, AI Chat (CHỈ đổi UI, không đổi logic)

**Loại:** UI/UX redesign thuần túy (không phải bug fix, không phải feature mới)
**Độ ưu tiên:** Trung bình
**File bị ảnh hưởng:** `lib/screens/home/add_transaction_screen.dart`, `lib/screens/home/transaction_detail_screen.dart`, `lib/screens/ai/ai_chat_screen.dart`

---

## 1. Context (Bối cảnh)

Áp dụng lại giao diện theo thiết kế Figma mới cho 3 màn hình. **Đây là ticket chỉ đổi phần hiển thị (UI)** — không thêm tính năng, không sửa bất kỳ logic nghiệp vụ nào. Ba màn hình này chứa logic đã qua nhiều vòng sửa bug quan trọng (xem `002_add_transaction_save_reliability.md`, `004_quick_template_category_race.md`, `005_silent_save_failure_fix.md`, `007_form_reset_on_type_toggle_and_ocr.md`, `010_atomic_transaction_and_note_multiline.md`) — nên đây là ticket **rủi ro cao nếu làm ẩu**, cần tuyệt đối cẩn trọng giữ nguyên phần logic khi đổi UI.

**Giả định về phạm vi AI Chat**: ticket này hiểu yêu cầu cho `AiChatScreen` là **chỉ đổi giao diện thuần túy** theo Figma (không đổi nội dung/hành vi chat, không áp dụng thay đổi kiến trúc "AI là giá trị cốt lõi" như đã làm ở ticket AI Insight riêng). Nếu đây không đúng ý định, cần làm rõ lại trước khi thực hiện.

## 2. Nguyên tắc bắt buộc khi thực hiện (đọc kỹ trước khi sửa)

- **Không đổi tên, không xóa, không thêm** bất kỳ biến state, `TextEditingController`, hàm xử lý (`_handleSave`, `_runValidation`, `_parseReceipt`, `_pickImage`, `_saveAsTemplate`, `_sendMessage`, `_buildFinancialContext`, `_resetChat`, v.v.) — chỉ được thay đổi phần `Widget build()` (cấu trúc UI trả về) và các widget con thuần hiển thị.
- **Không đổi thứ tự gọi hàm, không đổi điều kiện `if`/logic validate** — chỉ đổi cách hiển thị kết quả (màu sắc, layout, style).
- Nếu thiết kế Figma đòi hỏi thêm 1 trường dữ liệu mới không có trong model hiện tại (`AppTransaction`, `Category`, `Wallet`) → **KHÔNG tự thêm field mới**, dừng lại và báo cáo riêng, không tự quyết định.
- Sau khi sửa xong mỗi màn, **chạy `flutter analyze`** và tự kiểm tra lại đúng các luồng nghiệp vụ liệt kê ở mục Acceptance Criteria trước khi coi là hoàn tất.

## 3. Fix Requirements

### 3.1. `lib/screens/home/add_transaction_screen.dart`

Áp dụng màu sắc/spacing/style theo Figma cho toàn bộ các thành phần đã có, **giữ nguyên 100% cấu trúc dữ liệu và hành vi**:

- Toggle "Chi tiêu"/"Thu nhập" — đổi style nút, **giữ nguyên logic reset toàn bộ form khi đổi tab** (đã cố ý thiết kế vậy ở ticket 007, không được bỏ).
- Hàng chip mẫu giao dịch nhanh (`QuickTemplateChip`) — đổi style chip, **giữ nguyên** `onSelect` áp dụng đủ 4 field (ví/danh mục/ghi chú/địa điểm) đã fix ở ticket 002.
- Ô nhập số tiền (mở numpad khi chạm) — đổi style hiển thị số, giữ nguyên cơ chế `readOnly: true` + `onTap: _showNumpad`.
- Dropdown Ví/Danh mục — đổi style dropdown, **tuyệt đối giữ nguyên** cách kiểm tra `value` hợp lệ (logic đã fix race condition ở ticket 004 — dùng `allCategories` để check tồn tại, `categories` đã lọc để hiện `items`).
- Cảnh báo vượt số dư ví/vượt ngân sách (`_walletBalanceExceeded`/`_budgetExceeded`) — đổi style hiển thị cảnh báo (màu, icon) cho đẹp hơn, giữ nguyên điều kiện hiển thị.
- Ô Ghi chú (`maxLines: null, minLines: 1`) — giữ nguyên khả năng nhiều dòng đã fix ở ticket 010 phần B, chỉ đổi style viền/màu.
- Khu vực chụp/chọn ảnh hóa đơn — đổi style hiển thị, giữ nguyên 2 luồng (camera qua `_pickImage()`, gallery qua `IconButton` riêng), giữ nguyên việc xóa Ghi chú/Địa điểm trước khi OCR (ticket 007).
- Nút "Lưu giao dịch" — đổi style, giữ nguyên điều kiện `onPressed: (_isSaving || _isParsing || _isValidating) ? null : _handleSave`.

### 3.2. `lib/screens/home/transaction_detail_screen.dart`

- Áp dụng style Figma cho toàn bộ layout hiển thị chi tiết (số tiền, ngày, ghi chú, địa điểm, ảnh hóa đơn).
- Giữ nguyên dialog xác nhận xóa (`showDialog` với 2 nút Hủy/Xóa) và lệnh gọi `firestoreService.deleteTransaction(transaction)`.
- Giữ nguyên cách hiển thị ảnh bằng `Image.file(File(transaction.image!))` kèm `errorBuilder` (đã fix ở ticket 011) — **không được đổi lại thành `Image.network`**.

### 3.3. `lib/screens/ai/ai_chat_screen.dart`

- Áp dụng style Figma cho: AppBar (icon + tên "Trợ lý AI" + trạng thái "Đang hoạt động"), bong bóng chat (`_ChatBubble`), thanh gợi ý câu hỏi (`_buildSuggestions`), thanh nhập liệu (`_buildInputBar`), hiệu ứng đang gõ (`_TypingIndicator`).
- Giữ nguyên toàn bộ nội dung 3 câu gợi ý có sẵn (`'Tháng này tôi chi tiêu bao nhiêu?'`, `'Gợi ý tiết kiệm cho tôi'`, `'Ngân sách nào sắp vượt hạn mức?'`) — chỉ đổi style hiển thị chip, không đổi nội dung câu chữ trừ khi có xác nhận riêng.
- Giữ nguyên toàn bộ luồng gọi `AiService` (`_buildFinancialContext`, `chatWithFinancialData`, `resetChatSession`) — không đổi.

## 4. Không đổi (Out of scope)

- Không đổi bất kỳ hàm trong `FirestoreService`, `StorageService`, `AiService`, `ValidationUtils`, `TemplateService`.
- Không đổi model (`AppTransaction`, `Category`, `Wallet`, `QuickTemplate`).
- Không thêm tính năng mới (VD không thêm nút mới, không thêm bước xác nhận mới) ngoài những gì đã liệt kê là "đổi style".
- Không đổi nội dung prompt gửi Gemini ở `AiService`.
- Không đổi route/navigation flow giữa các màn.

## 5. Acceptance Criteria

**Add Transaction:**
- [ ] Tạo giao dịch Thu nhập (điền đủ số tiền/ví/danh mục) → lưu thành công, không bị khóa nút.
- [ ] Tạo giao dịch Chi tiêu vượt số dư ví hoặc vượt ngân sách → cảnh báo vẫn hiện đúng như cũ (chỉ khác style).
- [ ] Áp dụng 1 mẫu giao dịch → đủ cả 4 field (ví/danh mục/ghi chú/địa điểm) được điền đúng ngay lần đầu, không cần bấm lại lần 2.
- [ ] Đổi tab Chi tiêu ⇄ Thu nhập thủ công → toàn bộ form về trống như cũ.
- [ ] Chụp/chọn ảnh hóa đơn → OCR chạy đúng, điền đúng field, xóa đúng ghi chú/địa điểm cũ trước khi điền mới.
- [ ] Ghi chú nhiều dòng (từ OCR) hiển thị đầy đủ, không bị cắt.

**Transaction Detail:**
- [ ] Xem chi tiết 1 giao dịch có ảnh → ảnh hiển thị đúng qua `Image.file`, không lỗi.
- [ ] Xóa giao dịch → dialog xác nhận hiện đúng, xóa xong quay về màn trước, số dư ví cập nhật đúng.

**AI Chat:**
- [ ] Gửi tin nhắn → nhận phản hồi từ Gemini dựa trên dữ liệu tài chính thật, hiển thị đúng bong bóng chat.
- [ ] Bấm 1 trong 3 chip gợi ý → gửi đúng câu hỏi tương ứng.
- [ ] Bấm nút "Phiên mới" → xóa lịch sử chat, hiện lại tin nhắn chào mừng.

**Chung:**
- [ ] `flutter analyze` không phát sinh lỗi/warning mới sau khi sửa cả 3 màn.
- [ ] Test toàn bộ luồng trên tối thiểu 2 lần mỗi màn để chắc chắn không phải ăn may.
