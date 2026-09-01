import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/notification_model.dart';
import '../services/firestore_service.dart';
import '../services/theme_controller.dart';
import '../utils/constants.dart';
import '../widgets/stream_error_widget.dart';

/// 20. Notification - Danh sách thông báo (vượt ngân sách, nhắc hóa đơn, AI Insight)
class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  IconData _iconForType(String type) {
    switch (type) {
      case 'budget':
        return Icons.warning_amber_rounded;
      case 'ai_insight':
        return Icons.auto_awesome;
      default:
        return Icons.notifications_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, _, __) {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        final firestoreService = FirestoreService();

        return Scaffold(
          backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Thông báo')),
      body: StreamBuilder<List<AppNotification>>(
        stream: firestoreService.streamNotifications(uid),
        builder: (context, snap) {
          if (snap.hasError) return StreamErrorWidget(error: snap.error.toString());
          final notifications = snap.data ?? [];
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          if (notifications.isEmpty) {
            return Center(
              child: Text('Không có thông báo nào', style: TextStyle(color: AppColors.textSecondary)),
            );
          }
          return ListView.builder(
            itemCount: notifications.length,
            itemBuilder: (context, i) {
              final n = notifications[i];
              return ListTile(
                onTap: () => firestoreService.markNotificationRead(n.notificationId),
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withOpacity(0.12),
                  child: Icon(_iconForType(n.type), color: AppColors.primary),
                ),
                title: Text(n.title,
                    style: TextStyle(
                        fontWeight: n.status == 'unread' ? FontWeight.bold : FontWeight.normal)),
                subtitle: Text(n.content),
                trailing: n.status == 'unread'
                    ? Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: AppColors.expense, shape: BoxShape.circle),
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  },
);
  }
}
