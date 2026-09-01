# TICKET 019 — Hạ tầng đa ngôn ngữ (Việt/Anh) + màn chọn ngôn ngữ + áp dụng cho module Auth (Giai đoạn 1)

**Loại:** Feature mới — dựng hạ tầng đa ngôn ngữ, áp dụng thí điểm 1 module
**Độ ưu tiên:** Cao
**File bị ảnh hưởng:** `pubspec.yaml`, `lib/main.dart`, `lib/screens/profile_screen.dart`, `lib/screens/auth/splash_screen.dart`, `lib/screens/auth/onboarding_screen.dart`, `lib/screens/auth/login_screen.dart`, `lib/screens/auth/register_screen.dart`, `lib/screens/auth/forgot_password_screen.dart`
**File mới:** `l10n.yaml`, `lib/l10n/app_vi.arb`, `lib/l10n/app_en.arb`, `lib/services/locale_controller.dart`, `lib/screens/language_selection_screen.dart`

---

## 1. Context (Bối cảnh)

Dựng hạ tầng đa ngôn ngữ chuẩn Flutter (`flutter_localizations` + file `.arb`), tạo màn chọn ngôn ngữ hoạt động thật (đổi `Locale` toàn app khi chọn), và áp dụng thí điểm cho **module Auth** (Splash, Onboarding, Login, Register, Forgot Password) để chứng minh cơ chế chạy đúng.

**Phạm vi có chủ đích (đã thống nhất trước):** đây là **Giai đoạn 1** trong kế hoạch nhiều giai đoạn. Các module còn lại (Setup, Home, Management, AI, Profile...) **chưa** được dịch trong ticket này — sẽ làm ở các ticket riêng tiếp theo, mỗi ticket 1 module, tránh rủi ro vỡ toàn app nếu làm 1 lượt.

**Quyết định UX cho màn chọn ngôn ngữ:** hiện đầy đủ danh sách ~18-20 ngôn ngữ phổ biến (đúng yêu cầu "thiết kế theo chuẩn quốc tế", có cờ quốc gia, tìm kiếm, sắp xếp A-Z) để màn hình trông chuyên nghiệp/đầy đủ khi demo — nhưng **chỉ Tiếng Việt và English thực sự hoạt động được** (có bản dịch thật). Các ngôn ngữ khác hiển thị **mờ (disabled)** kèm nhãn nhỏ "Sắp ra mắt", không cho chọn — tránh tạo cảm giác giả (chọn xong nhưng không đổi gì). Đây là cách làm trung thực, nhất quán với hướng "Mức A" đã chọn cho màn Tiền tệ.

## 2. Fix Requirements

### 2.1. `pubspec.yaml` — thêm dependency + bật code generation

```yaml
dependencies:
  flutter_localizations:
    sdk: flutter
  # ... các dependency hiện có giữ nguyên

flutter:
  generate: true # MỚI — bật flutter gen-l10n
  uses-material-design: true
```

### 2.2. `l10n.yaml` (MỚI, đặt ở project root, ngang hàng `pubspec.yaml`)

```yaml
arb-dir: lib/l10n
template-arb-file: app_vi.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
```

### 2.3. `lib/l10n/app_vi.arb` và `lib/l10n/app_en.arb` (MỚI)

Trích toàn bộ chuỗi text hiển thị người dùng trong 5 màn Auth ra 2 file này (tiếng Việt = bản gốc hiện có, tiếng Anh = bản dịch tương ứng). Ví dụ cấu trúc (danh sách đầy đủ cần trích hết từ 5 file, đây chỉ là ví dụ minh họa key/format):

`lib/l10n/app_vi.arb`:
```json
{
  "@@locale": "vi",
  "appName": "Finance AI",
  "loginTitle": "Đăng nhập",
  "loginSubtitle": "Chào mừng bạn quay lại",
  "emailLabel": "Email",
  "passwordLabel": "Mật khẩu",
  "loginButton": "Đăng nhập",
  "loginWithGoogle": "Đăng nhập với Google",
  "noAccountYet": "Chưa có tài khoản? ",
  "registerNow": "Đăng ký ngay",
  "forgotPassword": "Quên mật khẩu?",
  "registerTitle": "Tạo tài khoản",
  "registerSubtitle": "Bắt đầu quản lý tài chính thông minh hơn",
  "fullNameLabel": "Họ và tên",
  "registerButton": "Đăng ký",
  "onboardingSkip": "Bỏ qua",
  "onboardingStart": "Bắt đầu",
  "onboardingNext": "Tiếp tục"
}
```

