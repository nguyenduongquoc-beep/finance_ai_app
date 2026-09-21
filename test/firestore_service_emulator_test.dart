import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:finance_ai_app/models/transaction_model.dart';
import 'package:finance_ai_app/models/wallet_model.dart';
import 'package:finance_ai_app/models/saving_goal_model.dart';
import 'package:finance_ai_app/utils/transaction_business_logic.dart';

void main() {
  group('Firestore Atomic & Security Rules Tests', () {
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
    });

    test('Atomic Create Transaction: wallet balance & goal savedAmount updated atomically', () async {
      // 1. Seed wallet document
      await fakeFirestore.collection('wallets').doc('w_1').set({
        'userId': 'u_1',
        'walletName': 'Ví Tiền Mặt',
        'balance': 500000.0,
        'initialBalance': 500000.0,
        'type': 'cash',
        'currency': 'VND',
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      // 2. Seed saving goal document
      await fakeFirestore.collection('savingGoals').doc('g_1').set({
        'userId': 'u_1',
        'name': 'Laptop mới',
        'targetAmount': 1000000.0,
        'savedAmount': 400000.0,
        'months': 6,
        'createdAt': DateTime.now().toIso8601String(),
      });

      final tx = AppTransaction(
        transactionId: 'tx_deposit_1',
        userId: 'u_1',
        walletId: 'w_1',
        categoryId: '',
        amount: 200000.0,
        type: 'goal_deposit',
        goalId: 'g_1',
        date: DateTime.now(),
      );

      // Run atomic Firestore transaction
      await fakeFirestore.runTransaction((txn) async {
        final wSnap = await txn.get(fakeFirestore.collection('wallets').doc('w_1'));
        final gSnap = await txn.get(fakeFirestore.collection('savingGoals').doc('g_1'));

        final wallet = Wallet.fromMap(wSnap.data()!, wSnap.id);
        final goal = SavingGoal.fromMap(gSnap.data()!, gSnap.id);

        final effects = TransactionBusinessLogic.processCreateTransaction(
          tx: tx,
          wallet: wallet,
          goal: goal,
        );

        txn.set(fakeFirestore.collection('transactions').doc(tx.transactionId), tx.toMap());
        txn.update(fakeFirestore.collection('wallets').doc('w_1'), {'balance': effects.newSourceBalance});
        txn.update(fakeFirestore.collection('savingGoals').doc('g_1'), {'savedAmount': effects.newGoalSavedAmount});
      });

      // Verify wallet balance updated atomically
      final updatedWalletDoc = await fakeFirestore.collection('wallets').doc('w_1').get();
      expect(updatedWalletDoc.data()!['balance'], equals(300000.0)); // 500,000 - 200,000

      // Verify goal savedAmount updated atomically
      final updatedGoalDoc = await fakeFirestore.collection('savingGoals').doc('g_1').get();
      expect(updatedGoalDoc.data()!['savedAmount'], equals(600000.0)); // 400,000 + 200,000

      // Verify transaction doc created
      final txDoc = await fakeFirestore.collection('transactions').doc('tx_deposit_1').get();
      expect(txDoc.exists, isTrue);
    });

    test('Atomic Delete Transaction: restores wallet balance and deletes tx doc', () async {
      // 1. Seed wallet
      await fakeFirestore.collection('wallets').doc('w_1').set({
        'userId': 'u_1',
        'walletName': 'Ví Tiền Mặt',
        'balance': 300000.0,
        'initialBalance': 500000.0,
        'type': 'cash',
        'currency': 'VND',
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(),
      });

      // 2. Seed transaction to delete
      final tx = AppTransaction(
        transactionId: 'tx_expense_1',
        userId: 'u_1',
        walletId: 'w_1',
        categoryId: 'cat_food',
        amount: 150000.0,
        type: 'expense',
        date: DateTime.now(),
      );
      await fakeFirestore.collection('transactions').doc(tx.transactionId).set(tx.toMap());

      // Run atomic delete transaction
      await fakeFirestore.runTransaction((txn) async {
        final txSnap = await txn.get(fakeFirestore.collection('transactions').doc(tx.transactionId));
        expect(txSnap.exists, isTrue);

        final wSnap = await txn.get(fakeFirestore.collection('wallets').doc('w_1'));
        final wallet = Wallet.fromMap(wSnap.data()!, wSnap.id);

        final effects = TransactionBusinessLogic.processDeleteTransaction(
          tx: tx,
          wallet: wallet,
        );

        txn.update(fakeFirestore.collection('wallets').doc('w_1'), {'balance': effects.newSourceBalance});
        txn.delete(fakeFirestore.collection('transactions').doc(tx.transactionId));
      });

      // Verify wallet balance restored
      final updatedWalletDoc = await fakeFirestore.collection('wallets').doc('w_1').get();
      expect(updatedWalletDoc.data()!['balance'], equals(450000.0)); // 300,000 + 150,000

      // Verify transaction doc deleted
      final txDoc = await fakeFirestore.collection('transactions').doc('tx_expense_1').get();
      expect(txDoc.exists, isFalse);
    });
  });
}
