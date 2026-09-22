import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/user_model.dart';
import '../models/wallet_model.dart';
import '../models/category_model.dart';
import '../models/transaction_model.dart';
import '../models/budget_model.dart';
import '../models/saving_goal_model.dart';
import '../models/notification_model.dart';
import '../models/recurring_transaction_model.dart';
import 'recurring_transaction_service.dart';
import 'storage_service.dart';
import '../utils/transaction_business_logic.dart';

/// ============================================================
/// FIRESTORE SERVICE
/// CRUD cho tất cả collections: users, wallets, categories,
/// transactions, budgets, savingGoals, notifications
/// ============================================================
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ---------------- USERS ----------------
  Future<void> createUserProfile(AppUser user) {
    return _db.collection('users').doc(user.uid).set(user.toMap());
  }

  Future<AppUser?> getUserProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromMap(doc.data()!, doc.id);
  }

  Stream<AppUser?> streamUserProfile(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? AppUser.fromMap(doc.data()!, doc.id) : null);
  }

  Future<void> updateUserProfile(String uid, Map<String, dynamic> data) {
    return _db.collection('users').doc(uid).update(data);
  }

  // ---------------- WALLETS ----------------
  Future<String> createWallet(Wallet wallet) async {
    final ref = await _db.collection('wallets').add(wallet.toMap());
    return ref.id;
  }

  Stream<List<Wallet>> streamWallets(String userId) {
    return _db
        .collection('wallets')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snap) {
      final list =
          snap.docs.map((d) => Wallet.fromMap(d.data(), d.id)).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Future<void> updateWallet(String walletId, Map<String, dynamic> data) {
    return _db.collection('wallets').doc(walletId).update(data);
  }

  Future<void> deleteWallet(String walletId) {
    return _db.collection('wallets').doc(walletId).delete();
  }

  /// Ẩn hoặc khôi phục hiển thị 1 ví — dùng thay cho xóa cứng khi ví đã có
  /// giao dịch, để giữ nguyên lịch sử giao dịch cũ (xem RULES.md nguyên tắc Wallet).
  Future<void> setWalletActive(String walletId, bool isActive) {
    return _db.collection('wallets').doc(walletId).update({
      'isActive': isActive,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<bool> checkWalletInUse(String userId, String walletId) async {
    final txQuery = await _db
        .collection('transactions')
        .where('userId', isEqualTo: userId)
        .where('walletId', isEqualTo: walletId)
        .limit(1)
        .get();
    return txQuery.docs.isNotEmpty;
  }

  Future<void> reassignAndDeleteWallet(
      String userId, String oldWalletId, String newWalletId) async {
    final oldWalletDoc = await _db.collection('wallets').doc(oldWalletId).get();
    if (!oldWalletDoc.exists) {
      throw Exception('Ví nguồn không tồn tại');
    }
    final oldBalance = (oldWalletDoc.data()!['balance'] as num).toDouble();

    // Giao dịch mà ví này là ví thực hiện (walletId)
    final txQuery = await _db
        .collection('transactions')
        .where('userId', isEqualTo: userId)
        .where('walletId', isEqualTo: oldWalletId)
        .get();

    // Giao dịch chuyển tiền mà ví này là ví ĐÍCH (toWalletId)
    final transferToQuery = await _db
        .collection('transactions')
        .where('userId', isEqualTo: userId)
        .where('toWalletId', isEqualTo: oldWalletId)
        .get();

    final batch = _db.batch();
    for (var doc in txQuery.docs) {
      batch.update(doc.reference, {'walletId': newWalletId});
    }
    for (var doc in transferToQuery.docs) {
      batch.update(doc.reference, {'toWalletId': newWalletId});
    }

    // QUAN TRỌNG: chuyển toàn bộ số dư ví cũ sang ví mới TRƯỚC khi xóa,
    // để tiền không biến mất khỏi tổng tài sản.
    if (oldBalance != 0) {
      batch.update(_db.collection('wallets').doc(newWalletId), {
        'balance': FieldValue.increment(oldBalance),
      });
    }

    batch.delete(_db.collection('wallets').doc(oldWalletId));
    await batch.commit();
  }

  /// Cập nhật số dư ví (dùng khi thêm/sửa/xóa giao dịch)
  Future<void> adjustWalletBalance(String walletId, double delta) {
    return _db.collection('wallets').doc(walletId).update({
      'balance': FieldValue.increment(delta),
    });
  }

  // ---------------- CATEGORIES ----------------
  Future<String> createCategory(Category category) async {
    final ref = await _db.collection('categories').add(category.toMap());
    return ref.id;
  }

  Stream<List<Category>> streamCategories(String userId, {String? type}) {
    Query<Map<String, dynamic>> query =
        _db.collection('categories').where('userId', isEqualTo: userId);
    if (type != null) {
      query = query.where('type', isEqualTo: type);
    }
    return query.snapshots().map((snap) {
      final list =
          snap.docs.map((d) => Category.fromMap(d.data(), d.id)).toList();
      list.sort((a, b) => a.name.compareTo(b.name));
      return list;
    });
  }

  Future<void> updateCategory(String categoryId, Map<String, dynamic> data) {
    return _db.collection('categories').doc(categoryId).update(data);
  }

  Future<void> deleteCategory(String categoryId) {
    return _db.collection('categories').doc(categoryId).delete();
  }

  Future<bool> checkCategoryInUse(String userId, String categoryId) async {
    final txQuery = await _db
        .collection('transactions')
        .where('userId', isEqualTo: userId)
        .where('categoryId', isEqualTo: categoryId)
        .limit(1)
        .get();
    if (txQuery.docs.isNotEmpty) return true;
    final budgetQuery = await _db
        .collection('budgets')
        .where('userId', isEqualTo: userId)
        .where('categoryId', isEqualTo: categoryId)
        .limit(1)
        .get();
    return budgetQuery.docs.isNotEmpty;
  }

  Future<void> reassignAndDeleteCategory(
      String userId, String oldCategoryId, String newCategoryId) async {
    final txQuery = await _db
        .collection('transactions')
        .where('userId', isEqualTo: userId)
        .where('categoryId', isEqualTo: oldCategoryId)
        .get();
    final budgetQuery = await _db
        .collection('budgets')
        .where('userId', isEqualTo: userId)
        .where('categoryId', isEqualTo: oldCategoryId)
        .get();

    final batch = _db.batch();
    for (var doc in txQuery.docs) {
      batch.update(doc.reference, {'categoryId': newCategoryId});
    }
    for (var doc in budgetQuery.docs) {
      batch.update(doc.reference, {'categoryId': newCategoryId});
    }
    batch.delete(_db.collection('categories').doc(oldCategoryId));
    await batch.commit();
  }

  // ---------------- TRANSACTIONS ----------------
  Future<String> createTransaction(AppTransaction tx) async {
    TransactionBusinessLogic.validateAmount(tx.amount);

    final txRef = _db.collection('transactions').doc();
    final walletRef = _db.collection('wallets').doc(tx.walletId);
    DocumentReference? toWalletRef;

    if (tx.type == 'transfer') {
      if (tx.toWalletId == null || tx.toWalletId!.isEmpty) {
        throw Exception('Giao dịch chuyển tiền cần chỉ định ví đích.');
      }
      if (tx.toWalletId == tx.walletId) {
        throw Exception('Ví nguồn và ví đích không được trùng nhau.');
      }
      toWalletRef = _db.collection('wallets').doc(tx.toWalletId);
    }

    DocumentReference? goalRef;
    if (tx.type == 'goal_deposit' || tx.type == 'goal_withdraw') {
      if (tx.goalId == null || tx.goalId!.isEmpty) {
        throw Exception('Giao dịch mục tiêu tiết kiệm cần chỉ định mục tiêu.');
      }
      goalRef = _db.collection('savingGoals').doc(tx.goalId);
    }

    DocumentReference? budgetRef;
    final monthStr = DateFormat('MM/yyyy').format(tx.date);
    if (tx.type == 'expense') {
      final budgetQuery = await _db
          .collection('budgets')
          .where('userId', isEqualTo: tx.userId)
          .where('categoryId', isEqualTo: tx.categoryId)
          .where('month', isEqualTo: monthStr)
          .limit(1)
          .get();
      if (budgetQuery.docs.isNotEmpty) {
        budgetRef = budgetQuery.docs.first.reference;
      }
    }

    await _db.runTransaction((transaction) async {
      final walletSnap = await transaction.get(walletRef);
      if (!walletSnap.exists) throw Exception('Ví không tồn tại.');
      final wallet = Wallet.fromMap(
          walletSnap.data() as Map<String, dynamic>, walletSnap.id);

      Wallet? toWallet;
      if (toWalletRef != null) {
        final toWalletSnap = await transaction.get(toWalletRef);
        if (!toWalletSnap.exists) throw Exception('Ví đích không tồn tại.');
        toWallet = Wallet.fromMap(
            toWalletSnap.data() as Map<String, dynamic>, toWalletSnap.id);
      }

      SavingGoal? goal;
      if (goalRef != null) {
        final goalSnap = await transaction.get(goalRef);
        if (!goalSnap.exists) {
          throw Exception('Mục tiêu tiết kiệm không tồn tại.');
        }
        goal = SavingGoal.fromMap(
            goalSnap.data() as Map<String, dynamic>, goalSnap.id);
      }

      final effects = TransactionBusinessLogic.processCreateTransaction(
        tx: tx,
        wallet: wallet,
        toWallet: toWallet,
        goal: goal,
      );

      transaction.set(txRef, tx.toMap());

      if (effects.newSourceBalance != null) {
        transaction.update(walletRef, {'balance': effects.newSourceBalance});
      }
      if (effects.newTargetBalance != null && toWalletRef != null) {
        transaction.update(toWalletRef, {'balance': effects.newTargetBalance});
      }
      if (effects.newGoalSavedAmount != null && goalRef != null) {
        transaction
            .update(goalRef, {'savedAmount': effects.newGoalSavedAmount});
      }
    });

    if (tx.type == 'expense' && budgetRef != null) {
      try {
        final updatedBudget = await budgetRef.get();
        final data = updatedBudget.data() as Map<String, dynamic>?;
        if (data != null) {
          final limit = (data['limit'] as num).toDouble();
          final newSpent = await getCategorySpentThisMonth(
              tx.userId, tx.categoryId,
              month: tx.date);
          final oldSpent = newSpent - tx.amount;
          if (limit > 0 && newSpent >= limit * 0.8 && oldSpent < limit * 0.8) {
            await createNotification(AppNotification(
              notificationId: '',
              userId: tx.userId,
              title: 'Cảnh báo ngân sách',
              content:
                  'Bạn đã tiêu vượt 80% ngân sách tháng $monthStr cho danh mục này.',
              status: 'unread',
              type: 'budget',
              createdAt: DateTime.now(),
            ));
          }
        }
      } catch (_) {}
    }

    return txRef.id;
  }

  Stream<List<AppTransaction>> streamTransactions(
    String userId, {
    DateTime? from,
    DateTime? to,
  }) {
    Query<Map<String, dynamic>> query =
        _db.collection('transactions').where('userId', isEqualTo: userId);

    if (from != null) {
      query =
          query.where('date', isGreaterThanOrEqualTo: from.toIso8601String());
    }
    if (to != null) {
      query = query.where('date', isLessThanOrEqualTo: to.toIso8601String());
    }

    // Sort by date descending (Requires Composite Index in Firestore)
    query = query.orderBy('date', descending: true);

    return query.snapshots().map((snap) {
      return snap.docs
          .map((d) => AppTransaction.fromMap(d.data(), d.id))
          .toList();
    });
  }

  /// Lấy danh sách giao dịch của user trong khoảng thời gian (dùng cho Smart Transaction Assistant)
  Future<List<AppTransaction>> getUserTransactions(
    String userId, {
    DateTime? from,
    DateTime? to,
  }) async {
    Query<Map<String, dynamic>> query =
        _db.collection('transactions').where('userId', isEqualTo: userId);

    if (from != null) {
      query =
          query.where('date', isGreaterThanOrEqualTo: from.toIso8601String());
    }
    if (to != null) {
      query = query.where('date', isLessThanOrEqualTo: to.toIso8601String());
    }

    final snap = await query.get();
    final list = snap.docs
        .map((d) => AppTransaction.fromMap(d.data(), d.id))
        .toList();
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }


  Future<void> updateTransaction(String txId, Map<String, dynamic> data) {
    return _db.collection('transactions').doc(txId).update(data);
  }

  /// Cập nhật giao dịch an toàn, xử lý atomic cả số dư ví và ngân sách
  Future<void> updateTransactionSafely(
    AppTransaction oldTx,
    AppTransaction newTx,
  ) async {
    if (oldTx.type == 'goal_deposit' ||
        oldTx.type == 'goal_withdraw' ||
        newTx.type == 'goal_deposit' ||
        newTx.type == 'goal_withdraw') {
      throw Exception(
          'Giao dịch nạp/rút mục tiêu không thể sửa. Vui lòng xóa và tạo lại giao dịch.');
    }

    TransactionBusinessLogic.validateAmount(newTx.amount);

    final monthStrNew = DateFormat('MM/yyyy').format(newTx.date);

    DocumentReference? newBudgetRef;
    if (newTx.type == 'expense') {
      final q = await _db
          .collection('budgets')
          .where('userId', isEqualTo: newTx.userId)
          .where('categoryId', isEqualTo: newTx.categoryId)
          .where('month', isEqualTo: monthStrNew)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) newBudgetRef = q.docs.first.reference;
    }

    final txRef = _db.collection('transactions').doc(newTx.transactionId);
    final oldWalletRef = _db.collection('wallets').doc(oldTx.walletId);
    final newWalletRef = _db.collection('wallets').doc(newTx.walletId);
    final oldToWalletRef =
        (oldTx.type == 'transfer' && oldTx.toWalletId != null)
            ? _db.collection('wallets').doc(oldTx.toWalletId!)
            : null;
    final newToWalletRef =
        (newTx.type == 'transfer' && newTx.toWalletId != null)
            ? _db.collection('wallets').doc(newTx.toWalletId!)
            : null;

    await _db.runTransaction((txn) async {
      final oldWalletSnap = await txn.get(oldWalletRef);
      if (!oldWalletSnap.exists) throw Exception('Ví nguồn không tồn tại.');
      final oldWallet = Wallet.fromMap(
          oldWalletSnap.data() as Map<String, dynamic>, oldWalletSnap.id);

      final newWalletSnap = (newTx.walletId == oldTx.walletId)
          ? oldWalletSnap
          : await txn.get(newWalletRef);
      if (!newWalletSnap.exists) throw Exception('Ví nguồn mới không tồn tại.');
      final newWallet = Wallet.fromMap(
          newWalletSnap.data() as Map<String, dynamic>, newWalletSnap.id);

      Wallet? oldToWallet;
      if (oldToWalletRef != null) {
        final oldToSnap = await txn.get(oldToWalletRef);
        if (oldToSnap.exists) {
          oldToWallet = Wallet.fromMap(
              oldToSnap.data() as Map<String, dynamic>, oldToSnap.id);
        }
      }

      Wallet? newToWallet;
      if (newToWalletRef != null) {
        final newToSnap = (oldTx.type == 'transfer' &&
                newTx.toWalletId == oldTx.toWalletId &&
                oldToWallet != null)
            ? await txn.get(oldToWalletRef!)
            : await txn.get(newToWalletRef);
        if (!newToSnap.exists) throw Exception('Ví đích không tồn tại.');
        newToWallet = Wallet.fromMap(
            newToSnap.data() as Map<String, dynamic>, newToSnap.id);
      }

      final balanceMap = TransactionBusinessLogic.processUpdateTransaction(
        oldTx: oldTx,
        newTx: newTx,
        oldWallet: oldWallet,
        newWallet: newWallet,
        oldToWallet: oldToWallet,
        newToWallet: newToWallet,
      );

      // Cập nhật tất cả các ví đã tính toán vào transaction
      balanceMap.forEach((walletId, newBalance) {
        txn.update(
            _db.collection('wallets').doc(walletId), {'balance': newBalance});
      });

      txn.update(txRef, newTx.toMap());
    });

    if (newTx.type == 'expense' && newBudgetRef != null) {
      try {
        final budgetDoc = await newBudgetRef.get();
        final data = budgetDoc.data() as Map<String, dynamic>?;
        if (data != null) {
          final limit = (data['limit'] as num).toDouble();
          final newSpent = await getCategorySpentThisMonth(
              newTx.userId, newTx.categoryId,
              month: newTx.date);
          final delta = newTx.categoryId == oldTx.categoryId
              ? (newTx.amount - oldTx.amount)
              : newTx.amount;
          final oldSpent = newSpent - delta;
          if (limit > 0 && newSpent >= limit * 0.8 && oldSpent < limit * 0.8) {
            await createNotification(AppNotification(
              notificationId: '',
              userId: newTx.userId,
              title: 'Cảnh báo ngân sách',
              content:
                  'Giao dịch vừa sửa đã làm bạn tiêu vượt 80% ngân sách tháng $monthStrNew cho danh mục này.',
              status: 'unread',
              type: 'budget',
              createdAt: DateTime.now(),
            ));
          }
        }
      } catch (_) {}
    }
  }

  Future<void> deleteTransaction(AppTransaction tx) async {
    final txRef = _db.collection('transactions').doc(tx.transactionId);
    final walletRef = _db.collection('wallets').doc(tx.walletId);
    final toWalletRef = (tx.type == 'transfer' &&
            tx.toWalletId != null &&
            tx.toWalletId!.isNotEmpty)
        ? _db.collection('wallets').doc(tx.toWalletId!)
        : null;
    final goalRef =
        ((tx.type == 'goal_deposit' || tx.type == 'goal_withdraw') &&
                tx.goalId != null &&
                tx.goalId!.isNotEmpty)
            ? _db.collection('savingGoals').doc(tx.goalId!)
            : null;

    await _db.runTransaction((transaction) async {
      final txSnap = await transaction.get(txRef);
      if (!txSnap.exists) return; // Giao dịch đã bị xóa trước đó

      final walletSnap = await transaction.get(walletRef);
      Wallet? wallet;
      if (walletSnap.exists) {
        wallet = Wallet.fromMap(
            walletSnap.data() as Map<String, dynamic>, walletSnap.id);
      }

      Wallet? toWallet;
      if (toWalletRef != null) {
        final toWalletSnap = await transaction.get(toWalletRef);
        if (toWalletSnap.exists) {
          toWallet = Wallet.fromMap(
              toWalletSnap.data() as Map<String, dynamic>, toWalletSnap.id);
        }
      }

      SavingGoal? goal;
      if (goalRef != null) {
        final goalSnap = await transaction.get(goalRef);
        if (goalSnap.exists) {
          goal = SavingGoal.fromMap(
              goalSnap.data() as Map<String, dynamic>, goalSnap.id);
        }
      }

      final effects = TransactionBusinessLogic.processDeleteTransaction(
        tx: tx,
        wallet: wallet,
        toWallet: toWallet,
        goal: goal,
      );

      if (walletSnap.exists && effects.newSourceBalance != null) {
        transaction.update(walletRef, {'balance': effects.newSourceBalance});
      }
      if (toWalletRef != null && effects.newTargetBalance != null) {
        final toSnap = await transaction.get(toWalletRef);
        if (toSnap.exists) {
          transaction
              .update(toWalletRef, {'balance': effects.newTargetBalance});
        }
      }
      if (goalRef != null && effects.newGoalSavedAmount != null) {
        final gSnap = await transaction.get(goalRef);
        if (gSnap.exists) {
          transaction
              .update(goalRef, {'savedAmount': effects.newGoalSavedAmount});
        }
      }

      transaction.delete(txRef);
    });

    if (tx.image != null && tx.image!.isNotEmpty) {
      try {
        await StorageService().deleteImageByUrl(tx.image!);
      } catch (_) {}
    }
  }

  // ---------------- BUDGETS ----------------
  Future<String> createBudget(Budget budget) async {
    final ref = await _db.collection('budgets').add(budget.toMap());
    return ref.id;
  }

  Stream<List<Budget>> streamBudgets(String userId, {String? month}) {
    Query<Map<String, dynamic>> query =
        _db.collection('budgets').where('userId', isEqualTo: userId);
    if (month != null) {
      query = query.where('month', isEqualTo: month);
    }
    return query.snapshots().map((snap) {
      final list =
          snap.docs.map((d) => Budget.fromMap(d.data(), d.id)).toList();
      list.sort((a, b) => b.month
          .compareTo(a.month)); // Sort text MM/yyyy, not perfect but okay
      return list;
    });
  }

  Future<void> updateBudget(String budgetId, Map<String, dynamic> data) {
    return _db.collection('budgets').doc(budgetId).update(data);
  }

  Future<void> deleteBudget(String budgetId) {
    return _db.collection('budgets').doc(budgetId).delete();
  }

  /// Tính tổng chi tiêu (expense) của 1 category trong 1 tháng cụ thể —
  /// tính ĐỘNG từ transactions, không đọc field spent (đã bỏ khỏi Budget).
  Future<double> getCategorySpentThisMonth(
    String userId,
    String categoryId, {
    DateTime? month,
  }) async {
    final target = month ?? DateTime.now();
    final monthStart = DateTime(target.year, target.month, 1);
    final monthEnd = DateTime(target.year, target.month + 1, 1)
        .subtract(const Duration(seconds: 1));
    final txQuery = await _db
        .collection('transactions')
        .where('userId', isEqualTo: userId)
        .where('date', isGreaterThanOrEqualTo: monthStart.toIso8601String())
        .where('date', isLessThanOrEqualTo: monthEnd.toIso8601String())
        .orderBy('date', descending: true)
        .get();
    double total = 0;
    for (final doc in txQuery.docs) {
      final data = doc.data();
      if (data['type'] == 'expense' && data['categoryId'] == categoryId) {
        total += (data['amount'] as num).toDouble();
      }
    }
    return total;
  }

  // ---------------- SAVING GOALS ----------------
  Future<String> createSavingGoal(SavingGoal goal) async {
    final ref = await _db.collection('savingGoals').add(goal.toMap());
    return ref.id;
  }

  Stream<List<SavingGoal>> streamSavingGoals(String userId) {
    return _db
        .collection('savingGoals')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snap) {
      final list =
          snap.docs.map((d) => SavingGoal.fromMap(d.data(), d.id)).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Future<void> updateSavingGoal(String goalId, Map<String, dynamic> data) {
    return _db.collection('savingGoals').doc(goalId).update(data);
  }

  // ---------------- NOTIFICATIONS ----------------
  Future<void> createNotification(AppNotification notification) {
    return _db.collection('notifications').add(notification.toMap());
  }

  Stream<List<AppNotification>> streamNotifications(String userId) {
    return _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => AppNotification.fromMap(d.data(), d.id))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  // ---------------- HELPERS ----------------
  /// Lấy số dư hiện tại của ví
  Future<double> getWalletBalance(String walletId) async {
    final doc = await _db.collection('wallets').doc(walletId).get();
    if (!doc.exists) return 0;
    final data = doc.data()!;
    return (data['balance'] as num).toDouble();
  }

  /// Lấy budget cho danh mục trong tháng hiện tại (hoặc tháng chỉ định)
  Future<Budget?> getCategoryBudget(String userId, String categoryId,
      {String? month}) async {
    final now = DateTime.now();
    final monthStr = month ?? DateFormat('MM/yyyy').format(now);
    final query = await _db
        .collection('budgets')
        .where('userId', isEqualTo: userId)
        .where('categoryId', isEqualTo: categoryId)
        .where('month', isEqualTo: monthStr)
        .limit(1)
        .get();
    if (query.docs.isEmpty) return null;
    final doc = query.docs.first;
    return Budget.fromMap(doc.data(), doc.id);
  }

  Future<void> markNotificationRead(String notificationId) {
    return _db
        .collection('notifications')
        .doc(notificationId)
        .update({'status': 'read'});
  }

  // ---------------- RECURRING TRANSACTIONS ----------------
  Future<String> createRecurringTransaction(
      RecurringTransactionSchedule schedule) async {
    RecurringTransactionSchedule.validateAmount(schedule.amount);

    final walletDoc =
        await _db.collection('wallets').doc(schedule.walletId).get();
    if (!walletDoc.exists) {
      throw Exception('Ví được chọn không tồn tại.');
    }
    final wallet = Wallet.fromMap(walletDoc.data()!, walletDoc.id);
    if (!wallet.isActive) {
      throw Exception('Không thể tạo lịch giao dịch với ví đã bị ẩn.');
    }

    if (schedule.type == 'expense' && schedule.categoryId.isNotEmpty) {
      final catDoc =
          await _db.collection('categories').doc(schedule.categoryId).get();
      if (!catDoc.exists) {
        throw Exception('Danh mục được chọn không tồn tại.');
      }
    }

    final ref =
        await _db.collection('recurringTransactions').add(schedule.toMap());
    return ref.id;
  }

  Stream<List<RecurringTransactionSchedule>> streamRecurringTransactions(
      String userId) {
    return _db
        .collection('recurringTransactions')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => RecurringTransactionSchedule.fromMap(d.data(), d.id))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Future<void> updateRecurringTransaction(
      String scheduleId, Map<String, dynamic> data) {
    data.remove('userId'); // Bảo vệ userId không bị thay đổi
    data['updatedAt'] = DateTime.now().toIso8601String();
    return _db.collection('recurringTransactions').doc(scheduleId).update(data);
  }

  Future<void> setRecurringTransactionActive(String scheduleId, bool isActive) {
    return _db.collection('recurringTransactions').doc(scheduleId).update({
      'isActive': isActive,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> deleteRecurringTransaction(String scheduleId) {
    // Chỉ xóa schedule, không xóa lịch sử giao dịch đã tạo trước đó
    return _db.collection('recurringTransactions').doc(scheduleId).delete();
  }

  Future<Map<String, dynamic>> processDueRecurringTransactions(
    String userId, {
    DateTime? referenceDate,
  }) async {
    final now = referenceDate ?? DateTime.now();
    final recService = RecurringTransactionService();

    final querySnap = await _db
        .collection('recurringTransactions')
        .where('userId', isEqualTo: userId)
        .where('isActive', isEqualTo: true)
        .get();

    final schedules = querySnap.docs
        .map((d) => RecurringTransactionSchedule.fromMap(d.data(), d.id))
        .toList();

    int processedCount = 0;
    int skippedCount = 0;
    final List<String> failedSchedules = [];

    for (final schedule in schedules) {
      final dueDates = recService.dueOccurrences(
        schedule: schedule,
        referenceDate: now,
      );

      if (dueDates.isEmpty) continue;

      bool stopSchedule = false;

      for (final occurrenceDate in dueDates) {
        if (stopSchedule) break;

        final occurrenceKey =
            RecurringTransactionService.getOccurrenceKey(occurrenceDate);
        final deterministicTxId =
            RecurringTransactionService.buildTransactionId(
                schedule.scheduleId, occurrenceDate);

        final txRef = _db.collection('transactions').doc(deterministicTxId);
        final walletRef = _db.collection('wallets').doc(schedule.walletId);
        final scheduleRef =
            _db.collection('recurringTransactions').doc(schedule.scheduleId);

        bool transactionAlreadyExists = false;
        bool insufficientBalance = false;
        bool walletUnavailable = false;

        await _db.runTransaction((txn) async {
          final txSnap = await txn.get(txRef);
          if (txSnap.exists) {
            transactionAlreadyExists = true;
            return;
          }

          final walletSnap = await txn.get(walletRef);
          if (!walletSnap.exists) {
            walletUnavailable = true;
            return;
          }

          final wallet = Wallet.fromMap(
              walletSnap.data() as Map<String, dynamic>, walletSnap.id);
          if (!wallet.isActive) {
            walletUnavailable = true;
            return;
          }

          if (schedule.type == 'expense' && wallet.balance < schedule.amount) {
            insufficientBalance = true;
            return;
          }

          // Tạo AppTransaction doc
          final appTx = AppTransaction(
            transactionId: deterministicTxId,
            userId: userId,
            walletId: schedule.walletId,
            categoryId: schedule.categoryId,
            amount: schedule.amount,
            type: schedule.type,
            note: schedule.note != null && schedule.note!.isNotEmpty
                ? schedule.note
                : 'Giao dịch định kỳ',
            date: occurrenceDate,
            recurringScheduleId: schedule.scheduleId,
            recurringOccurrenceKey: occurrenceKey,
          );

          txn.set(txRef, appTx.toMap());

          final delta =
              schedule.type == 'income' ? schedule.amount : -schedule.amount;
          txn.update(walletRef, {
            'balance': FieldValue.increment(delta),
          });

          // Tính nextDueDate cho kỳ tiếp theo
          final nextDueDate = recService.nextOccurrenceAfter(
            occurrenceDate,
            schedule.frequency,
            schedule.startDate,
          );

          txn.update(scheduleRef, {
            'nextDueDate': nextDueDate.toIso8601String(),
            'lastProcessedKey': occurrenceKey,
            'updatedAt': DateTime.now().toIso8601String(),
          });
        });

        if (transactionAlreadyExists) {
          skippedCount++;
        } else if (walletUnavailable) {
          failedSchedules.add(
              'Ví cho khoản "${schedule.note ?? 'Giao dịch định kỳ'}" không khả dụng.');
          stopSchedule = true;
        } else if (insufficientBalance) {
          failedSchedules.add(
              'Ví không đủ số dư để ghi nhận khoản "${schedule.note ?? 'Giao dịch định kỳ'}" (${schedule.amount.round()}đ).');
          stopSchedule = true;
        } else {
          processedCount++;
        }
      }
    }

    return {
      'processedCount': processedCount,
      'skippedCount': skippedCount,
      'failedSchedules': failedSchedules,
    };
  }
}