`lib/l10n/app_en.arb`:
```json
{
  "@@locale": "en",
  "appName": "Finance AI",
  "loginTitle": "Login",
  "loginSubtitle": "Welcome back",
  "emailLabel": "Email",
  "passwordLabel": "Password",
  "loginButton": "Login",
  "loginWithGoogle": "Sign in with Google",
  "noAccountYet": "Don't have an account? ",
  "registerNow": "Register now",
  "forgotPassword": "Forgot password?",
  "registerTitle": "Create account",
  "registerSubtitle": "Start managing your finances smarter",
  "fullNameLabel": "Full name",
  "registerButton": "Register",
  "onboardingSkip": "Skip",
  "onboardingStart": "Get started",
  "onboardingNext": "Next"
}
```

**Yêu cầu bắt buộc:** rà soát đầy đủ **toàn bộ** chuỗi text hiển thị người dùng trong cả 5 file (`splash_screen.dart`, `onboarding_screen.dart`, `login_screen.dart`, `register_screen.dart`, `forgot_password_screen.dart`) — bao gồm cả thông báo lỗi (`_errorMessage`), placeholder, validator message — không được bỏ sót chuỗi nào, thêm đủ key tương ứng vào cả 2 file `.arb`.

### 2.4. `lib/services/locale_controller.dart` (MỚI)

```dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================
/// LOCALE CONTROLLER
/// Quản lý ngôn ngữ hiển thị toàn app, tương tự ThemeController.
/// Lưu lựa chọn qua shared_preferences.
/// ============================================================
class LocaleController {
  static final ValueNotifier<Locale> locale = ValueNotifier(const Locale('vi'));
  static const _prefKey = 'app_locale';

  static Future<void> loadSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    locale.value = Locale(saved ?? 'vi');
  }

  static Future<void> setLocale(String languageCode) async {
    locale.value = Locale(languageCode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, languageCode);
  }
}
```

### 2.5. `lib/main.dart` — đăng ký localization delegates + kết hợp với `ThemeController` đã có (ticket 018)

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await ThemeController.loadSavedTheme();
  await LocaleController.loadSavedLocale(); // MỚI
  runApp(const FinanceAiApp());
}

class FinanceAiApp extends StatelessWidget {
  const FinanceAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) {
        return ValueListenableBuilder<Locale>(
          valueListenable: LocaleController.locale,
          builder: (context, locale, __) {
            return MaterialApp(
              title: AppStrings.appName,
              debugShowCheckedModeBanner: false,
              themeMode: mode,
              locale: locale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('vi'), Locale('en')],
              theme: /* giữ nguyên theme đã có ở ticket 018 */,
              darkTheme: /* giữ nguyên darkTheme đã có ở ticket 018 */,
              initialRoute: AppRoutes.splash,
              routes: AppRoutes.routes,
            );
          },
        );
      },
    );
  }
}
```

Thêm import:
```dart
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'services/locale_controller.dart';
```

### 2.6. Áp dụng vào 5 màn Auth — thay text hardcode bằng `AppLocalizations.of(context)!.xxx`

Ví dụ áp dụng cho `login_screen.dart`:
```dart
// Trước:
const Text('Đăng nhập', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),

