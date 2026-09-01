# TICKET 018 — Dark Mode thật (toàn app), icon mặt trăng/mặt trời đổi theo trạng thái

**Loại:** Feature mới (không phải bug fix)
**Độ ưu tiên:** Cao
**File bị ảnh hưởng:** `lib/main.dart`, `lib/utils/constants.dart`, `lib/screens/profile_screen.dart`
**File mới:** `lib/services/theme_controller.dart`

---

## 1. Context (Bối cảnh)

Hiện tại `AppColors` (`lib/utils/constants.dart`) là các hằng số `static const Color` cố định — mọi widget trong ~21 màn hình đều tham chiếu trực tiếp `AppColors.background`, `AppColors.card`, `AppColors.textPrimary`... (đúng quy ước `RULES.md` mục 3: cấm hardcode màu, luôn dùng `AppColors.*`). Toggle "Chế độ tối" ở `ProfileScreen` hiện chỉ là `SwitchListTile` placeholder (`value: false`, `onChanged` rỗng), chưa có logic thật (đã ghi nhận ở `PROGRESS.md`).

**Vấn đề kiến trúc cần giải quyết:** vì hầu hết widget dùng trực tiếp `AppColors.xxx` (không qua `Theme.of(context)`), cách làm dark mode "chuẩn Flutter" thông thường (chỉ khai báo `theme`/`darkTheme`/`themeMode` ở `MaterialApp`) **sẽ không tự động áp dụng** cho các widget này — chúng sẽ mãi hiện đúng 1 màu bất kể `themeMode`. Để dark mode thực sự đổi **toàn app** như yêu cầu, cần biến `AppColors` từ hằng số cố định thành giá trị **động theo trạng thái hiện tại**, và toàn bộ cây widget phải được rebuild khi đổi trạng thái.

## 2. Fix Requirements

### 2.1. `lib/services/theme_controller.dart` (MỚI)

```dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================
/// THEME CONTROLLER
/// Quản lý trạng thái Dark Mode toàn app bằng ValueNotifier (đơn giản,
/// không cần thêm package quản lý state mới). Lưu lựa chọn qua
/// shared_preferences để giữ nguyên qua các lần mở app.
/// ============================================================
class ThemeController {
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.light);
  static const _prefKey = 'theme_mode';

  /// Gọi 1 lần trong main() TRƯỚC khi runApp(), để nạp đúng lựa chọn
  /// đã lưu từ lần trước (nếu có).
  static Future<void> loadSavedTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    mode.value = saved == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }

  static Future<void> toggle(bool isDark) async {
    mode.value = isDark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, isDark ? 'dark' : 'light');
  }

  static bool get isDark => mode.value == ThemeMode.dark;
}
```

### 2.2. `lib/utils/constants.dart` — chuyển `AppColors` từ hằng số sang giá trị động

**Chỉ 4 token cần đổi theo chế độ** (background, card, textPrimary, textSecondary) — các màu ngữ nghĩa còn lại (primary, secondary, income, expense, warning, aiAccent) **giữ nguyên giống nhau ở cả 2 chế độ** (đã đủ tương phản trên nền tối, không cần bảng riêng):

```dart
class AppColors {
  // Giữ nguyên — không đổi theo chế độ
  static const Color primary = Color(0xFF2E7D6B);
  static const Color secondary = Color(0xFF4CAF94);
  static const Color income = Color(0xFF2E7D32);
  static const Color expense = Color(0xFFD32F2F);
  static const Color warning = Color(0xFFFFA726);
  static const Color aiAccent = Color(0xFF7C4DFF);

  // MỚI — đổi động theo ThemeController.isDark
  static Color get background =>
      ThemeController.isDark ? const Color(0xFF121212) : const Color(0xFFF7F8FA);
  static Color get card =>
      ThemeController.isDark ? const Color(0xFF1E1E1E) : Colors.white;
  static Color get textPrimary =>
      ThemeController.isDark ? const Color(0xFFF5F5F5) : const Color(0xFF1A1A1A);
  static Color get textSecondary =>
      ThemeController.isDark ? const Color(0xFFB0B0B0) : const Color(0xFF757575);
}
```

Thêm `import 'package:flutter/material.dart';` + `import '../services/theme_controller.dart';` vào đầu file nếu chưa có.

**Hệ quả kỹ thuật quan trọng:** vì 4 token này không còn là `const`, mọi nơi trong code đang dùng `const Text(style: TextStyle(color: AppColors.textPrimary))` hoặc tương tự (khai báo `const` widget có tham chiếu 1 trong 4 token trên) **sẽ lỗi biên dịch**. Đây là bước dọn dẹp bắt buộc:
1. Sau khi đổi `constants.dart`, chạy `flutter analyze`.
2. Với **mỗi dòng báo `error`** (không phải `info`/`warning`) liên quan tới việc dùng `const` với giá trị không còn là hằng số → xóa từ khóa `const` ở đúng vị trí đó (chỉ xóa `const`, không đổi gì khác).
3. Lặp lại `flutter analyze` tới khi không còn `error` nào.

