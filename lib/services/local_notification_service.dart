import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/recurring_transaction_model.dart';
import '../routes/app_routes.dart';
import '../screens/management/recurring_transaction_screen.dart';
import '../utils/formatters.dart';
import 'recurring_transaction_service.dart';

/// Item mô tả 1 thông báo cục bộ cần lên lịch (dùng cho cả test & production)
class ScheduledNotificationItem {
  final int notificationId;
  final String scheduleId;
  final DateTime scheduledTime;
  final String title;
  final String body;
  final String payload;
  final bool isOnDueDate;

  ScheduledNotificationItem({
    required this.notificationId,
    required this.scheduleId,
    required this.scheduledTime,
    required this.title,
    required this.body,
    required this.payload,
    required this.isOnDueDate,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduledNotificationItem &&
          runtimeType == other.runtimeType &&
          notificationId == other.notificationId &&
          scheduleId == other.scheduleId &&
          scheduledTime == other.scheduledTime;

  @override
  int get hashCode =>
      notificationId.hashCode ^ scheduleId.hashCode ^ scheduledTime.hashCode;
}

/// ============================================================
/// LOCAL NOTIFICATION SERVICE
/// Quản lý thông báo cục bộ cho Giao dịch định kỳ & Hóa đơn
/// ============================================================
class LocalNotificationService {
  static final LocalNotificationService _instance =
      LocalNotificationService._internal();
  factory LocalNotificationService() => _instance;
  LocalNotificationService._internal();

  static const String payloadPrefix = 'bill_reminder_v1:';

  FlutterLocalNotificationsPlugin? _plugin;
  bool _isInitialized = false;

  /// Khởi tạo plugin & cấu hình Timezone thực tế từ thiết bị
  Future<void> initialize({FlutterLocalNotificationsPlugin? plugin}) async {
    if (_isInitialized && plugin == null) return;

    tz.initializeTimeZones();
    try {
      final String timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      debugPrint('[NotificationService] Configured timezone: $timeZoneName');
    } catch (e) {
      debugPrint('[NotificationService] Error fetching device timezone: $e');
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));
      } catch (_) {}
    }

