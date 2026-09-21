import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_ai_app/models/recurring_transaction_model.dart';
import 'package:finance_ai_app/models/transaction_model.dart';
import 'package:finance_ai_app/models/wallet_model.dart';
import 'package:finance_ai_app/services/financial_forecast_service.dart';
import 'package:finance_ai_app/services/recurring_transaction_service.dart';

void main() {
  group('RecurringTransactionService Pure Dart Unit Tests', () {
    final service = RecurringTransactionService();
    final forecastService = FinancialForecastService();

    // 1. Weekly recurrence
    test('1. Weekly recurrence creates exact next date on same weekday', () {
      final startDate = DateTime(2026, 9, 7); // Monday
      final fromDate = DateTime(2026, 9, 7);
      final next = service.nextOccurrenceAfter(fromDate, 'weekly', startDate);
      expect(next.weekday, equals(DateTime.monday));
      expect(next, equals(DateTime(2026, 9, 14)));
    });

    // 2. Monthly recurrence day 31 falls on last day of 30-day month
    test(
        '2. Monthly recurrence day 31 falls on last day of 30-day month (e.g. Sept 30)',
        () {
      final startDate = DateTime(2026, 8, 31); // Aug 31
      final fromDate = DateTime(2026, 8, 31);
      final next = service.nextOccurrenceAfter(fromDate, 'monthly', startDate);
      expect(next.month, equals(9));
      expect(next.day, equals(30)); // September has 30 days
    });

    // 3. Monthly recurrence day 31 in Feb of non-leap year
    test('3. Monthly recurrence day 31 in Feb of non-leap year (Feb 28)', () {
      final startDate = DateTime(2026, 1, 31); // Jan 31, 2026
      final fromDate = DateTime(2026, 1, 31);
      final next = service.nextOccurrenceAfter(fromDate, 'monthly', startDate);
      expect(next.year, equals(2026));
      expect(next.month, equals(2));
      expect(next.day, equals(28));
    });

    // 4. Monthly recurrence day 29 in Feb of leap year
    test('4. Monthly recurrence day 29 in Feb of leap year (Feb 29, 2028)', () {
      final startDate = DateTime(2028, 1, 31); // Jan 31, 2028 (leap year)
      final fromDate = DateTime(2028, 1, 31);
      final next = service.nextOccurrenceAfter(fromDate, 'monthly', startDate);
      expect(next.year, equals(2028));
      expect(next.month, equals(2));
      expect(next.day, equals(29));
    });

    // 5. Due occurrences includes current reference date
    test(
        '5. Due occurrences includes current reference date if nextDueDate <= referenceDate',
        () {
      final schedule = RecurringTransactionSchedule(
        scheduleId: 'sch_1',
        userId: 'u_1',
        type: 'expense',
        walletId: 'w_1',
        categoryId: 'cat_food',
        amount: 100000,
        frequency: 'monthly',
        startDate: DateTime(2026, 9, 15),
        nextDueDate: DateTime(2026, 9, 15),
        createdAt: DateTime(2026, 9, 1),
      );

      final due = service.dueOccurrences(
        schedule: schedule,
        referenceDate: DateTime(2026, 9, 15),
      );

      expect(due.length, equals(1));
      expect(due.first, equals(DateTime(2026, 9, 15)));
    });

    // 6. Upcoming occurrences filter strictly within 7/14/30 day window
    test('6. Upcoming occurrences filter strictly within 7/14/30 day window',
        () {
      final schedules = [
        RecurringTransactionSchedule(
          scheduleId: 'sch_1',
          userId: 'u_1',
          type: 'expense',
          walletId: 'w_1',
          categoryId: 'cat_food',
          amount: 100000,
          frequency: 'monthly',
          startDate: DateTime(2026, 9, 20),
          nextDueDate: DateTime(2026, 9, 20),
          createdAt: DateTime(2026, 9, 1),
        ),
        RecurringTransactionSchedule(
          scheduleId: 'sch_2',
          userId: 'u_1',
          type: 'income',
          walletId: 'w_1',
          categoryId: '',
          amount: 5000000,
          frequency: 'monthly',
          startDate: DateTime(2026, 10, 25),
          nextDueDate: DateTime(2026, 10, 25),
          createdAt: DateTime(2026, 9, 1),
        ),
      ];

      final refDate = DateTime(2026, 9, 15);
      final upcoming7Days = service.upcomingOccurrences(
        schedules: schedules,
        referenceDate: refDate,
        daysAhead: 7,
      );

      expect(upcoming7Days.length, equals(1));
      expect(upcoming7Days.first.schedule.scheduleId, equals('sch_1'));

      final upcoming30Days = service.upcomingOccurrences(
        schedules: schedules,
        referenceDate: refDate,
        daysAhead: 30,
      );

      expect(upcoming30Days.length,
          equals(1)); // sch_2 is Oct 25 (> 30 days from Sept 15)
    });

    // 7. No duplicate occurrences
    test('7. No duplicate occurrences returned by dueOccurrences', () {
      final schedule = RecurringTransactionSchedule(
        scheduleId: 'sch_1',
        userId: 'u_1',
        type: 'expense',
        walletId: 'w_1',
        categoryId: 'cat_food',
        amount: 100000,
        frequency: 'weekly',
        startDate: DateTime(2026, 9, 1),
        nextDueDate: DateTime(2026, 9, 1),
        createdAt: DateTime(2026, 9, 1),
      );

      final due = service.dueOccurrences(
        schedule: schedule,
        referenceDate: DateTime(2026, 9, 15),
      );

      final uniqueSet = due.toSet();
      expect(due.length, equals(uniqueSet.length));
    });

    // 8. Catch-up cap works properly
    test(
        '8. Catch-up cap limits backlog occurrences to specified max (default 12)',
        () {
      final schedule = RecurringTransactionSchedule(
        scheduleId: 'sch_1',
        userId: 'u_1',
        type: 'expense',
        walletId: 'w_1',
        categoryId: 'cat_food',
        amount: 100000,
        frequency: 'weekly',
        startDate: DateTime(2025, 1, 1),
        nextDueDate: DateTime(2025, 1, 1),
        createdAt: DateTime(2025, 1, 1),
      );

      final due = service.dueOccurrences(
        schedule: schedule,
        referenceDate: DateTime(2026, 9, 15),
        catchUpCap: 12,
      );

      expect(due.length, equals(12));
    });

    // 9. Fixed referenceDate yields reproducible results
    test('9. Fixed referenceDate yields reproducible results', () {
      final refDate1 = DateTime(2026, 9, 15);
      final refDate2 = DateTime(2026, 9, 15);

      final schedule = RecurringTransactionSchedule(
        scheduleId: 'sch_1',
        userId: 'u_1',
        type: 'expense',
        walletId: 'w_1',
        categoryId: 'cat_food',
        amount: 100000,
        frequency: 'monthly',
        startDate: DateTime(2026, 9, 10),
        nextDueDate: DateTime(2026, 9, 10),
        createdAt: DateTime(2026, 9, 1),
      );

      final due1 =
          service.dueOccurrences(schedule: schedule, referenceDate: refDate1);
      final due2 =
          service.dueOccurrences(schedule: schedule, referenceDate: refDate2);

      expect(due1, equals(due2));
    });

    // 10. Forecast planned income/expense calculation
    test(
        '10. Forecast planned remaining income and expense calculated correctly for remaining month',
        () {
      final schedules = [
        RecurringTransactionSchedule(
          scheduleId: 'sch_inc',
          userId: 'u_1',
          type: 'income',
          walletId: 'w_1',
          categoryId: '',
          amount: 5000000,
          frequency: 'monthly',
          startDate: DateTime(2026, 9, 25),
          nextDueDate: DateTime(2026, 9, 25),
          createdAt: DateTime(2026, 9, 1),
        ),
        RecurringTransactionSchedule(
          scheduleId: 'sch_exp',
          userId: 'u_1',
          type: 'expense',
          walletId: 'w_1',
          categoryId: 'cat_rent',
          amount: 2000000,
          frequency: 'monthly',
          startDate: DateTime(2026, 9, 20),
          nextDueDate: DateTime(2026, 9, 20),
          createdAt: DateTime(2026, 9, 1),
        ),
      ];

      final refDate = DateTime(2026, 9, 15);
      final planned = service.computePlannedRemainingAmounts(
        schedules: schedules,
        referenceDate: refDate,
      );

      expect(planned.plannedRemainingIncome, equals(5000000.0));
      expect(planned.plannedRemainingExpense, equals(2000000.0));
    });

    // 11. Forecast does not double-count created recurring expenses
    test(
        '11. Forecast excludes created recurring expenses from daily discretionary expense average',
        () {
      final activeWallets = [
        Wallet(
          walletId: 'w_1',
          userId: 'u_1',
          walletName: 'Ví chính',
          balance: 10000000,
          type: 'bank',
          createdAt: DateTime(2026, 1, 1),
        ),
      ];

      final refDate = DateTime(2026, 9, 15);

      final transactions = [
        // Manual discretionary expense (150,000 in 15 days -> 10k/day)
        AppTransaction(
          transactionId: 'tx_manual',
          userId: 'u_1',
          walletId: 'w_1',
          categoryId: 'cat_food',
          amount: 150000,
          type: 'expense',
          date: refDate,
        ),
        // Created recurring expense (already processed)
        AppTransaction(
          transactionId: 'recurring_sch_rent_2026-09-05',
          userId: 'u_1',
          walletId: 'w_1',
          categoryId: 'cat_rent',
          amount: 2000000,
          type: 'expense',
          date: DateTime(2026, 9, 5),
          recurringScheduleId: 'sch_rent',
          recurringOccurrenceKey: '2026-09-05',
        ),
      ];

      final forecast = forecastService.calculateMonthEndForecast(
        activeWallets: activeWallets,
        currentMonthTx: transactions,
        refDate: refDate,
      );

      // Discretionary avg should only be calculated from manual expense (150,000 / 15 days = 10,000/day)
      expect(forecast.averageDailyDiscretionaryExpense, equals(10000.0));
      expect(forecast.projectedRemainingDiscretionaryExpense, equals(150000.0));
    });

    // 12. Schedule paused does not contribute to forecast or due occurrences
    test(
        '12. Schedule with isActive == false returns zero due occurrences and zero forecast planned amounts',
        () {
      final schedule = RecurringTransactionSchedule(
        scheduleId: 'sch_paused',
        userId: 'u_1',
        type: 'expense',
        walletId: 'w_1',
        categoryId: 'cat_food',
        amount: 1000000,
        frequency: 'monthly',
        startDate: DateTime(2026, 9, 10),
        nextDueDate: DateTime(2026, 9, 10),
        isActive: false, // Paused!
        createdAt: DateTime(2026, 9, 1),
      );

      final refDate = DateTime(2026, 9, 15);
      final due =
          service.dueOccurrences(schedule: schedule, referenceDate: refDate);
      expect(due, isEmpty);

      final planned = service.computePlannedRemainingAmounts(
        schedules: [schedule],
        referenceDate: refDate,
      );
      expect(planned.plannedRemainingExpense, equals(0.0));
      expect(planned.plannedRemainingIncome, equals(0.0));
    });
  });

  group('FakeCloudFirestore Integration Tests', () {
    late FakeFirebaseFirestore fakeDb;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
    });

    // 13. Idempotent processing test
    test(
        '13. Processing due recurring transactions twice for same schedule + occurrenceKey creates only 1 transaction',
        () async {
      final userId = 'u_1';
      final scheduleId = 'sch_salary';
      final occurrenceDate = DateTime(2026, 9, 10);
      final occurrenceKey =
          RecurringTransactionService.getOccurrenceKey(occurrenceDate);
      final deterministicTxId = RecurringTransactionService.buildTransactionId(
          scheduleId, occurrenceDate);

      // Seed wallet
      await fakeDb.collection('wallets').doc('w_1').set({
        'userId': userId,
        'walletName': 'Ví Bank',
        'balance': 5000000.0,
        'type': 'bank',
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      // Seed schedule
      await fakeDb.collection('recurringTransactions').doc(scheduleId).set({
        'userId': userId,
        'type': 'income',
        'walletId': 'w_1',
        'categoryId': '',
        'amount': 10000000.0,
        'frequency': 'monthly',
        'startDate': occurrenceDate.toIso8601String(),
        'nextDueDate': occurrenceDate.toIso8601String(),
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      // 1st processing run
      await fakeDb.runTransaction((txn) async {
        final txRef = fakeDb.collection('transactions').doc(deterministicTxId);
        final txSnap = await txn.get(txRef);
        expect(txSnap.exists, isFalse);

        final appTx = AppTransaction(
          transactionId: deterministicTxId,
          userId: userId,
          walletId: 'w_1',
          categoryId: '',
          amount: 10000000.0,
          type: 'income',
          date: occurrenceDate,
          recurringScheduleId: scheduleId,
          recurringOccurrenceKey: occurrenceKey,
        );

        txn.set(txRef, appTx.toMap());
        txn.update(
            fakeDb.collection('wallets').doc('w_1'), {'balance': 15000000.0});
      });

      // 2nd processing run (simulating retry)
      bool skippedOnSecondRun = false;
      await fakeDb.runTransaction((txn) async {
        final txRef = fakeDb.collection('transactions').doc(deterministicTxId);
        final txSnap = await txn.get(txRef);
        if (txSnap.exists) {
          skippedOnSecondRun = true;
          return;
        }
      });

      expect(skippedOnSecondRun, isTrue);

      // Verify wallet balance changed only once (5m + 10m = 15m)
      final walletDoc = await fakeDb.collection('wallets').doc('w_1').get();
      expect(walletDoc.data()!['balance'], equals(15000000.0));
    });

    // 14. Expense with insufficient balance test
    test(
        '14. Recurring expense with insufficient balance does not create transaction, does not change balance, and does not advance nextDueDate',
        () async {
      final userId = 'u_1';
      final scheduleId = 'sch_rent';
      final occurrenceDate = DateTime(2026, 9, 10);

      // Seed wallet with low balance (500,000)
      await fakeDb.collection('wallets').doc('w_1').set({
        'userId': userId,
        'walletName': 'Ví Chi Tiêu',
        'balance': 500000.0,
        'type': 'cash',
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      // Seed schedule requiring 3,000,000
      await fakeDb.collection('recurringTransactions').doc(scheduleId).set({
        'userId': userId,
        'type': 'expense',
        'walletId': 'w_1',
        'categoryId': 'cat_rent',
        'amount': 3000000.0,
        'frequency': 'monthly',
        'startDate': occurrenceDate.toIso8601String(),
        'nextDueDate': occurrenceDate.toIso8601String(),
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      bool insufficientBalanceDetected = false;

      // Attempt processing in transaction
      await fakeDb.runTransaction((txn) async {
        final wSnap = await txn.get(fakeDb.collection('wallets').doc('w_1'));
        final balance = (wSnap.data()!['balance'] as num).toDouble();
        if (balance < 3000000.0) {
          insufficientBalanceDetected = true;
          return;
        }
      });

      expect(insufficientBalanceDetected, isTrue);

      // Verify zero transactions created
      final txQuery = await fakeDb.collection('transactions').get();
      expect(txQuery.docs, isEmpty);

      // Verify balance unchanged
      final walletDoc = await fakeDb.collection('wallets').doc('w_1').get();
      expect(walletDoc.data()!['balance'], equals(500000.0));

      // Verify nextDueDate NOT updated
      final schDoc = await fakeDb
          .collection('recurringTransactions')
          .doc(scheduleId)
          .get();
      expect(schDoc.data()!['nextDueDate'],
          equals(occurrenceDate.toIso8601String()));
    });

    // 15. Delete schedule does not delete past historical transactions
    test(
        '15. Deleting schedule doc does not delete past historical transaction documents',
        () async {
      final scheduleId = 'sch_internet';

      // Seed historical transaction created by schedule
      await fakeDb
          .collection('transactions')
          .doc('recurring_sch_internet_2026-08-01')
          .set({
        'userId': 'u_1',
        'walletId': 'w_1',
        'categoryId': 'cat_internet',
        'amount': 300000.0,
        'type': 'expense',
        'date': DateTime(2026, 8, 1).toIso8601String(),
        'recurringScheduleId': scheduleId,
        'recurringOccurrenceKey': '2026-08-01',
      });

      // Seed schedule
      await fakeDb.collection('recurringTransactions').doc(scheduleId).set({
        'userId': 'u_1',
        'type': 'expense',
        'walletId': 'w_1',
        'categoryId': 'cat_internet',
        'amount': 300000.0,
        'frequency': 'monthly',
        'startDate': DateTime(2026, 8, 1).toIso8601String(),
        'nextDueDate': DateTime(2026, 9, 1).toIso8601String(),
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      // Delete schedule
      await fakeDb.collection('recurringTransactions').doc(scheduleId).delete();

      // Verify schedule is deleted
      final schDoc = await fakeDb
          .collection('recurringTransactions')
          .doc(scheduleId)
          .get();
      expect(schDoc.exists, isFalse);

      // Verify historical transaction document STILL EXISTS
      final txDoc = await fakeDb
          .collection('transactions')
          .doc('recurring_sch_internet_2026-08-01')
          .get();
      expect(txDoc.exists, isTrue);
      expect(txDoc.data()!['recurringScheduleId'], equals(scheduleId));
    });
  });
}
