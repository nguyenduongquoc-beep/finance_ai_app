# TICKET 035 — Khắc phục trải nghiệm khi mạng chập chờn: fail-fast khi mất mạng thay vì chờ hết toàn bộ chuỗi model dự phòng

**Loại:** Bug fix (trải nghiệm người dùng — không phải crash, nhưng gây cảm giác "app bị treo/lỗi" khi mạng yếu)
**Độ ưu tiên:** Cao — đây là 1 trong các tính năng cốt lõi (AI + OCR), cần hoạt động mượt và có phản hồi rõ ràng
**File bị ảnh hưởng:** `lib/services/ai_service.dart`, `lib/screens/home/add_transaction_screen.dart`, `lib/screens/ai/ai_chat_screen.dart`, `lib/screens/ai/ai_insight_screen.dart`, `lib/screens/ai/ai_report_screen.dart`, `lib/screens/management/saving_goal_screen.dart`

---

## 1. Context (Bối cảnh)

`AiService._generateWithFallback()` hiện tại thử lần lượt 4 model trong `_modelFallbackChain`, mỗi model có `.timeout(const Duration(seconds: 15))`. Cơ chế này đúng đắn cho trường hợp **1 model cụ thể bị lỗi/deprecate** (VD trả về 404 not found) — khi đó thử model dự phòng tiếp theo là hợp lý.

**Vấn đề:** khi nguyên nhân lỗi là **mất kết nối mạng** (không phải lỗi riêng của 1 model), việc thử tiếp 3 model còn lại là **vô nghĩa** — vì cả 4 model đều cần mạng để gọi API, tất cả sẽ thất bại giống nhau. Hệ quả: người dùng phải chờ tối đa **4 × 15 giây = 60 giây** mới nhận được thông báo lỗi, trong khi lẽ ra chỉ cần chờ đúng 15 giây (1 lần thử) là đã biết chắc chắn là do mất mạng.

Log thực tế đã ghi nhận đúng hiện tượng này:
```
! Model "gemini-3.6-flash" thất bại: TimeoutException after 0:00:15.000000 — thử model dự phòng tiếp theo...
🚀 Đang gọi Gemini với model: gemini-flash-latest
...
! Model "gemini-flash-latest" thất bại: TimeoutException after 0:00:15.000000
OCR Receipt extraction error: TimeoutException after 0:00:15.000000: Future not completed
```
Trong lúc đó, log Firestore ở cùng thời điểm cho thấy rõ nguyên nhân gốc là mất mạng: `Unable to resolve host "firestore.googleapis.com": No address associated with hostname`.

Đây là nguyên nhân trực tiếp khiến người dùng cảm thấy "app bị treo/lỗi" khi mạng chập chờn (không mất hẳn, chỉ yếu/ngắt quãng) — không phải do luồng lưu giao dịch hay OCR bị vỡ logic, mà do **thời gian chờ trước khi nhận được thông báo lỗi quá lâu và không rõ ràng**.

## 2. Nguyên tắc khắc phục

**Phân loại lỗi thành 2 nhóm, xử lý khác nhau:**
1. **Lỗi mạng** (không phân giải được DNS, socket bị đóng, connection refused/reset) → **dừng ngay lập tức**, không thử model tiếp theo, ném ra 1 loại exception riêng để tầng UI nhận diện và hiển thị đúng thông báo "Không có kết nối mạng".
2. **Lỗi khác** (model không tồn tại, quá tải, response rỗng...) → giữ nguyên hành vi cũ, tiếp tục thử model dự phòng tiếp theo.

## 3. Fix Requirements

### 3.1. `lib/services/ai_service.dart` — thêm helper phân loại lỗi mạng

Thêm import nếu chưa có:
```dart
import 'dart:io' show SocketException;
```