    _plugin = plugin ?? FlutterLocalNotificationsPlugin();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin?.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null && response.payload!.isNotEmpty) {
          handleNotificationPayload(response.payload!);
        }
      },
    );

    _isInitialized = true;
  }

  /// Xin quyền Notification trên Android 13+ và iOS (chỉ xin nếu chưa được cấp)
  Future<bool> requestPermission() async {
    if (_plugin == null) return false;

    final androidImplementation =
        _plugin!.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      final areEnabled = await androidImplementation.areNotificationsEnabled();
      if (areEnabled == true) {
        return true;
      }
      final granted =
          await androidImplementation.requestNotificationsPermission();
      return granted ?? false;
    }

    final iosImplementation = _plugin!.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (iosImplementation != null) {
      final granted = await iosImplementation.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    return true;
  }

  /// Xử lý điều hướng khi bấm vào thông báo
  static void handleNotificationPayload(String rawPayload) {
    try {
      String payload = rawPayload;
      if (payload.startsWith(payloadPrefix)) {
        payload = payload.substring(payloadPrefix.length);
      }
      String scheduleId = payload;
      if (payload.startsWith('{')) {
        final map = jsonDecode(payload) as Map<String, dynamic>;
        scheduleId = map['scheduleId'] ?? payload;
      }

      if (scheduleId.isNotEmpty && AppRoutes.navigatorKey.currentState != null) {
        AppRoutes.navigatorKey.currentState!.push(
          MaterialPageRoute(
            builder: (_) =>
                RecurringTransactionScreen(targetScheduleId: scheduleId),
          ),
        );
      }
    } catch (e) {
      debugPrint('[NotificationService] Error handling payload: $e');
    }
  }

  /// Tính toán ID thông báo deterministic từ scheduleId và occurrenceKey
  static int generateNotificationId(String scheduleId, String occurrenceKey,
      {required bool isOnDueDate}) {
    final input =
        '$scheduleId#$occurrenceKey#${isOnDueDate ? 'due' : 'advance'}';
    int hash = 0;
    for (int i = 0; i < input.length; i++) {
      hash = (hash * 31 + input.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return hash;
  }

  /// Logic thuần Dart: Tính toán các thông báo cần lên lịch trong 90 ngày tới
  static List<ScheduledNotificationItem> calculateScheduledNotifications({
    required RecurringTransactionSchedule schedule,
    String? walletName,
    DateTime? referenceDate,
    int maxDaysAhead = 90,
  }) {
    if (!schedule.isActive || schedule.reminderDaysBefore == 0) {
      return [];
    }

    final now = referenceDate ?? DateTime.now();
    final recService = RecurringTransactionService();
    final List<ScheduledNotificationItem> items = [];

    // Tính toán các kỳ lặp trong 90 ngày tới
    final occurrences = recService.nextOccurrencesInWindow(
      schedule: schedule,
      referenceDate: now,
      daysAhead: maxDaysAhead,
    );

    final String displayName = (schedule.note != null &&
            schedule.note!.trim().isNotEmpty)
        ? schedule.note!.trim()
        : (schedule.type == 'income' ? 'Thu nhập định kỳ' : 'Hóa đơn định kỳ');
    final String isTypeLabel = schedule.type == 'income' ? 'Thu nhập' : 'Chi tiêu';
    final String walletText = walletName ?? 'Ví';
    final String formattedAmount = AppFormatters.number(schedule.amount);

    for (final date in occurrences) {
      final occurrenceKey = RecurringTransactionService.getOccurrenceKey(date);
      final payload = '$payloadPrefix${jsonEncode({'scheduleId': schedule.scheduleId})}';

      // 1. Thông báo trước hạn (nếu reminderDaysBefore > 0)
      if (schedule.reminderDaysBefore > 0) {
        final advanceDate = DateTime(
          date.year,
          date.month,
          date.day - schedule.reminderDaysBefore,
          9, // 09:00 sáng
          0,
        );

        if (advanceDate.isAfter(now)) {
          final advanceId = generateNotificationId(
              schedule.scheduleId, occurrenceKey,
              isOnDueDate: false);
          items.add(ScheduledNotificationItem(
            notificationId: advanceId,
            scheduleId: schedule.scheduleId,
            scheduledTime: advanceDate,
            title: 'Sắp đến hạn: $displayName',
            body:
                '$isTypeLabel: ${formattedAmount}đ • Ví: $walletText • Còn ${schedule.reminderDaysBefore} ngày',
            payload: payload,
            isOnDueDate: false,
          ));
        }
      }

      // 2. Thông báo đúng ngày đến hạn
      final dueDateNotificationTime = DateTime(
        date.year,
        date.month,
        date.day,
        9, // 09:00 sáng
        0,
      );

      if (dueDateNotificationTime.isAfter(now)) {
        final dueId = generateNotificationId(
            schedule.scheduleId, occurrenceKey,
            isOnDueDate: true);
        items.add(ScheduledNotificationItem(
          notificationId: dueId,
          scheduleId: schedule.scheduleId,
          scheduledTime: dueDateNotificationTime,
          title: 'Hôm nay đến hạn: $displayName',
          body: '$isTypeLabel: ${formattedAmount}đ • Ví: $walletText',
          payload: payload,
          isOnDueDate: true,
        ));
      }
    }

    return items;
  }

  /// Lên lịch thông báo trên thiết bị cho 1 lịch định kỳ
  Future<void> scheduleRemindersForSchedule({
    required RecurringTransactionSchedule schedule,
    String? walletName,
    DateTime? referenceDate,
  }) async {
    if (_plugin == null || !_isInitialized) return;

    // Hủy các thông báo cũ trước khi lên lịch lại
    await cancelRemindersForSchedule(schedule.scheduleId);

    if (!schedule.isActive || schedule.reminderDaysBefore == 0) return;

    final items = calculateScheduledNotifications(
      schedule: schedule,
      walletName: walletName,
      referenceDate: referenceDate,
    );

    const androidDetails = AndroidNotificationDetails(
      'recurring_bill_channel',
      'Nhắc nhở hóa đơn & Giao dịch định kỳ',
      channelDescription:
          'Thông báo nhắc nhở khi đến hạn các khoản thu chi định kỳ',
      importance: Importance.high,
      priority: Priority.high,
    );
    const notificationDetails =
        NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails());

    for (final item in items) {
      try {
        final tzScheduledTime = tz.TZDateTime.from(item.scheduledTime, tz.local);
        await _plugin!.zonedSchedule(
          item.notificationId,
          item.title,
          item.body,
          tzScheduledTime,
          notificationDetails,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: item.payload,
        );
      } catch (e) {
        debugPrint(
            '[NotificationService] Error scheduling notification ${item.notificationId}: $e');
      }
    }
  }

  /// Hủy các thông báo liên quan đến 1 scheduleId (chỉ hủy notification thuộc Bill Reminder)
  Future<void> cancelRemindersForSchedule(String scheduleId) async {
    if (_plugin == null || !_isInitialized) return;

    final pending = await _plugin!.pendingNotificationRequests();
    for (final req in pending) {
      if (req.payload != null &&
          req.payload!.startsWith(payloadPrefix) &&
          req.payload!.contains(scheduleId)) {
        await _plugin!.cancel(req.id);
      }
    }
  }

  /// Đồng bộ toàn bộ thông báo cho danh sách tất cả các lịch lặp của user (tối đa 50)
  Future<void> syncAllReminders({
    required List<RecurringTransactionSchedule> schedules,
    required Map<String, String> walletNamesMap,
    DateTime? referenceDate,
  }) async {
    if (_plugin == null || !_isInitialized) return;

    // Hủy các thông báo lặp cũ của Bill Reminder (dựa vào payloadPrefix)
    final pending = await _plugin!.pendingNotificationRequests();
    for (final req in pending) {
      if (req.payload != null && req.payload!.startsWith(payloadPrefix)) {
        await _plugin!.cancel(req.id);
      }
    }

    int scheduledCount = 0;
    const int maxTotalNotifications = 50; // Giới hạn tổng số thông báo

    for (final schedule in schedules) {
      if (scheduledCount >= maxTotalNotifications) break;
      if (!schedule.isActive || schedule.reminderDaysBefore == 0) continue;

      final walletName = walletNamesMap[schedule.walletId];
      final items = calculateScheduledNotifications(
        schedule: schedule,
        walletName: walletName,
        referenceDate: referenceDate,
      );

      const androidDetails = AndroidNotificationDetails(
        'recurring_bill_channel',
        'Nhắc nhở hóa đơn & Giao dịch định kỳ',
        channelDescription:
            'Thông báo nhắc nhở khi đến hạn các khoản thu chi định kỳ',
        importance: Importance.high,
        priority: Priority.high,
      );
      const notificationDetails = NotificationDetails(
          android: androidDetails, iOS: DarwinNotificationDetails());

      for (final item in items) {
        if (scheduledCount >= maxTotalNotifications) break;

        try {
          final tzScheduledTime =
              tz.TZDateTime.from(item.scheduledTime, tz.local);
          await _plugin!.zonedSchedule(
            item.notificationId,
            item.title,
            item.body,
            tzScheduledTime,
            notificationDetails,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: item.payload,
          );
          scheduledCount++;
        } catch (e) {
          debugPrint(
              '[NotificationService] Error scheduling notification ${item.notificationId}: $e');
        }
      }
    }
  }
}
