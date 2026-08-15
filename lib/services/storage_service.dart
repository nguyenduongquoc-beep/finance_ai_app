import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// ============================================================
/// STORAGE SERVICE
/// Upload ảnh hóa đơn giao dịch, avatar người dùng lên Firebase Storage
/// ============================================================
class StorageService {

  /// Upload ảnh hóa đơn giao dịch
  /// Đường dẫn: receipts/{userId}/{timestamp}.jpg
  Future<String> uploadReceiptImage(String userId, Uint8List imageBytes) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final receiptsDir = Directory('${docsDir.path}/receipts');
    if (!await receiptsDir.exists()) {
      await receiptsDir.create(recursive: true);
    }
    final fileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final file = File('${receiptsDir.path}/${fileName}');
    await file.writeAsBytes(imageBytes);
    return file.path;
  }

  /// Upload avatar người dùng
  /// Đường dẫn: avatars/{userId}.jpg
  Future<String> uploadAvatar(String userId, File imageFile) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final avatarsDir = Directory('${docsDir.path}/avatars');
    if (!await avatarsDir.exists()) {
      await avatarsDir.create(recursive: true);
    }
    final destFile = File('${avatarsDir.path}/${userId}.jpg');
    await imageFile.copy(destFile.path);
    return destFile.path;
  }

  /// Xóa ảnh theo URL
  Future<void> deleteImageByUrl(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      // Ignored errors during deletion
    }
  }
}