Thêm hàm mới trong class `AiService`:
```dart
/// Nhận diện lỗi do MẤT MẠNG (khác với lỗi riêng của 1 model AI).
/// Khi gặp lỗi loại này, thử tiếp các model dự phòng khác là vô nghĩa
/// (vì tất cả đều cần mạng để gọi API) — nên phải dừng ngay, không lãng
/// phí thời gian chờ của người dùng.
bool _isNetworkError(Object e) {
  if (e is SocketException) return true;
  final msg = e.toString().toLowerCase();
  return msg.contains('failed host lookup') ||
      msg.contains('no address associated') ||
      msg.contains('network is unreachable') ||
      msg.contains('connection refused') ||
      msg.contains('connection reset') ||
      msg.contains('software caused connection abort');
}
```

### 3.2. Sửa `_generateWithFallback()` — dừng ngay khi phát hiện lỗi mạng

```dart
Future<GenerateContentResponse> _generateWithFallback(List<Content> content) async {
  Exception? lastError;
  for (final modelName in _modelFallbackChain) {
    try {
      debugPrint('🚀 Đang gọi Gemini với model: $modelName');
      final model = GenerativeModel(model: modelName, apiKey: geminiApiKey);
      final response = await model.generateContent(content)
          .timeout(const Duration(seconds: 15));
      return response;
    } catch (e) {
      if (_isNetworkError(e)) {
        debugPrint('⚠️ Phát hiện lỗi mất mạng khi gọi model "$modelName" — dừng ngay, không thử model dự phòng khác: $e');
        throw Exception('NO_NETWORK');
      }
      lastError = e is Exception ? e : Exception(e.toString());
      debugPrint('⚠️ Model "$modelName" thất bại: $e — thử model dự phòng tiếp theo...');
      continue;
    }
  }
  throw lastError ?? Exception('Tất cả model AI đều không khả dụng');
}
```

**Lưu ý về `TimeoutException`:** timeout **không được** xếp vào nhóm "lỗi mạng chắc chắn" trong bước 3.1 — vì timeout có thể do model xử lý chậm (không nhất thiết là mất mạng), nên vẫn giữ hành vi thử model tiếp theo khi gặp timeout đơn thuần. Chỉ dừng ngay khi có **bằng chứng rõ ràng** là lỗi tầng mạng (DNS/socket) như liệt kê ở `_isNetworkError()`.

### 3.3. Thêm helper dùng chung để kiểm tra lỗi có phải "NO_NETWORK" hay không

Thêm hàm public trong `AiService` để các màn UI dùng lại, tránh mỗi nơi tự viết lại logic so khớp chuỗi:
```dart
/// Kiểm tra 1 exception có phải là lỗi "mất mạng" do _generateWithFallback
/// ném ra hay không — dùng ở tầng UI để hiển thị đúng thông báo.
static bool isNoNetworkException(Object e) {
  return e.toString().contains('NO_NETWORK');
}
```

### 3.4. Cập nhật tầng UI — hiển thị đúng thông báo khi gặp lỗi mạng

Áp dụng pattern sau ở **mọi nơi** đang gọi các hàm của `AiService` (không đổi cấu trúc try/catch hiện có, chỉ thêm 1 nhánh kiểm tra ưu tiên trước khi rơi vào catch chung):

**a) `add_transaction_screen.dart` — `_parseReceipt()`:**
```dart
} catch (e) {
  final msg = AiService.isNoNetworkException(e)
      ? 'Không có kết nối mạng. Vui lòng kiểm tra Internet và thử lại.'
      : 'Lỗi khi trích xuất hoá đơn: $e';
  AppSnackbar.show(context, msg, isError: true);
}
```

**b) `ai_chat_screen.dart` — `_sendMessage()`:**
```dart
} catch (e, stackTrace) {
  debugPrint('AI Chat error: $e');
  debugPrintStack(stackTrace: stackTrace);
  if (mounted) {
    final msg = AiService.isNoNetworkException(e)
        ? 'Không có kết nối mạng. Vui lòng kiểm tra Internet và thử lại.'
        : 'Xin lỗi, đã có lỗi xảy ra. Vui lòng thử lại sau.';
    setState(() => _messages.add(_ChatMessage(msg, false)));
    _scrollToBottom();
  }
}
```

