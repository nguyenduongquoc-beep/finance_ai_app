// File này là PLACEHOLDER.
//
// Sau khi tạo project Firebase, hãy chạy lệnh sau tại thư mục gốc dự án
// để FlutterFire CLI tự động sinh file firebase_options.dart thật:
//
//   flutterfire configure
//
// Lệnh này sẽ:
// 1. Hỏi bạn chọn Firebase project (hoặc tạo mới)
// 2. Hỏi bạn chọn nền tảng (Android/iOS/Web)
// 3. Tự động ghi đè file này với cấu hình thật (apiKey, appId, projectId...)
//
// KHÔNG chỉnh sửa thủ công file này sau khi đã chạy flutterfire configure.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions chưa hỗ trợ nền tảng này. '
          'Chạy `flutterfire configure` để sinh cấu hình.',
        );
    }
  }

  // TODO: Thay thế bằng giá trị thật sau khi chạy `flutterfire configure`

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBauEJq_yx-se3xUrcO63HcTvwbKPQ8-w0',
    appId: '1:290574068185:android:aaa0364c13c5e4bc6711c8',
    messagingSenderId: '290574068185',
    projectId: 'finance-ai-app-6df28',
    storageBucket: 'finance-ai-app-6df28.firebasestorage.app',
  );
  // TODO: Thay thế bằng giá trị thật sau khi chạy `flutterfire configure`

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCOIVZSyvHFjNgbD-k7sUAUuSEXxY_dMxM',
    appId: '1:290574068185:ios:8ae851e4e126a9e46711c8',
    messagingSenderId: '290574068185',
    projectId: 'finance-ai-app-6df28',
    storageBucket: 'finance-ai-app-6df28.firebasestorage.app',
    iosBundleId: 'com.example.financeAiApp',
  );
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBj4Bedx0xkZ1lJ3YxEu7SWM5Ad6ovTGQ4',
    appId: '1:290574068185:web:840c2caeba9665b86711c8',
    messagingSenderId: '290574068185',
    projectId: 'finance-ai-app-6df28',
    authDomain: 'finance-ai-app-6df28.firebaseapp.com',
    storageBucket: 'finance-ai-app-6df28.firebasestorage.app',
  );
}