// Sau:
Text(AppLocalizations.of(context)!.loginTitle,
    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
```
Thêm `import 'package:flutter_gen/gen_l10n/app_localizations.dart';` vào đầu mỗi trong 5 file. Áp dụng tương tự cho **toàn bộ** chuỗi text đã liệt kê trong `.arb` — không được sót câu nào trong 5 màn này.

### 2.7. `lib/screens/language_selection_screen.dart` (MỚI)

- AppBar: `"Ngôn ngữ hiển thị" / "Language"` (tự động theo locale hiện tại).
- Thanh tìm kiếm ở đầu — lọc danh sách theo tên ngôn ngữ (không phân biệt hoa/thường).
- Danh sách ~18-20 ngôn ngữ phổ biến, mỗi dòng gồm: cờ quốc gia (dùng ký tự emoji Unicode, VD 🇻🇳, 🇺🇸, 🇯🇵 — không cần thêm package/asset ảnh riêng), tên ngôn ngữ (bản địa + tiếng Việt), dấu tick nếu đang được chọn.
- **Sắp xếp A-Z** theo tên hiển thị.
- Chỉ 2 dòng **"Tiếng Việt"** và **"English"** ở trạng thái bật (tappable, chọn được). Các dòng còn lại hiển thị **mờ** (`opacity: 0.4`), có nhãn nhỏ "Sắp ra mắt"/"Coming soon", `onTap: null` (không phản hồi khi chạm).
- Chọn 1 trong 2 ngôn ngữ khả dụng → đánh dấu chọn tạm (chưa áp dụng ngay).
- Nút **"Áp dụng"** ở đáy màn (chỉ bật khi lựa chọn khác locale hiện tại) → gọi `LocaleController.setLocale(code)`, sau đó `Navigator.pop(context)`.

**Lưu ý giới hạn nền tảng:** cờ quốc gia dạng emoji có thể hiển thị không đúng (VD ra chữ viết tắt "US" thay vì hình cờ) trên 1 số nền tảng do giới hạn font hệ thống (đặc biệt Windows desktop) — đây là giới hạn nền tảng, không phải bug, không cần xử lý thêm trong ticket này.

### 2.8. `lib/screens/profile_screen.dart` — nối mục "Ngôn ngữ hiển thị" với màn mới

Thay placeholder `SnackBar` tạm (đã làm ở ticket 017) bằng điều hướng thật:
```dart
ValueListenableBuilder<Locale>(
  valueListenable: LocaleController.locale,
  builder: (context, locale, _) {
    return ListTile(
      leading: const Icon(Icons.language_outlined),
      title: const Text('Ngôn ngữ hiển thị'),
      trailing: Text(locale.languageCode == 'vi' ? 'Tiếng Việt' : 'English'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LanguageSelectionScreen()),
      ),
    );
  },
)
```

## 3. Không đổi (Out of scope)

- Không dịch các module khác (Setup, Home, Management, AI, Notification, Profile) — để dành cho các ticket Giai đoạn 2+ riêng biệt, mỗi ticket 1 module.
- Không làm cho các ngôn ngữ ngoài Việt/Anh hoạt động thật — chỉ hiển thị trong danh sách ở trạng thái "Sắp ra mắt".
- Không thêm package quản lý cờ quốc gia dạng ảnh — dùng emoji Unicode.
- Không đổi cấu trúc `AppRoutes`, không đổi logic `AuthService`/`FirestoreService` trong 5 màn Auth — chỉ thay chuỗi text hiển thị bằng `AppLocalizations`.

## 4. Acceptance Criteria

- [ ] `flutter pub get` sau khi thêm `flutter_localizations` + `generate: true` chạy thành công, sinh ra `AppLocalizations` không lỗi.
- [ ] Vào Profile → "Ngôn ngữ hiển thị" → mở đúng màn chọn ngôn ngữ, có tìm kiếm, sắp xếp A-Z, cờ quốc gia hiển thị.
- [ ] Gõ tìm kiếm (VD "eng") → lọc đúng ra "English".
- [ ] Bấm vào 1 ngôn ngữ "Sắp ra mắt" → không có phản hồi, không crash.
- [ ] Chọn "English" → bấm "Áp dụng" → quay lại, **toàn bộ 5 màn Auth** (thử bằng cách đăng xuất rồi xem lại Splash/Onboarding/Login/Register/Forgot Password) hiển thị đúng tiếng Anh.
- [ ] Chọn lại "Tiếng Việt" → toàn bộ 5 màn Auth trở về tiếng Việt như cũ.
- [ ] Tắt app, mở lại → giữ đúng ngôn ngữ đã chọn lần trước.
- [ ] Các màn khác ngoài Auth (Dashboard, Profile...) vẫn hiển thị tiếng Việt bình thường dù đã chọn English cho Auth (đúng phạm vi Giai đoạn 1, chưa dịch các module đó) — không bị lỗi/thiếu chữ (missing translation) ở các màn chưa dịch.
- [ ] `flutter analyze` không phát sinh lỗi mới.
