import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/quick_template.dart';

class TemplateService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Create a new quick template for the current user.
  Future<String> createTemplate({
    required String title,
    required double amount,
    required String type,
    required String walletId,
    required String categoryId,
    String note = '',
    String location = '',
    DateTime? date,
    String? imagePath,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('User not authenticated');
    final doc = await _db
        .collection('users')
        .doc(uid)
        .collection('quickTemplates')
        .add({
      'title': title,
      'amount': amount,
      'type': type,
      'walletId': walletId,
      'categoryId': categoryId,
      'note': note,
      'location': location,
      'date': (date ?? DateTime.now()).toIso8601String(),
      if (imagePath != null) 'imagePath': imagePath,
    });
    return doc.id;
  }

  /// Stream all templates belonging to the current user.
  Stream<List<QuickTemplate>> streamUserTemplates() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    return _db
        .collection('users')
        .doc(uid)
        .collection('quickTemplates')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => QuickTemplate.fromMap(d.data(), d.id))
            .toList());
  }
}
