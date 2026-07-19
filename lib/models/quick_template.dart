import 'package:cloud_firestore/cloud_firestore.dart';

class QuickTemplate {
  final String id;
  final String title; // e.g. "Cà phê sáng"
  final double amount;
  final String type; // 'income' or 'expense'
  final String walletId;
  final String categoryId;
  final String note;
  final String location;
  final DateTime date;
  final String? imagePath; // optional local path or URL

  QuickTemplate({
    required this.id,
    required this.title,
    required this.amount,
    required this.type,
    required this.walletId,
    required this.categoryId,
    required this.note,
    required this.location,
    required this.date,
    this.imagePath,
  });

  factory QuickTemplate.fromMap(Map<String, dynamic> map, String docId) {
    return QuickTemplate(
      id: docId,
      title: map['title'] as String,
      amount: (map['amount'] as num).toDouble(),
      type: map['type'] as String,
      walletId: map['walletId'] as String,
      categoryId: map['categoryId'] as String,
      note: map['note'] as String? ?? '',
      location: map['location'] as String? ?? '',
      date: DateTime.parse(map['date'] as String),
      imagePath: map['imagePath'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'amount': amount,
      'type': type,
      'walletId': walletId,
      'categoryId': categoryId,
      'note': note,
      'location': location,
      'date': date.toIso8601String(),
      if (imagePath != null) 'imagePath': imagePath,
    };
  }
}
