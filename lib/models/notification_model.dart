/// ============================================================
/// NOTIFICATION MODEL
/// Firestore collection: notifications/{notificationId}
/// ============================================================
class AppNotification {
  final String notificationId;
  final String userId;
  final String title;
  final String content;
  final String status; // read | unread
  final String type; // budget | reminder | ai_insight
  final DateTime createdAt;

  AppNotification({
    required this.notificationId,
    required this.userId,
    required this.title,
    required this.content,
    this.status = 'unread',
    this.type = 'reminder',
    required this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map, String id) {
    return AppNotification(
      notificationId: id,
      userId: map['userId'] ?? '',
      title: map['title'] ?? '',
      content: map['content'] ?? '',
      status: map['status'] ?? 'unread',
      type: map['type'] ?? 'reminder',
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'title': title,
      'content': content,
      'status': status,
      'type': type,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