**c) `ai_insight_screen.dart` — `_explainIssue()`, `_explainCut()`, `_loadTrendLazy()`, `_loadOverviewLazy()`:**
Ở mỗi hàm, đổi thông báo lỗi mặc định ("Không thể tải đề xuất từ AI lúc này.") thành có điều kiện:
```dart
} catch (e) {
  if (!mounted) return;
  final msg = AiService.isNoNetworkException(e)
      ? 'Không có kết nối mạng.'
      : 'Không thể tải đề xuất từ AI lúc này.';
  setState(() {
    _aiExplanations[key] = msg;
    _aiLoadingMap[key] = false;
  });
}
```
(Áp dụng đúng pattern tương tự cho `_loadTrendLazy()`/`_loadOverviewLazy()`, giữ nguyên cấu trúc state hiện có, chỉ đổi nội dung thông báo.)

**d) `saving_goal_screen.dart` — `_loadAiPlan()`:**
```dart
} catch (e) {
  if (!mounted) return;
  setState(() => _isLoadingPlan = false);
  final msg = AiService.isNoNetworkException(e)
      ? 'Không có kết nối mạng. Vui lòng thử lại.'
      : 'Không thể tải kế hoạch AI lúc này.';
  AppSnackbar.show(context, msg, isError: true);
}
```
(Cần đổi hàm này từ chỉ `setState` sang có gọi `AppSnackbar` để người dùng biết rõ lý do — hiện tại hàm chỉ âm thầm tắt loading mà không báo gì.)

### 3.5. Không đổi `financial_analytics_service.dart`

`FinancialAnalyticsService` là Dart thuần, không gọi mạng — không liên quan tới ticket này.

## 4. Không đổi (Out of scope)

- Không thêm package kiểm tra kết nối mạng (`connectivity_plus`...) — dùng cách phát hiện lỗi mạng qua exception thực tế khi gọi API, không cần thêm dependency mới, đơn giản và đủ chính xác cho quy mô đồ án.
- Không đổi `_modelFallbackChain` hay số lượng model dự phòng.
- Không đổi timeout 15 giây/model (giữ nguyên theo `RULES.md` mục 7) — chỉ đổi hành vi khi phát hiện chắc chắn là lỗi mạng.
- Không thêm cơ chế tự động thử lại (auto-retry) — người dùng vẫn chủ động bấm lại thao tác sau khi có mạng, đúng UX đã có từ trước (Ticket 005).

## 5. Acceptance Criteria

- [ ] Tắt hẳn Wifi/dữ liệu di động → thử OCR 1 ảnh hóa đơn → nhận được thông báo "Không có kết nối mạng..." trong vòng **~15 giây** (không phải 60 giây như trước).
- [ ] Tắt mạng → hỏi AI Chat 1 câu → tin nhắn lỗi hiện đúng "Không có kết nối mạng...", không phải thông báo lỗi chung chung.
- [ ] Tắt mạng → bấm "Xem giải thích từ AI" ở 1 thẻ vấn đề trong AI Insight → thẻ đó hiện đúng thông báo mất mạng, không chặn các thẻ khác.
- [ ] Giả lập lỗi model cụ thể (VD đổi tạm 1 tên model trong `_modelFallbackChain` thành tên sai) trong khi mạng vẫn bình thường → xác nhận hệ thống **vẫn thử tiếp** các model dự phòng còn lại đúng như hành vi cũ (không bị fail-fast nhầm khi không phải lỗi mạng).
- [ ] Có mạng lại → thử lại thao tác vừa lỗi → hoạt động bình thường, không cần khởi động lại app.
- [ ] Luồng lưu giao dịch (`_handleSave`) không bị ảnh hưởng bởi ticket này — xác nhận lại hành vi cũ vẫn đúng: mất mạng giữa lúc lưu → báo lỗi rõ ràng, giữ nguyên dữ liệu đã nhập trên form.
- [ ] `flutter analyze` không phát sinh lỗi/warning mới.
