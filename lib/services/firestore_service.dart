import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/user_model.dart';
import '../models/wallet_model.dart';
import '../models/category_model.dart';
import '../models/transaction_model.dart';
import '../models/budget_model.dart';
import '../models/saving_goal_model.dart';
import '../models/notification_model.dart';
import 'storage_service.dart';

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
    return _db.collection('users').doc(uid).snapshots().map(
        (doc) => doc.exists ? AppUser.fromMap(doc.data()!, doc.id) : null);
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
      final list = snap.docs.map((d) => Wallet.fromMap(d.data(), d.id)).toList();
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

  Future<bool> checkWalletInUse(String walletId) async {
    final txQuery = await _db.collection('transactions').where('walletId', isEqualTo: walletId).limit(1).get();
    return txQuery.docs.isNotEmpty;
  }

  Future<void> reassignAndDeleteWallet(String oldWalletId, String newWalletId) async {
    final txQuery = await _db.collection('transactions').where('walletId', isEqualTo: oldWalletId).get();
    final batch = _db.batch();
    for (var doc in txQuery.docs) {
      batch.update(doc.reference, {'walletId': newWalletId});
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
      final list = snap.docs.map((d) => Category.fromMap(d.data(), d.id)).toList();
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

  Future<bool> checkCategoryInUse(String categoryId) async {
    final txQuery = await _db.collection('transactions').where('categoryId', isEqualTo: categoryId).limit(1).get();
    if (txQuery.docs.isNotEmpty) return true;
    final budgetQuery = await _db.collection('budgets').where('categoryId', isEqualTo: categoryId).limit(1).get();
    return budgetQuery.docs.isNotEmpty;
  }

  Future<void> reassignAndDeleteCategory(String oldCategoryId, String newCategoryId) async {
    final txQuery = await _db.collection('transactions').where('categoryId', isEqualTo: oldCategoryId).get();
    final budgetQuery = await _db.collection('budgets').where('categoryId', isEqualTo: oldCategoryId).get();
    
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
    // Create a reference for the new transaction document (not yet written)
    final txRef = _db.collection('transactions').doc();
    final walletRef = _db.collection('wallets').doc(tx.walletId);

    DocumentReference? budgetRef;
    final monthStr = DateFormat('MM/yyyy').format(tx.date);
    if (tx.type == 'expense') {
      final budgetQuery = await _db
          .collection('budgets')
          .where('categoryId', isEqualTo: tx.categoryId)
          .where('month', isEqualTo: monthStr)
          .limit(1)
          .get();
      if (budgetQuery.docs.isNotEmpty) {
        budgetRef = budgetQuery.docs.first.reference;
      }
    }

    await _db.runTransaction((transaction) async {
      // Read wallet (required before write in Firestore transaction)
      final walletSnap = await transaction.get(walletRef);
      if (!walletSnap.exists) {
        throw Exception('Ví không tồn tại');
      }
      DocumentSnapshot? budgetSnap;
      if (budgetRef != null) {
        budgetSnap = await transaction.get(budgetRef);
      }

      // Write transaction document
      transaction.set(txRef, tx.toMap());

      // Update wallet balance
      final delta = tx.type == 'income' ? tx.amount : -tx.amount;
      final currentBalance = (walletSnap.data() as Map<String, dynamic>)['balance'] as num;
      transaction.update(walletRef, {'balance': currentBalance + delta});

      // Update budget spent if applicable
      if (budgetRef != null && budgetSnap != null && budgetSnap.exists) {
        final currentSpent = (budgetSnap.data() as Map<String, dynamic>)['spent'] as num;
        transaction.update(budgetRef, {'spent': currentSpent + tx.amount});
      }
    });

    // After transaction commits, check for budget warning (outside transaction)
    if (tx.type == 'expense' && budgetRef != null) {
      final updatedBudget = await budgetRef.get();
      final data = updatedBudget.data() as Map<String, dynamic>?;
      if (data != null) {
        final limit = (data['limit'] as num).toDouble();
        final spent = (data['spent'] as num).toDouble();
        if (spent > limit * 0.9 && spent - tx.amount <= limit * 0.9) {
          await createNotification(AppNotification(
            notificationId: '',
            userId: data['userId'],
            title: 'Cảnh báo ngân sách',
            content: 'Bạn đã tiêu vượt 90% ngân sách tháng $monthStr cho danh mục này.',
            status: 'unread',
            type: 'budget',
            createdAt: DateTime.now(),
          ));
        }
      }
    }

    return txRef.id;
  }

  Stream<List<AppTransaction>> streamTransactions(
      String userId, {
        DateTime? from,
        DateTime? to,
      }) {
    Query<Map<String, dynamic>> query = _db
        .collection('transactions')
        .where('userId', isEqualTo: userId);
        
    if (from != null) {
      query = query.where('date', isGreaterThanOrEqualTo: from.toIso8601String());
    }
    if (to != null) {
      query = query.where('date', isLessThanOrEqualTo: to.toIso8601String());
    }
    
    // Sort by date descending (Requires Composite Index in Firestore)
    query = query.orderBy('date', descending: true);
        
    return query.snapshots().map((snap) {
      return snap.docs.map((d) => AppTransaction.fromMap(d.data(), d.id)).toList();
    });
  }

  Future<void> updateTransaction(String txId, Map<String, dynamic> data) {
    return _db.collection('transactions').doc(txId).update(data);
  }

  /// Cập nhật giao dịch an toàn, xử lý atomic cả số dư ví và ngân sách
  Future<void> updateTransactionSafely(
    AppTransaction oldTx,
    AppTransaction newTx,
  ) async {
    // Để có thể đọc trong transaction, ta query budget refs trước
    final monthStrOld = DateFormat('MM/yyyy').format(oldTx.date);
    final monthStrNew = DateFormat('MM/yyyy').format(newTx.date);
    
    final oldBudgetQuery = await _db
        .collection('budgets')
        .where('categoryId', isEqualTo: oldTx.categoryId)
        .where('month', isEqualTo: monthStrOld)
        .limit(1)
        .get();
        
    final newBudgetQuery = await _db
        .collection('budgets')
        .where('categoryId', isEqualTo: newTx.categoryId)
        .where('month', isEqualTo: monthStrNew)
        .limit(1)
        .get();

    final DocumentReference? oldBudgetRef = oldBudgetQuery.docs.isNotEmpty ? oldBudgetQuery.docs.first.reference : null;
    final DocumentReference? newBudgetRef = newBudgetQuery.docs.isNotEmpty ? newBudgetQuery.docs.first.reference : null;

    await _db.runTransaction((txn) async {
      // 1. Hoàn tác ảnh hưởng của oldTx
      if (oldTx.type == 'expense') {
        txn.update(_db.collection('wallets').doc(oldTx.walletId), {
          'balance': FieldValue.increment(oldTx.amount),
        });
        if (oldBudgetRef != null) {
          txn.update(oldBudgetRef, {
            'spent': FieldValue.increment(-oldTx.amount),
          });
        }
      } else {
        txn.update(_db.collection('wallets').doc(oldTx.walletId), {
          'balance': FieldValue.increment(-oldTx.amount),
        });
      }

      // 2. Áp dụng ảnh hưởng của newTx
      if (newTx.type == 'expense') {
        txn.update(_db.collection('wallets').doc(newTx.walletId), {
          'balance': FieldValue.increment(-newTx.amount),
        });
        if (newBudgetRef != null) {
          txn.update(newBudgetRef, {
            'spent': FieldValue.increment(newTx.amount),
          });
        }
      } else {
        txn.update(_db.collection('wallets').doc(newTx.walletId), {
          'balance': FieldValue.increment(newTx.amount),
        });
      }

      // 3. Cập nhật transaction doc
      txn.update(_db.collection('transactions').doc(newTx.transactionId), newTx.toMap());
    });
    
    // Gửi thông báo nếu vượt ngân sách sau khi update
    if (newTx.type == 'expense') {
      final updatedBudgetQuery = await _db
          .collection('budgets')
          .where('categoryId', isEqualTo: newTx.categoryId)
          .where('month', isEqualTo: monthStrNew)
          .limit(1)
          .get();
      if (updatedBudgetQuery.docs.isNotEmpty) {
        final doc = updatedBudgetQuery.docs.first;
        final limit = (doc.data()['limit'] as num).toDouble();
        final spent = (doc.data()['spent'] as num).toDouble();
        if (spent > limit * 0.9 && spent - newTx.amount <= limit * 0.9) {
          await createNotification(AppNotification(
            notificationId: '',
            userId: doc.data()['userId'],
            title: 'Cảnh báo ngân sách',
            content: 'Giao dịch vừa sửa đã làm bạn tiêu vượt 90% ngân sách tháng $monthStrNew cho danh mục này.',
            status: 'unread',
            type: 'budget',
            createdAt: DateTime.now(),
          ));
        }
      }
    }
  }

  Future<void> deleteTransaction(AppTransaction tx) async {
    await _db.collection('transactions').doc(tx.transactionId).delete();

    // 1. Hoàn lại số dư ví
    final delta = tx.type == 'income' ? -tx.amount : tx.amount;
    await adjustWalletBalance(tx.walletId, delta);

    // 2. Hoàn lại số tiền đã tiêu trong ngân sách (nếu là chi tiêu)
    if (tx.type == 'expense') {
      final monthStr = DateFormat('MM/yyyy').format(tx.date);
      await adjustBudgetSpent(tx.categoryId, monthStr, -tx.amount);
    }

    // 3. Xóa ảnh local nếu có
    if (tx.image != null && tx.image!.isNotEmpty) {
      try {
        await StorageService().deleteImageByUrl(tx.image!);
      } catch (_) {
        // ignore errors
      }
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
      final list = snap.docs.map((d) => Budget.fromMap(d.data(), d.id)).toList();
      list.sort((a, b) => b.month.compareTo(a.month)); // Sort text MM/yyyy, not perfect but okay
      return list;
    });
  }

  Future<void> updateBudget(String budgetId, Map<String, dynamic> data) {
    return _db.collection('budgets').doc(budgetId).update(data);
  }

  Future<void> deleteBudget(String budgetId) {
    return _db.collection('budgets').doc(budgetId).delete();
  }

  /// Cập nhật số tiền đã chi tiêu của ngân sách (khi có giao dịch mới/xóa)
  Future<void> adjustBudgetSpent(String categoryId, String month, double delta) async {
    final query = await _db
        .collection('budgets')
        .where('categoryId', isEqualTo: categoryId)
        .where('month', isEqualTo: month)
        .limit(1)
        .get();
    if (query.docs.isNotEmpty) {
      final doc = query.docs.first;
      final limit = (doc.data()['limit'] as num).toDouble();
      final oldSpent = (doc.data()['spent'] as num).toDouble();
      final newSpent = oldSpent + delta;
      
      await doc.reference.update({
        'spent': FieldValue.increment(delta),
      });

      if (delta > 0 && oldSpent <= limit * 0.9 && newSpent > limit * 0.9) {
        await createNotification(AppNotification(
          notificationId: '',
          userId: doc.data()['userId'],
          title: 'Cảnh báo ngân sách',
          content: 'Bạn đã tiêu vượt 90% ngân sách tháng $month cho danh mục này.',
          status: 'unread',
          type: 'budget',
          createdAt: DateTime.now(),
        ));
      }
    }
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
      final list = snap.docs.map((d) => SavingGoal.fromMap(d.data(), d.id)).toList();
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
      final list = snap.docs.map((d) => AppNotification.fromMap(d.data(), d.id)).toList();
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
  Future<Budget?> getCategoryBudget(String categoryId, {String? month}) async {
    final now = DateTime.now();
    final monthStr = month ?? DateFormat('MM/yyyy').format(now);
    final query = await _db
        .collection('budgets')
        .where('categoryId', isEqualTo: categoryId)
        .where('month', isEqualTo: monthStr)
        .limit(1)
        .get();
    if (query.docs.isEmpty) return null;
    final doc = query.docs.first;
    return Budget.fromMap(doc.data(), doc.id);
  }

  /// Lấy số tiền đã chi tiêu của một danh mục (budget) hiện tại
  Future<double> getCategoryBudgetSpent(String categoryId) async {
    final budget = await getCategoryBudget(categoryId);
    return budget?.spent ?? 0;
  }

  Future<void> markNotificationRead(String notificationId) {
    return _db
        .collection('notifications')
        .doc(notificationId)
        .update({'status': 'read'});
  }
}
