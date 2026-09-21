import 'package:flutter_test/flutter_test.dart';
import 'package:finance_ai_app/models/transaction_model.dart';
import 'package:finance_ai_app/models/wallet_model.dart';
import 'package:finance_ai_app/models/saving_goal_model.dart';
import 'package:finance_ai_app/utils/transaction_business_logic.dart';

void main() {
  group('TransactionBusinessLogic Tests', () {
    late Wallet sourceWallet;
    late Wallet targetWallet;
    late Wallet inactiveWallet;
    late SavingGoal goal;

    setUp(() {
      sourceWallet = Wallet(
        walletId: 'w_source',
        userId: 'u_1',
        walletName: 'Ví Tiền Mặt',
        type: 'cash',
        balance: 500000.0,
        createdAt: DateTime.now(),
        isActive: true,
      );

      targetWallet = Wallet(
        walletId: 'w_target',
        userId: 'u_1',
        walletName: 'Ví Ngân Hàng',
        type: 'bank',
        balance: 200000.0,
        createdAt: DateTime.now(),
        isActive: true,
      );

      inactiveWallet = Wallet(
        walletId: 'w_inactive',
        userId: 'u_1',
        walletName: 'Ví Đã Ẩn',
        type: 'cash',
        balance: 100000.0,
        createdAt: DateTime.now(),
        isActive: false,
      );

      goal = SavingGoal(
        goalId: 'g_laptop',
        userId: 'u_1',
        name: 'Mua Laptop',
        targetAmount: 1000000.0,
        savedAmount: 800000.0, // Còn thiếu 200,000đ
        months: 6,
        createdAt: DateTime.now(),
      );
    });

    test('1. Nạp mục tiêu bằng đúng số tiền còn thiếu: thành công', () {
      final tx = AppTransaction(
        transactionId: 'tx_1',
        userId: 'u_1',
        walletId: 'w_source',
        categoryId: '',
        amount: 200000.0, // Đúng 200,000đ còn thiếu
        type: 'goal_deposit',
        goalId: 'g_laptop',
        date: DateTime.now(),
      );

      final effects = TransactionBusinessLogic.processCreateTransaction(
        tx: tx,
        wallet: sourceWallet,
        goal: goal,
      );

      expect(effects.newSourceBalance, equals(300000.0)); // 500,000 - 200,000
      expect(effects.newGoalSavedAmount,
          equals(1000000.0)); // 800,000 + 200,000 = 1,000,000
    });

    test('2. Nạp vượt số tiền còn thiếu: thất bại, không trừ ví', () {
      final tx = AppTransaction(
        transactionId: 'tx_2',
        userId: 'u_1',
        walletId: 'w_source',
        categoryId: '',
        amount: 300000.0, // Vượt 200,000đ còn thiếu
        type: 'goal_deposit',
        goalId: 'g_laptop',
        date: DateTime.now(),
      );

      expect(
        () => TransactionBusinessLogic.processCreateTransaction(
          tx: tx,
          wallet: sourceWallet,
          goal: goal,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Số tiền nạp vượt quá số tiền còn thiếu'),
          ),
        ),
      );
    });

    test('3. Chi tiêu vượt số dư ví: thất bại', () {
      final tx = AppTransaction(
        transactionId: 'tx_3',
        userId: 'u_1',
        walletId: 'w_source',
        categoryId: 'cat_food',
        amount: 600000.0, // Vượt số dư 500,000đ
        type: 'expense',
        date: DateTime.now(),
      );

      expect(
        () => TransactionBusinessLogic.processCreateTransaction(
          tx: tx,
          wallet: sourceWallet,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Số dư ví không đủ để thực hiện giao dịch này'),
          ),
        ),
      );
    });

    test('4. Chuyển tiền vượt số dư ví hoặc ví trùng nhau: thất bại', () {
      final txExceed = AppTransaction(
        transactionId: 'tx_4a',
        userId: 'u_1',
        walletId: 'w_source',
        toWalletId: 'w_target',
        categoryId: '',
        amount: 600000.0, // Vượt số dư
        type: 'transfer',
        date: DateTime.now(),
      );

      expect(
        () => TransactionBusinessLogic.processCreateTransaction(
          tx: txExceed,
          wallet: sourceWallet,
          toWallet: targetWallet,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Số dư ví không đủ để thực hiện giao dịch này'),
          ),
        ),
      );

      final txSameWallet = AppTransaction(
        transactionId: 'tx_4b',
        userId: 'u_1',
        walletId: 'w_source',
        toWalletId: 'w_source',
        categoryId: '',
        amount: 100000.0,
        type: 'transfer',
        date: DateTime.now(),
      );

      expect(
        () => TransactionBusinessLogic.processCreateTransaction(
          tx: txSameWallet,
          wallet: sourceWallet,
          toWallet: sourceWallet,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Ví nguồn và ví đích không được trùng nhau'),
          ),
        ),
      );
    });

    test('5. Validate số tiền amount <= 0, NaN, Infinity: thất bại', () {
      expect(
        () => TransactionBusinessLogic.validateAmount(0),
        throwsA(isA<Exception>()),
      );
      expect(
        () => TransactionBusinessLogic.validateAmount(-50000),
        throwsA(isA<Exception>()),
      );
      expect(
        () => TransactionBusinessLogic.validateAmount(double.nan),
        throwsA(isA<Exception>()),
      );
      expect(
        () => TransactionBusinessLogic.validateAmount(double.infinity),
        throwsA(isA<Exception>()),
      );
    });

    test('6. Xóa giao dịch chi (kể cả khi ví bị ẩn): hoàn tiền chính xác về ví',
        () {
      final txExpense = AppTransaction(
        transactionId: 'tx_5',
        userId: 'u_1',
        walletId: 'w_inactive', // Ví đang bị ẩn
        categoryId: 'cat_food',
        amount: 150000.0,
        type: 'expense',
        date: DateTime.now(),
      );

      final effects = TransactionBusinessLogic.processDeleteTransaction(
        tx: txExpense,
        wallet: inactiveWallet,
      );

      expect(effects.newSourceBalance,
          equals(250000.0)); // 100,000 + 150,000 = 250,000
    });

    test('7. Xóa giao dịch chuyển tiền: hoàn lại ví nguồn và trừ ví đích', () {
      final txTransfer = AppTransaction(
        transactionId: 'tx_6',
        userId: 'u_1',
        walletId: 'w_source',
        toWalletId: 'w_target',
        categoryId: '',
        amount: 100000.0,
        type: 'transfer',
        date: DateTime.now(),
      );

      final effects = TransactionBusinessLogic.processDeleteTransaction(
        tx: txTransfer,
        wallet: sourceWallet,
        toWallet: targetWallet,
      );

      expect(effects.newSourceBalance, equals(600000.0)); // 500,000 + 100,000
      expect(effects.newTargetBalance, equals(100000.0)); // 200,000 - 100,000
    });

    test('8. Xóa nạp/rút mục tiêu: ví và savedAmount được hoàn tác chính xác',
        () {
      final txDeposit = AppTransaction(
        transactionId: 'tx_7a',
        userId: 'u_1',
        walletId: 'w_source',
        categoryId: '',
        amount: 200000.0,
        type: 'goal_deposit',
        goalId: 'g_laptop',
        date: DateTime.now(),
      );

      final effectsDep = TransactionBusinessLogic.processDeleteTransaction(
        tx: txDeposit,
        wallet: sourceWallet,
        goal: goal,
      );

      expect(
          effectsDep.newSourceBalance, equals(700000.0)); // 500,000 + 200,000
      expect(
          effectsDep.newGoalSavedAmount, equals(600000.0)); // 800,000 - 200,000

      final txWithdraw = AppTransaction(
        transactionId: 'tx_7b',
        userId: 'u_1',
        walletId: 'w_source',
        categoryId: '',
        amount: 100000.0,
        type: 'goal_withdraw',
        goalId: 'g_laptop',
        date: DateTime.now(),
      );

      final effectsWith = TransactionBusinessLogic.processDeleteTransaction(
        tx: txWithdraw,
        wallet: sourceWallet,
        goal: goal,
      );

      expect(
          effectsWith.newSourceBalance, equals(400000.0)); // 500,000 - 100,000
      expect(effectsWith.newGoalSavedAmount,
          equals(900000.0)); // 800,000 + 100,000
    });

    test('9. Khóa sửa giao dịch nạp/rút mục tiêu', () {
      final oldTx = AppTransaction(
        transactionId: 'tx_8',
        userId: 'u_1',
        walletId: 'w_source',
        categoryId: '',
        amount: 100000.0,
        type: 'goal_deposit',
        goalId: 'g_laptop',
        date: DateTime.now(),
      );

      final newTx = AppTransaction(
        transactionId: 'tx_8',
        userId: 'u_1',
        walletId: 'w_source',
        categoryId: '',
        amount: 150000.0,
        type: 'goal_deposit',
        goalId: 'g_laptop',
        date: DateTime.now(),
      );

      expect(
        () => TransactionBusinessLogic.processUpdateTransaction(
          oldTx: oldTx,
          newTx: newTx,
          oldWallet: sourceWallet,
          newWallet: sourceWallet,
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Giao dịch nạp/rút mục tiêu không thể sửa'),
          ),
        ),
      );
    });
  });
}
