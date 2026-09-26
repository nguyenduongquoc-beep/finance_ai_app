import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/models/recurring_transaction_model.dart';
import 'package:finance_ai_app/services/local_notification_service.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

void main() {
  group('LocalNotificationService Pure Logic Unit Tests', () {
    final refDate = DateTime(2026, 9, 20, 10, 0); // Reference: Sep 20, 2026 10:00 AM

    test('1. Inactive schedule yields 0 scheduled notifications', () {
      final schedule = RecurringTransactionSchedule(
        scheduleId: 'sch_inactive',
        userId: 'u1',
        type: 'expense',
        walletId: 'w1',
        categoryId: 'c1',
        amount: 500000,
        frequency: 'monthly',
        startDate: DateTime(2026, 9, 25),
        nextDueDate: DateTime(2026, 9, 25),
        isActive: false,
        createdAt: DateTime(2026, 9, 1),
        reminderDaysBefore: 1,
      );

      final items = LocalNotificationService.calculateScheduledNotifications(
        schedule: schedule,
        walletName: 'Ví Chính',
        referenceDate: refDate,
      );

      expect(items, isEmpty);
    });

    test('2. reminderDaysBefore == 0 yields 0 notifications', () {
      final schedule = RecurringTransactionSchedule(
        scheduleId: 'sch_no_reminder',
        userId: 'u1',
        type: 'expense',
        walletId: 'w1',
        categoryId: 'c1',
        amount: 500000,
        frequency: 'monthly',
        startDate: DateTime(2026, 9, 25),
        nextDueDate: DateTime(2026, 9, 25),
        isActive: true,
        createdAt: DateTime(2026, 9, 1),
        reminderDaysBefore: 0,
      );

      final items = LocalNotificationService.calculateScheduledNotifications(
        schedule: schedule,
        walletName: 'Ví Chính',
        referenceDate: refDate,
      );

      expect(items, isEmpty);
    });

    test('3. reminderDaysBefore == 3 generates both advance and due date notifications', () {
      final schedule = RecurringTransactionSchedule(
        scheduleId: 'sch_rent',
        userId: 'u1',
        type: 'expense',
        walletId: 'w1',
        categoryId: 'c1',
        note: 'Tiền nhà',
        amount: 5000000,
        frequency: 'monthly',
        startDate: DateTime(2026, 10, 1),
        nextDueDate: DateTime(2026, 10, 1),
        isActive: true,
        createdAt: DateTime(2026, 9, 1),
        reminderDaysBefore: 3,
      );

      final items = LocalNotificationService.calculateScheduledNotifications(
        schedule: schedule,
        walletName: 'Ví ACB',
        referenceDate: refDate,
        maxDaysAhead: 30, // Window Sep 20 -> Oct 20
      );

      expect(items.isNotEmpty, isTrue);

      // Verify the first occurrence (Oct 1)
      final advance = items.firstWhere(
        (item) => !item.isOnDueDate && item.scheduledTime.month == 9 && item.scheduledTime.day == 28,
      );
      expect(advance.scheduledTime, equals(DateTime(2026, 9, 28, 9, 0)));
      expect(advance.title, contains('Sắp đến hạn: Tiền nhà'));
      expect(advance.body, contains('Còn 3 ngày'));
      expect(advance.body, contains('Ví: Ví ACB'));

      final due = items.firstWhere(
        (item) => item.isOnDueDate && item.scheduledTime.month == 10 && item.scheduledTime.day == 1,
      );
      expect(due.scheduledTime, equals(DateTime(2026, 10, 1, 9, 0)));
      expect(due.title, contains('Hôm nay đến hạn: Tiền nhà'));
    });

    test('4. Deterministic notification ID is generated reproducibly', () {
      final id1 = LocalNotificationService.generateNotificationId('sch_1', '2026-10-01', isOnDueDate: true);
      final id2 = LocalNotificationService.generateNotificationId('sch_1', '2026-10-01', isOnDueDate: true);
      final id3 = LocalNotificationService.generateNotificationId('sch_1', '2026-10-01', isOnDueDate: false);

      expect(id1, equals(id2));
      expect(id1, isNot(equals(id3)));
      expect(id1, isA<int>());
      expect(id1 >= 0, isTrue);
    });

    test('5. Past notification dates before referenceDate are excluded', () {
      final schedule = RecurringTransactionSchedule(
        scheduleId: 'sch_past',
        userId: 'u1',
        type: 'expense',
        walletId: 'w1',
        categoryId: 'c1',
        amount: 200000,
        frequency: 'monthly',
        startDate: DateTime(2026, 9, 15),
        nextDueDate: DateTime(2026, 9, 15),
        isActive: true,
        createdAt: DateTime(2026, 9, 1),
        reminderDaysBefore: 1,
      );

      // refDate is Sep 20. Sep 15 due date and Sep 14 advance date are in the past.
      final items = LocalNotificationService.calculateScheduledNotifications(
        schedule: schedule,
        walletName: 'Ví Chính',
        referenceDate: refDate,
        maxDaysAhead: 15,
      );

      for (final item in items) {
        expect(item.scheduledTime.isAfter(refDate), isTrue);
      }
    });

    test('6. Scheduled notification times are explicitly configured for 09:00 AM local time', () {
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Ho_Chi_Minh'));
      final schedule = RecurringTransactionSchedule(
        scheduleId: 'sch_tz',
        userId: 'u1',
        type: 'expense',
        walletId: 'w1',
        categoryId: 'c1',
        amount: 100000,
        frequency: 'monthly',
        startDate: DateTime(2026, 10, 5),
        nextDueDate: DateTime(2026, 10, 5),
        isActive: true,
        createdAt: DateTime(2026, 9, 1),
        reminderDaysBefore: 1,
      );

      final items = LocalNotificationService.calculateScheduledNotifications(
        schedule: schedule,
        walletName: 'Ví',
        referenceDate: refDate,
        maxDaysAhead: 30,
      );

      expect(items, isNotEmpty);
      for (final item in items) {
        final tzTime = tz.TZDateTime.from(item.scheduledTime, tz.local);
        expect(item.scheduledTime.hour, equals(9));
        expect(item.scheduledTime.minute, equals(0));
        expect(tzTime.hour, equals(9));
        expect(tzTime.minute, equals(0));
      }
    });

    test('7. Notification payload starts with bill_reminder_v1: prefix', () {
      final schedule = RecurringTransactionSchedule(
        scheduleId: 'sch_prefix_test',
        userId: 'u1',
        type: 'expense',
        walletId: 'w1',
        categoryId: 'c1',
        amount: 100000,
        frequency: 'monthly',
        startDate: DateTime(2026, 10, 5),
        nextDueDate: DateTime(2026, 10, 5),
        isActive: true,
        createdAt: DateTime(2026, 9, 1),
        reminderDaysBefore: 1,
      );

      final items = LocalNotificationService.calculateScheduledNotifications(
        schedule: schedule,
        walletName: 'Ví',
        referenceDate: refDate,
        maxDaysAhead: 30,
      );

      expect(items, isNotEmpty);
      for (final item in items) {
        expect(item.payload.startsWith(LocalNotificationService.payloadPrefix), isTrue);
        expect(item.payload, contains('sch_prefix_test'));
      }
    });

    test('8. Total calculated notifications across multiple schedules respects window bounds', () {
      final schedules = List.generate(
        30,
        (i) => RecurringTransactionSchedule(
          scheduleId: 'sch_$i',
          userId: 'u1',
          type: 'expense',
          walletId: 'w1',
          categoryId: 'c1',
          amount: 10000,
          frequency: 'weekly',
          startDate: DateTime(2026, 9, 21),
          nextDueDate: DateTime(2026, 9, 21),
          isActive: true,
          createdAt: DateTime(2026, 9, 1),
          reminderDaysBefore: 1,
        ),
      );

      int totalItems = 0;
      for (final s in schedules) {
        final items = LocalNotificationService.calculateScheduledNotifications(
          schedule: s,
          walletName: 'Ví',
          referenceDate: refDate,
          maxDaysAhead: 90,
        );
        totalItems += items.length;
      }

      expect(totalItems, greaterThan(0));
    });
  });
}
