# TICKET 024 — Redesign màn Quản lý danh mục sang dạng List (theo mockup mới) + icon theo danh mục + nút Thêm + Long-press xóa có tên danh mục + chặn trùng tên

**Loại:** UI/UX redesign + Cải tiến logic (icon mapping, validate trùng tên)
**Độ ưu tiên:** Trung bình
**File bị ảnh hưởng:** `lib/screens/management/category_management_screen.dart`
**File tham khảo (không sửa, chỉ đọc để tái dùng logic icon đã có):** `lib/widgets/transaction_card.dart`, `lib/screens/home/transaction_detail_screen.dart`, `lib/screens/setup/category_setup_screen.dart`

---

## 1. Context (Bối cảnh)

Màn `CategoryManagementScreen` hiện tại hiển thị danh mục dạng **GridView 3 cột**, mỗi ô chỉ có icon tròn cố định (`Icons.category` cho mọi danh mục — nợ kỹ thuật đã ghi nhận ở `DESIGN.md` mục 7) + tên danh mục, không có số liệu chi tiêu.

Theo mockup mới (đính kèm `category-management.png`), thiết kế đổi sang **dạng List** mỗi dòng 1 danh mục, gồm:
- Icon tròn nền nhạt theo màu danh mục, icon thật khớp với loại danh mục (ăn uống → dao nĩa, di chuyển → xe, mua sắm → túi, hóa đơn → hóa đơn, sức khỏe → xe cứu thương/y tế, giáo dục → mũ tốt nghiệp...).
- Tên danh mục (đậm) + dòng phụ bên dưới hiện **số tiền đã chi tiêu/thu nhập trong tháng hiện tại** của đúng danh mục đó.
- Tab "Chi tiêu"/"Thu nhập" dạng pill bo tròn, nền xám nhạt, tab active nổi trắng + chữ xanh đậm.
- Nút "+" nổi để thêm danh mục mới (**tự thiết kế** — mockup không có sẵn nút riêng cho màn này, chỉ có nút "+" ở bottom nav chính dùng để thêm giao dịch, không phải thêm danh mục).

Ngoài ra bổ sung 2 yêu cầu hành vi:
- Nhấn giữ (long-press) 1 danh mục → hiện dialog xác nhận xóa, **nội dung phải nêu rõ tên danh mục đang xóa**, xóa xong là mất vĩnh viễn.
- Không cho tạo 2 danh mục **trùng tên** (cùng loại Chi tiêu/Thu nhập, không phân biệt hoa thường/khoảng trắng thừa).

## 2. Fix Requirements

### 2.1. Thêm hàm map `icon` (String) → `IconData` ngay trong file này

Codebase hiện có **3 nơi khác nhau** đã tự viết y hệt 1 switch-case map icon string → IconData (`transaction_card.dart._getCategoryIcon`, `transaction_detail_screen.dart.getCategoryIcon`, `category_setup_screen.dart._getIconData`) — **không** tạo thêm bản sao thứ 4 với logic khác biệt. Copy đúng nguyên bộ mapping đã có (cùng danh sách case: `restaurant`, `shopping_bag`, `local_gas_station`, `school`, `movie`, `flight`, `local_hospital`, `work`, `card_giftcard`, `storefront`, default `Icons.category`) làm private method `_getCategoryIcon(String iconName)` trong `_CategoryManagementScreenState`.

> Ghi chú kỹ thuật (không thuộc phạm vi ticket này, chỉ ghi nhận): về lâu dài nên gom 3-4 bản sao này thành 1 helper dùng chung ở `lib/utils/` — nếu muốn thực hiện dọn dẹp đó, cần 1 ticket riêng (đổi ≥3 file, rủi ro cao hơn phạm vi ở đây).

### 2.2. Đổi bố cục từ `GridView` sang `ListView` theo đúng style mockup

Thay `GridView.builder` (`crossAxisCount: 3`) bằng `ListView.builder`, mỗi item là 1 `Container` bo góc 16, nền `AppColors.card`, shadow nhẹ (`Colors.black.withOpacity(0.05)`, blur 6-8), margin ngang 16 / dọc 6, padding 14, chứa `Row`:
- `CircleAvatar` (radius ~24) nền `Color(c.color).withOpacity(0.15)`, icon `_getCategoryIcon(c.icon)` màu `Color(c.color)`.
- Cột tên + dòng phụ: tên danh mục (`fontWeight: bold`, `fontSize: 15`, `AppColors.textPrimary`), dòng dưới `'${label} trong tháng: ${AppFormatters.currency(monthlyTotal)}'` (`fontSize: 12`, `AppColors.textSecondary`) — `label` = `'Chi tiêu'` nếu tab đang là `expense`, `'Thu nhập'` nếu `income`.

