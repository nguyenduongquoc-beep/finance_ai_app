import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/wallet_model.dart';
import '../models/category_model.dart';
import '../models/transaction_model.dart';
import '../models/budget_model.dart';
import '../models/saving_goal_model.dart';
import '../models/notification_model.dart';
import 'package:intl/intl.dart';

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

  // ---------------- TRANSACTIONS ----------------
  Future<String> createTransaction(AppTransaction tx) async {
    final ref = await _db.collection('transactions').add(tx.toMap());
    
    // 1. Cập nhật số dư ví tương ứng
    final delta = tx.type == 'income' ? tx.amount : -tx.amount;
    await adjustWalletBalance(tx.walletId, delta);
    
    // 2. Cập nhật số tiền đã tiêu trong ngân sách (nếu là chi tiêu)
    if (tx.type == 'expense') {
      final monthStr = DateFormat('MM/yyyy').format(tx.date);
      await adjustBudgetSpent(tx.categoryId, monthStr, tx.amount);
    }
    
    return ref.id;
  }

  Stream<List<AppTransaction>> streamTransactions(
      String userId, {
        DateTime? from,
        DateTime? to,
      }) {
    final query = _db
        .collection('transactions')
        .where('userId', isEqualTo: userId);
        
    return query.snapshots().map((snap) {
      var list = snap.docs.map((d) => AppTransaction.fromMap(d.data(), d.id)).toList();
      
      // Filter locally to avoid Firebase Composite Index requirement
      if (from != null) {
        list = list.where((t) => !t.date.isBefore(from)).toList();
      }
      if (to != null) {
        list = list.where((t) => !t.date.isAfter(to)).toList();
      }
      
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    });
  }

  Future<void> updateTransaction(String txId, Map<String, dynamic> data) {
    return _db.collection('transactions').doc(txId).update(data);
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
      await query.docs.first.reference.update({
        'spent': FieldValue.increment(delta),
      });
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

  /// Lấy budget cho danh mục trong tháng hiện tại
  Future<Budget?> getCategoryBudget(String categoryId) async {
    final now = DateTime.now();
    final monthStr = DateFormat('MM/yyyy').format(now);
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
