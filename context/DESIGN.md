# DESIGN — Finance AI App

Nguồn sự thật: `lib/utils/constants.dart` (`AppColors`, `AppStrings`, default categories). Mọi thay đổi màu sắc/spacing phải sửa ở đây, **không** hardcode màu trực tiếp trong widget.

## 1. Nhận diện thương hiệu

- **Tinh thần thiết kế:** tài chính cá nhân — cảm giác ổn định, đáng tin cậy, nhưng vẫn hiện đại nhờ điểm nhấn AI (tím).
- **Tên hiển thị:** "Finance AI" (`AppStrings.appName`)
- **Ngôn ngữ UI:** Tiếng Việt 100% cho người dùng cuối; code/comment kỹ thuật bằng tiếng Anh xen tiếng Việt (giữ nguyên convention hiện có trong repo).

## 2. Bảng màu (`AppColors`)

| Token | Hex | Vai trò |
|---|---|---|
| `primary` | `#2E7D6B` | Xanh lá đậm — màu thương hiệu chính, nút hành động chính, header gradient |
| `secondary` | `#4CAF94` | Xanh lá nhạt hơn — hỗ trợ, gradient phụ |
| `income` | `#2E7D32` | Xanh — thu nhập, số dương, thành công |
| `expense` | `#D32F2F` | Đỏ — chi tiêu, cảnh báo, xóa/nguy hiểm |
| `background` | `#F7F8FA` | Nền màn hình (xám rất nhạt) |
| `card` | `#FFFFFF` | Nền card/surface |
| `textPrimary` | `#1A1A1A` | Chữ chính |
| `textSecondary` | `#757575` | Chữ phụ, caption, placeholder |
| `warning` | `#FFA726` | Cam — sắp vượt ngân sách (near-limit) |
| `aiAccent` | `#7C4DFF` | Tím — mọi thứ liên quan đến AI (icon, card, chip), để người dùng luôn nhận diện được "đây là tính năng AI" |

**Quy tắc màu theo trạng thái ngân sách** (xem `Budget` model):
- Bình thường: `primary`
- `isNearLimit` (≥90%, chưa vượt): `warning`
- `isOverBudget` (đã vượt): `expense`

## 3. Typography

- Font hệ thống mặc định của Material 3 hiện đang dùng (`google_fonts` có trong dependencies nhưng **chưa được áp dụng nhất quán** trong `ThemeData` — cần rà soát khi chuẩn hóa design system).
- Cỡ chữ đang dùng trong thực tế (nên chuẩn hóa thành `AppTextStyles` nếu mở rộng):
  - Số dư/số tiền lớn (Dashboard header): 32px, bold
  - Tiêu đề màn hình / tên mục tiêu: 22–26px, bold
  - Tiêu đề section/card: 15–18px, bold hoặc w600
  - Body: 13–14px
  - Caption/label phụ: 11–12px

## 4. Spacing & Bo góc

- Padding màn hình chuẩn: `16` hoặc `24`
- Khoảng cách giữa các block: bội số của `4` (4, 6, 8, 10, 12, 14, 16, 20, 24, 28, 32)
- Bo góc (`BorderRadius.circular`):
  - Card nhỏ / chip: `10–14`
  - Card lớn / container nổi bật: `16–20`
  - Bottom sheet / numpad: `12`
  - Header gradient bo dưới: `28`
- Card mặc định trong `ThemeData.cardTheme`: `elevation: 0`, bo góc `14`, dùng `boxShadow` thủ công (`Colors.black.withOpacity(0.06–0.07)`, blur 8–10) thay vì elevation Material mặc định để có bóng mềm hơn.

## 5. Component patterns

- **Nút chính:** `ElevatedButton`/`FilledButton` nền `primary`, chữ trắng, bo góc 12, padding vertical 14.
- **Input field:** `filled: true`, nền trắng, `OutlineInputBorder` bo góc 12, không viền (`BorderSide.none`) — set global qua `inputDecorationTheme`.
- **Card thông tin AI:** luôn dùng `aiAccent` làm điểm nhấn (icon trong circle nền `aiAccent.withOpacity(0.12)`, border `aiAccent.withOpacity(0.2–0.3)`).
- **Progress bar ngân sách/mục tiêu:** `LinearPercentIndicator`, `lineHeight: 10–12`, bo góc `barRadius: Radius.circular(6–8)`.
- **Badge trạng thái** (VD "Vượt hạn mức!", "Hoàn thành! 🎉"): pill nhỏ, padding ngang 8/dọc 2-3, bo góc 8, nền đặc màu trạng thái, chữ trắng 11px bold.
- **Step indicator (onboarding setup 3 bước):** thanh ngang bo góc 4, cao 5, màu `primary` cho bước đã qua / `Colors.grey.shade300` cho bước chưa tới.

## 6. Animation

- `LinearPercentIndicator`: `animation: true`, `animationDuration: 600` (budget) hoặc `800` (saving goal).
- `AnimatedContainer` cho dot indicator onboarding: `Duration(milliseconds: 200)`.
- Typing indicator AI chat: `AnimationController` lặp `900ms`, 3 chấm nhấp nhô lệch pha 1/3 chu kỳ.
- Nguyên tắc: animation chỉ dùng cho phản hồi trạng thái (progress, loading, chuyển trang onboarding) — **không** dùng animation trang trí không cần thiết để giữ hiệu năng ổn định trên thiết bị yếu.

## 7. Iconography

- Bộ icon: Material Icons, ưu tiên biến thể `_outlined` cho trạng thái tĩnh/menu, biến thể đặc (filled) cho trạng thái active/nhấn mạnh.
- Icon danh mục: hiện tại **chưa map** `Category.icon` (String) sang `IconData` thật — toàn bộ đang tạm dùng `Icons.category` (ghi nhận nợ kỹ thuật trong PROGRESS.md, cần bảng map string→IconData khi hoàn thiện).

## 8. Accessibility

- Thêm `Semantics` label cho các icon-only button và các thành phần tương tác quan trọng (đặc biệt nút "+" nổi, các icon action trên AppBar) — hiện **chưa được áp dụng đầy đủ**, cần bổ sung khi polish UI.
- Tương phản màu: `textSecondary` (#757575) trên nền trắng/`background` đạt tối thiểu AA cho text thường; tránh dùng `textSecondary` cho text quan trọng cỡ nhỏ hơn 12px.
- Vùng chạm tối thiểu cho các nút icon: giữ mặc định Material (48x48) trừ khi có lý do UI đặc biệt.
