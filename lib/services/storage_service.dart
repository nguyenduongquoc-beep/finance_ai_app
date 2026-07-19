import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

/// ============================================================
/// STORAGE SERVICE
/// Upload ảnh hóa đơn giao dịch, avatar người dùng lên Firebase Storage
/// ============================================================
class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Upload ảnh hóa đơn giao dịch
  /// Đường dẫn: receipts/{userId}/{timestamp}.jpg
  Future<String> uploadReceiptImage(String userId, File imageFile) async {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _storage.ref().child('receipts/$userId/$fileName');
    final task = await ref.putFile(imageFile);
    return task.ref.getDownloadURL();
  }

  /// Upload avatar người dùng
  /// Đường dẫn: avatars/{userId}.jpg
  Future<String> uploadAvatar(String userId, File imageFile) async {
    final ref = _storage.ref().child('avatars/$userId.jpg');
    final task = await ref.putFile(imageFile);
    return task.ref.getDownloadURL();
  }

  /// Xóa ảnh theo URL
  Future<void> deleteImageByUrl(String url) async {
    final ref = _storage.refFromURL(url);
    await ref.delete();
  }
}