`onTap`/`onLongPress` giữ đúng vị trí như hiện tại (tap để sửa, long-press để xóa — xem mục 2.5).

### 2.3. Tính số tiền chi tiêu/thu nhập trong tháng cho từng danh mục

Trong `_buildCategoryList(uid, type)`, lồng thêm 1 `StreamBuilder<List<AppTransaction>>` (dùng `firestoreService.streamTransactions(uid, from: monthStart)` đã có sẵn — **không** thêm hàm mới trong `FirestoreService`, không thêm composite index mới) để lấy giao dịch tháng hiện tại **một lần cho cả danh sách**, sau đó gộp tổng theo `categoryId` bằng Dart thuần (client-side, giống cách `_buildCategoryPie` ở Dashboard đã làm):

```dart
final monthStart = DateTime(DateTime.now().year, DateTime.now().month, 1);

StreamBuilder<List<AppTransaction>>(
  stream: _firestoreService.streamTransactions(uid, from: monthStart),
  builder: (context, txSnap) {
    final monthTx = txSnap.data ?? [];
    final Map<String, double> totalsByCategory = {};
    for (final tx in monthTx.where((t) => t.type == type)) {
      totalsByCategory[tx.categoryId] = (totalsByCategory[tx.categoryId] ?? 0) + tx.amount;
    }
    // truyền totalsByCategory xuống ListView.builder, tra theo c.categoryId, mặc định 0 nếu chưa có giao dịch
    ...
  },
)
```

Cần thêm `import '../../models/transaction_model.dart';` nếu file chưa có.

### 2.4. Đổi `TabBar` sang dạng Pill Segmented (đúng mockup)

Thay `TabBar` mặc định trong `AppBar.bottom` bằng khối segmented control tự vẽ, đặt trong `body` (không còn nằm trong `AppBar`), theo đúng style pill đã dùng ở `home_dashboard_screen.dart._buildHalfYearFilter()` (nền `Colors.grey.shade100`, item active nền trắng bo góc, chữ `AppColors.primary` bold khi active, `AppColors.textSecondary` khi không active). Bỏ `TabController`/`TabBarView`, thay bằng 1 biến state `String _selectedType = 'expense'` (hoặc giữ `TabController.index` nếu muốn ít thay đổi hơn — miễn UI đúng dạng pill, không bắt buộc bỏ hẳn `TabController`).

### 2.5. Nút "+" Thêm danh mục — tự thiết kế, đặt FAB riêng cho màn này

Giữ nguyên `floatingActionButton: FloatingActionButton(...)` đã có sẵn gọi `_showCategoryDialog(context, uid)`, chỉ chỉnh style cho nhất quán với `WalletManagementScreen` (cùng pattern trong app): nền `AppColors.primary`, icon `Icons.add` màu trắng, `shape: CircleBorder()`, không cần đổi vị trí (mặc định `FloatingActionButtonLocation.endFloat` — góc dưới-phải), **không** đặt trùng vị trí với nút "+" thêm giao dịch của bottom nav chính (nút đó thuộc `MainNavigation`, ở giữa, không liên quan tới màn này).

### 2.6. Long-press xóa — dialog phải nêu rõ tên danh mục

Sửa nội dung `AlertDialog` xác nhận xóa (nhánh không đang được sử dụng, trong `onLongPress`) từ:
```dart
content: const Text('Bạn có chắc chắn muốn xóa danh mục này? Hành động này không thể hoàn tác.'),
```
thành (chèn tên danh mục cụ thể):
```dart
content: Text('Bạn có chắc chắn muốn xóa danh mục "${c.name}"? Hành động này không thể hoàn tác, dữ liệu sẽ mất vĩnh viễn.'),
```
Giữ nguyên toàn bộ phần còn lại của `onLongPress` (kiểm tra `checkCategoryInUse`, luồng reassign khi đang được dùng, try/catch báo lỗi qua `AppSnackbar` — đã đúng từ ticket 015, không đổi).

### 2.7. Chặn tạo/sửa trùng tên danh mục (cùng loại)

Trong `_showCategoryDialog()`, trước khi gọi `_firestoreService.createCategory(...)` hoặc `updateCategory(...)`, thêm kiểm tra trùng tên (so sánh `trim().toLowerCase()`, cùng `type`, bỏ qua chính nó khi đang sửa):

