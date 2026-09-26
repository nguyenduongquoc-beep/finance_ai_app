import '../models/recurring_transaction_model.dart';

/// Lớp hỗ trợ chứa 1 kỳ sắp tới của 1 schedule
class UpcomingOccurrence {
  final RecurringTransactionSchedule schedule;
  final DateTime dueDate;

  const UpcomingOccurrence({
    required this.schedule,
    required this.dueDate,
  });
}

/// Kết quả tổng hợp thu/chi định kỳ còn lại trong phần cuối tháng
class PlannedRemainingAmounts {
  final double plannedRemainingIncome;
  final double plannedRemainingExpense;

  const PlannedRemainingAmounts({
    required this.plannedRemainingIncome,
    required this.plannedRemainingExpense,
  });
}

/// ============================================================
/// RECURRING TRANSACTION SERVICE (DART THUẦN — KHÔNG IMPORT FIREBASE)
/// ============================================================
class RecurringTransactionService {
  /// Sinh khóa kỳ hạn từ DateTime (VD: "2026-09-30")
  static String getOccurrenceKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Sinh document ID xác định cho transaction lặp: `recurring_{scheduleId}_{occurrenceKey}`
  static String buildTransactionId(String scheduleId, DateTime occurrenceDate) {
    final key = getOccurrenceKey(occurrenceDate);
    return 'recurring_${scheduleId}_$key';
  }

  /// Tính ngày đến hạn tiếp theo strictly sau [fromDate]
  DateTime nextOccurrenceAfter(
      DateTime fromDate, String frequency, DateTime startDate) {
    if (frequency == 'weekly') {
      var nextDate = DateTime(fromDate.year, fromDate.month, fromDate.day + 1);
      while (nextDate.weekday != startDate.weekday) {
        nextDate = nextDate.add(const Duration(days: 1));
      }
      return DateTime(
        nextDate.year,
        nextDate.month,
        nextDate.day,
        startDate.hour,
        startDate.minute,
        startDate.second,
      );
    } else {
      // Monthly recurrence
      int targetYear = fromDate.year;
      int targetMonth = fromDate.month + 1;
      if (targetMonth > 12) {
        targetYear++;
        targetMonth = 1;
      }

      while (true) {
        final lastDayOfTargetMonth =
            DateTime(targetYear, targetMonth + 1, 0).day;
        final targetDay = startDate.day.clamp(1, lastDayOfTargetMonth);
        final candidate = DateTime(
          targetYear,
          targetMonth,
          targetDay,
          startDate.hour,
          startDate.minute,
          startDate.second,
        );

        if (candidate.isAfter(fromDate)) {
          return candidate;
        }

        targetMonth++;
        if (targetMonth > 12) {
          targetYear++;
          targetMonth = 1;
        }
      }
    }
  }

  /// Trả về danh sách các kỳ đến hạn <= [referenceDate] từ nextDueDate của schedule
  List<DateTime> dueOccurrences({
    required RecurringTransactionSchedule schedule,
    required DateTime referenceDate,
    int catchUpCap = 12,
  }) {
    if (!schedule.isActive) return [];

    final results = <DateTime>[];
    var current = schedule.nextDueDate;

    // So sánh theo mốc thời gian / ngày
    while (!current.isAfter(referenceDate) && results.length < catchUpCap) {
      results.add(current);
      final next =
          nextOccurrenceAfter(current, schedule.frequency, schedule.startDate);
      if (!next.isAfter(current)) break; // Safety against infinite loop
      current = next;
    }

    return results;
  }

  /// Trả về danh sách ngày đến hạn của 1 schedule trong khoảng N ngày tới (từ today đến today + daysAhead)
  List<DateTime> nextOccurrencesInWindow({
    required RecurringTransactionSchedule schedule,
    required DateTime referenceDate,
    required int daysAhead,
  }) {
    if (!schedule.isActive) return [];

    final results = <DateTime>[];
    final windowStart = DateTime(
        referenceDate.year, referenceDate.month, referenceDate.day);
    final windowEnd = DateTime(referenceDate.year, referenceDate.month,
        referenceDate.day + daysAhead, 23, 59, 59);

    var current = schedule.nextDueDate;
    while (current.isBefore(windowStart)) {
      final next =
          nextOccurrenceAfter(current, schedule.frequency, schedule.startDate);
      if (!next.isAfter(current)) break;
      current = next;
    }

    while (!current.isAfter(windowEnd)) {
      results.add(current);
      final next =
          nextOccurrenceAfter(current, schedule.frequency, schedule.startDate);
      if (!next.isAfter(current)) break;
      current = next;
    }

    return results;
  }

  /// Trả về các kỳ sắp đến hạn từ (referenceDate + 1 ngày) tới (referenceDate + daysAhead)
  List<UpcomingOccurrence> upcomingOccurrences({
    required List<RecurringTransactionSchedule> schedules,
    required DateTime referenceDate,
    required int daysAhead,
  }) {
    final results = <UpcomingOccurrence>[];
    final windowStart = DateTime(
        referenceDate.year, referenceDate.month, referenceDate.day + 1);
    final windowEnd = DateTime(referenceDate.year, referenceDate.month,
        referenceDate.day + daysAhead, 23, 59, 59);

    for (final schedule in schedules.where((s) => s.isActive)) {
      var current = schedule.nextDueDate;
      // Advance to window or referenceDate
      while (current.isBefore(windowStart)) {
        current = nextOccurrenceAfter(
            current, schedule.frequency, schedule.startDate);
      }

      while (!current.isAfter(windowEnd)) {
        results.add(UpcomingOccurrence(schedule: schedule, dueDate: current));
        current = nextOccurrenceAfter(
            current, schedule.frequency, schedule.startDate);
      }
    }

    results.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return results;
  }

  /// Tính tổng thu/chi định kỳ còn lại trong phần cuối tháng hiện tại
  /// CHỈ TÍNH CÁC KỲ CHƯA PHÁT SINH VÀ CÓ NGÀY ĐẾN HẠN > referenceDate (từ ngày mai đến cuối tháng)
  PlannedRemainingAmounts computePlannedRemainingAmounts({
    required List<RecurringTransactionSchedule> schedules,
    required DateTime referenceDate,
  }) {
    double plannedIncome = 0;
    double plannedExpense = 0;

    final windowStart = DateTime(
        referenceDate.year, referenceDate.month, referenceDate.day + 1);
    final monthEnd =
        DateTime(referenceDate.year, referenceDate.month + 1, 0, 23, 59, 59);

    if (windowStart.isAfter(monthEnd)) {
      return const PlannedRemainingAmounts(
        plannedRemainingIncome: 0,
        plannedRemainingExpense: 0,
      );
    }

    for (final schedule in schedules.where((s) => s.isActive)) {
      var current = schedule.nextDueDate;
      // Skip overdue / past occurrences
      while (current.isBefore(windowStart)) {
        current = nextOccurrenceAfter(
            current, schedule.frequency, schedule.startDate);
      }

      while (!current.isAfter(monthEnd)) {
        if (schedule.type == 'income') {
          plannedIncome += schedule.amount;
        } else if (schedule.type == 'expense') {
          plannedExpense += schedule.amount;
        }
        current = nextOccurrenceAfter(
            current, schedule.frequency, schedule.startDate);
      }
    }

    return PlannedRemainingAmounts(
      plannedRemainingIncome: plannedIncome,
      plannedRemainingExpense: plannedExpense,
    );
  }
}