### 2.3. `lib/main.dart` — nạp theme đã lưu + bọc `MaterialApp` để rebuild khi đổi

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await ThemeController.loadSavedTheme(); // MỚI — nạp trước khi runApp
  runApp(const FinanceAiApp());
}

class FinanceAiApp extends StatelessWidget {
  const FinanceAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: AppStrings.appName,
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.primary, brightness: Brightness.light),
            scaffoldBackgroundColor: AppColors.background,
            appBarTheme: AppBarTheme(
              backgroundColor: AppColors.background,
              foregroundColor: AppColors.textPrimary,
              elevation: 0, centerTitle: false),
            inputDecorationTheme: InputDecorationTheme(
              filled: true, fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppColors.primary, brightness: Brightness.dark),
            scaffoldBackgroundColor: AppColors.background,
            appBarTheme: AppBarTheme(
              backgroundColor: AppColors.background,
              foregroundColor: AppColors.textPrimary,
              elevation: 0, centerTitle: false),
            inputDecorationTheme: InputDecorationTheme(
              filled: true, fillColor: AppColors.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          ),
          initialRoute: AppRoutes.splash,
          routes: AppRoutes.routes,
        );
      },
    );
  }
}
```

Thêm `import 'services/theme_controller.dart';` vào đầu file.

**Vì sao dùng `ValueListenableBuilder` bọc cả `MaterialApp`:** khi `ThemeController.mode` đổi giá trị, toàn bộ `MaterialApp` (và mọi widget con bên dưới, bao gồm các widget đang gọi `AppColors.xxx` — giờ là getter động) được rebuild lại từ gốc, đảm bảo màu sắc cập nhật đồng loạt trên **mọi màn hình đang hiển thị**, không chỉ màn Profile.

### 2.4. `lib/screens/profile_screen.dart` — nối toggle "Chế độ tối" với logic thật + icon đổi mặt trăng/mặt trời

Thay `SwitchListTile` placeholder hiện tại bằng:

```dart
ValueListenableBuilder<ThemeMode>(
  valueListenable: ThemeController.mode,
  builder: (context, mode, _) {
    final isDark = mode == ThemeMode.dark;
    return SwitchListTile(
      secondary: Icon(
        isDark ? Icons.wb_sunny_outlined : Icons.dark_mode_outlined,
        color: AppColors.primary,
      ),
      title: const Text('Chế độ tối'),
      value: isDark,
      onChanged: (v) => ThemeController.toggle(v),
    );
  },
)
```

Thêm `import '../services/theme_controller.dart';` vào đầu file.

**Quy ước icon (theo đúng yêu cầu):** đang ở **chế độ sáng** → hiện icon **mặt trăng** (`Icons.dark_mode_outlined`, gợi ý "bấm để chuyển sang tối"). Đang ở **chế độ tối** → hiện icon **mặt trời** (`Icons.wb_sunny_outlined`, gợi ý "bấm để chuyển về sáng").

## 3. Không đổi (Out of scope)

- Không thêm chế độ "Theo hệ thống" (tự động theo cài đặt điện thoại) — chỉ 2 trạng thái Sáng/Tối, chuyển bằng tay qua công tắc, đúng yêu cầu ban đầu ("chỉ cần ấn nút gạt").
- Không tinh chỉnh riêng từng widget/màn cho đẹp hơn ở dark mode ngoài việc đổi đúng 4 token màu nền tảng — nếu có chỗ nào tương phản chưa tốt sau khi đổi, ghi nhận riêng để tinh chỉnh sau, không mở rộng phạm vi ticket này.
- Không đổi màu splash/logo app icon (icon ứng dụng ngoài màn hình chính, launcher icon) — chỉ đổi UI bên trong app.
- Không đổi cách các mục Ngôn ngữ/Tiền tệ hoạt động (thuộc ticket riêng khác).

## 4. Acceptance Criteria

- [ ] Mở app lần đầu (chưa từng đổi gì) → mặc định chế độ Sáng.
- [ ] Vào Profile → bấm công tắc "Chế độ tối" → **toàn bộ app** (không chỉ màn Profile) chuyển sang nền tối ngay lập tức: Dashboard, Danh sách giao dịch, AI Insight, Setup, tất cả các màn đã mở/điều hướng qua.
- [ ] Icon cạnh "Chế độ tối" đổi đúng: đang sáng → hiện mặt trăng; đang tối → hiện mặt trời.
- [ ] Tắt app hoàn toàn, mở lại → giữ đúng chế độ đã chọn lần trước (không reset về sáng).
- [ ] Ở chế độ tối, chữ/nút/card vẫn đọc được rõ ràng, không bị chữ tối trên nền tối hoặc ngược lại — kiểm tra tối thiểu 5 màn hình khác nhau (Dashboard, Add Transaction, AI Chat, Profile, 1 màn Management bất kỳ).
- [ ] `flutter analyze` sau khi hoàn tất **không còn `error`** nào (chỉ chấp nhận `info`/`warning` không liên quan, như các cảnh báo `withOpacity` deprecated đã có từ trước).
- [ ] Test chuyển đổi qua lại Sáng ⇄ Tối tối thiểu 3 lần liên tiếp để chắc chắn không bị treo/lỗi giữa chừng.