```dart
TextButton(
  onPressed: () async {
    final newName = nameController.text.trim();
    if (newName.isEmpty) return;

    final isDuplicate = await _firestoreService
        .streamCategories(uid, type: type)
        .first
        .then((list) => list.any((existing) =>
            existing.categoryId != category?.categoryId &&
            existing.name.trim().toLowerCase() == newName.toLowerCase()));

    if (isDuplicate) {
      if (ctx.mounted) {
        AppSnackbar.show(context, 'Danh mục "$newName" đã tồn tại, vui lòng đặt tên khác.', isError: true);
      }
      return;
    }

    if (category == null) {
      await _firestoreService.createCategory(Category(
        categoryId: '',
        userId: uid,
        name: newName,
        type: type,
        icon: 'category',
        color: selectedColor.value,
      ));
    } else {
      await _firestoreService.updateCategory(category.categoryId, {
        'name': newName,
        'color': selectedColor.value,
      });
    }
    if (ctx.mounted) Navigator.pop(ctx);
  },
  child: const Text('Lưu'),
),
```

Dùng `.first` trên stream đã có sẵn (`streamCategories`) để lấy snapshot hiện tại — **không** thêm hàm Firestore mới, không thêm field `unique` ở tầng DB (NoSQL không hỗ trợ constraint kiểu này, validate ở tầng ứng dụng đúng theo `SCHEMA.md` mục 4).

## 3. Không đổi (Out of scope)

- Không đổi `FirestoreService` (không thêm hàm mới, không đổi signature `streamCategories`/`createCategory`/`updateCategory`/`checkCategoryInUse`/`reassignAndDeleteCategory`).
- Không đổi luồng reassign khi danh mục đang được dùng (dialog chọn danh mục thay thế) — giữ nguyên 100% logic đã có từ ticket 015.
- Không đổi bảng chọn màu (`_colorOptions`) hay dialog chọn màu hiện có.
- Không thêm bảng icon picker cho người dùng tự chọn icon khi tạo danh mục mới — mọi danh mục **mới tạo** vẫn gán `icon: 'category'` mặc định như hiện tại (map ra `Icons.category`); việc chọn icon tùy ý là tính năng khác, ngoài phạm vi ticket này.
- Không đổi cách tính `spent` của `Budget` hay bất kỳ collection nào khác — số liệu "Chi tiêu trong tháng" ở màn này là tính **hiển thị riêng cho màn Category**, độc lập với `budgets.spent`.

## 4. Acceptance Criteria

- [ ] Màn Quản lý danh mục hiển thị dạng list dọc, mỗi dòng đúng bố cục: icon tròn màu theo danh mục + tên + dòng phụ số tiền tháng này, khớp đúng tinh thần mockup đính kèm.
- [ ] Danh mục "Ăn uống" hiện đúng icon dao nĩa (`restaurant`), "Mua sắm" hiện icon túi (`shopping_bag`), v.v. — khớp đúng bảng mapping đã có sẵn trong app (không hiện `Icons.category` cho các danh mục đã có icon string hợp lệ).
- [ ] Số tiền "Chi tiêu trong tháng"/"Thu nhập trong tháng" hiển thị đúng, cập nhật ngay khi thêm/sửa/xóa giao dịch thuộc danh mục đó trong tháng hiện tại.
- [ ] Tab Chi tiêu/Thu nhập hiện dạng pill bo tròn đúng mockup, chuyển tab mượt, danh sách + số liệu đổi đúng theo tab.
- [ ] Bấm nút "+" (FAB riêng của màn này, không phải nút giữa bottom nav) → mở đúng dialog thêm danh mục.
- [ ] Nhấn giữ 1 danh mục **chưa** được dùng ở giao dịch/ngân sách nào → dialog xác nhận hiện đúng tên danh mục, xác nhận xóa → danh mục biến mất, không thể khôi phục.
- [ ] Nhấn giữ 1 danh mục **đang** được dùng → luồng reassign hiện đúng như cũ (không bị ảnh hưởng bởi thay đổi UI).
- [ ] Tạo danh mục mới với tên trùng (kể cả khác hoa/thường, khác khoảng trắng đầu-cuối) với 1 danh mục **cùng loại** đã có → báo lỗi rõ ràng, không tạo thêm bản ghi mới.
- [ ] Tạo danh mục cùng tên nhưng **khác loại** (VD "Khác" cho cả Chi tiêu và Thu nhập) → cho phép tạo bình thường (validate chỉ áp dụng trong cùng 1 loại).
- [ ] Sửa tên 1 danh mục về đúng tên cũ của chính nó (không đổi gì) → không bị báo lỗi trùng (loại trừ đúng `categoryId` đang sửa).
- [ ] `flutter analyze` không phát sinh lỗi/warning mới.
