import '../models/transaction_model.dart';
import '../models/wallet_model.dart';
import '../models/saving_goal_model.dart';

/// Kết quả tính toán ảnh hưởng của giao dịch lên các ví và mục tiêu tiết kiệm
class TransactionEffects {
  final double? newSourceBalance;
  final double? newTargetBalance;
  final double? newGoalSavedAmount;

  const TransactionEffects({
    this.newSourceBalance,
    this.newTargetBalance,
    this.newGoalSavedAmount,
  });
}

/// Lớp xử lý nghiệp vụ tài chính thuần Dart (Pure Logic)
/// Giúp đảm bảo tính nhất quán số dư, không cho số dư âm, chặn nạp tiền vượt mục tiêu,
/// và hỗ trợ unit test độc lập không phụ thuộc Firestore.
class TransactionBusinessLogic {
  /// Validate số tiền giao dịch hợp lệ (> 0, hữu hạn, không NaN)
  static void validateAmount(double amount) {
    if (amount <= 0 || amount.isNaN || !amount.isFinite) {
      throw Exception('Số tiền giao dịch không hợp lệ.');
    }
  }

  /// Kiểm tra và tính toán ảnh hưởng khi tạo giao dịch mới
  static TransactionEffects processCreateTransaction({
    required AppTransaction tx,
    required Wallet wallet,
    Wallet? toWallet,
    SavingGoal? goal,
  }) {
    validateAmount(tx.amount);

    if (!wallet.isActive) {
      throw Exception('Ví đã bị ẩn hoặc không hoạt động.');
    }

    switch (tx.type) {
      case 'income':
        return TransactionEffects(
          newSourceBalance: wallet.balance + tx.amount,
        );

      case 'expense':
        if (tx.amount > wallet.balance) {
          throw Exception('Số dư ví không đủ để thực hiện giao dịch này.');
        }
        return TransactionEffects(
          newSourceBalance: wallet.balance - tx.amount,
        );

      case 'transfer':
        if (toWallet == null) {
          throw Exception('Ví đích không tồn tại.');
        }
        if (!toWallet.isActive) {
          throw Exception('Ví đích đã bị ẩn hoặc không hoạt động.');
        }
        if (tx.walletId == tx.toWalletId) {
          throw Exception('Ví nguồn và ví đích không được trùng nhau.');
        }
        if (tx.amount > wallet.balance) {
          throw Exception('Số dư ví không đủ để thực hiện giao dịch này.');
        }
        return TransactionEffects(
          newSourceBalance: wallet.balance - tx.amount,
          newTargetBalance: toWallet.balance + tx.amount,
        );

      case 'goal_deposit':
        if (goal == null) {
          throw Exception('Mục tiêu tiết kiệm không tồn tại.');
        }
        if (tx.amount > wallet.balance) {
          throw Exception('Số dư ví không đủ để thực hiện giao dịch này.');
        }
        final remaining = goal.targetAmount - goal.savedAmount;
        if (tx.amount > remaining) {
          throw Exception(
              'Số tiền nạp vượt quá số tiền còn thiếu của mục tiêu tiết kiệm.');
        }
        return TransactionEffects(
          newSourceBalance: wallet.balance - tx.amount,
          newGoalSavedAmount: goal.savedAmount + tx.amount,
        );

      case 'goal_withdraw':
        if (goal == null) {
          throw Exception('Mục tiêu tiết kiệm không tồn tại.');
        }
        if (tx.amount > goal.savedAmount) {
          throw Exception(
              'Số tiền rút vượt quá số tiền đã tiết kiệm trong mục tiêu.');
        }
        return TransactionEffects(
          newSourceBalance: wallet.balance + tx.amount,
          newGoalSavedAmount: goal.savedAmount - tx.amount,
        );

      default:
        throw Exception('Loại giao dịch không hợp lệ.');
    }
  }

  /// Kiểm tra và tính toán ảnh hưởng khi xóa giao dịch
  /// (Không chặn nếu ví bị ẩn isActive == false để hỗ trợ đối soát lịch sử)
  static TransactionEffects processDeleteTransaction({
    required AppTransaction tx,
    Wallet? wallet,
    Wallet? toWallet,
    SavingGoal? goal,
  }) {
    validateAmount(tx.amount);

    switch (tx.type) {
      case 'income':
        final currentBal = wallet?.balance ?? 0;
        return TransactionEffects(
          newSourceBalance: currentBal - tx.amount,
        );

      case 'expense':
        final currentBal = wallet?.balance ?? 0;
        return TransactionEffects(
          newSourceBalance: currentBal + tx.amount,
        );

      case 'transfer':
        final currentSource = wallet?.balance ?? 0;
        final currentTarget = toWallet?.balance ?? 0;
        return TransactionEffects(
          newSourceBalance: currentSource + tx.amount,
          newTargetBalance: currentTarget - tx.amount,
        );

      case 'goal_deposit':
        final currentBal = wallet?.balance ?? 0;
        final currentSaved = goal?.savedAmount ?? 0;
        return TransactionEffects(
          newSourceBalance: currentBal + tx.amount,
          newGoalSavedAmount:
              (currentSaved - tx.amount).clamp(0, double.infinity),
        );

      case 'goal_withdraw':
        final currentBal = wallet?.balance ?? 0;
        final currentSaved = goal?.savedAmount ?? 0;
        final targetAmount = goal?.targetAmount ?? double.infinity;
        return TransactionEffects(
          newSourceBalance: currentBal - tx.amount,
          newGoalSavedAmount: (currentSaved + tx.amount).clamp(0, targetAmount),
        );

      default:
        throw Exception('Loại giao dịch không hợp lệ.');
    }
  }

  /// Kiểm tra và tính toán ảnh hưởng khi sửa giao dịch an toàn
  /// Khóa sửa goal_deposit và goal_withdraw
  static Map<String, double> processUpdateTransaction({
    required AppTransaction oldTx,
    required AppTransaction newTx,
    required Wallet oldWallet,
    required Wallet newWallet,
    Wallet? oldToWallet,
    Wallet? newToWallet,
  }) {
    if (oldTx.type == 'goal_deposit' ||
        oldTx.type == 'goal_withdraw' ||
        newTx.type == 'goal_deposit' ||
        newTx.type == 'goal_withdraw') {
      throw Exception(
          'Giao dịch nạp/rút mục tiêu không thể sửa. Vui lòng xóa và tạo lại giao dịch.');
    }

    validateAmount(newTx.amount);

    // Kiểm tra ví chuyển tiền
    if (newTx.type == 'transfer') {
      if (newTx.toWalletId == null || newTx.toWalletId!.isEmpty) {
        throw Exception('Giao dịch chuyển tiền cần chỉ định ví đích.');
      }
      if (newTx.walletId == newTx.toWalletId) {
        throw Exception('Ví nguồn và ví đích không được trùng nhau.');
      }
    }

    // Kiểm tra ví mới isActive nếu đổi ví
    if (newTx.walletId != oldTx.walletId && !newWallet.isActive) {
      throw Exception('Ví đã bị ẩn hoặc không hoạt động.');
    }
    if (newTx.type == 'transfer') {
      if (newToWallet == null) {
        throw Exception('Ví đích không tồn tại.');
      }
      final isNewToWallet =
          oldTx.type != 'transfer' || newTx.toWalletId != oldTx.toWalletId;
      if (isNewToWallet && !newToWallet.isActive) {
        throw Exception('Ví đích đã bị ẩn hoặc không hoạt động.');
      }
    }

    // Tính toán số dư mới cho các ví liên quan
    final balanceMap = <String, double>{};

    // Khởi tạo số dư hiện tại từ đối tượng ví
    balanceMap[oldWallet.walletId] = oldWallet.balance;
    balanceMap[newWallet.walletId] = newWallet.balance;
    if (oldToWallet != null) {
      balanceMap[oldToWallet.walletId] = oldToWallet.balance;
    }
    if (newToWallet != null) {
      balanceMap[newToWallet.walletId] = newToWallet.balance;
    }

    // 1. Hoàn tác oldTx
    switch (oldTx.type) {
      case 'expense':
        balanceMap[oldTx.walletId] =
            (balanceMap[oldTx.walletId] ?? 0) + oldTx.amount;
        break;
      case 'income':
        balanceMap[oldTx.walletId] =
            (balanceMap[oldTx.walletId] ?? 0) - oldTx.amount;
        break;
      case 'transfer':
        balanceMap[oldTx.walletId] =
            (balanceMap[oldTx.walletId] ?? 0) + oldTx.amount;
        if (oldTx.toWalletId != null) {
          balanceMap[oldTx.toWalletId!] =
              (balanceMap[oldTx.toWalletId!] ?? 0) - oldTx.amount;
        }
        break;
    }

    // 2. Áp dụng newTx
    switch (newTx.type) {
      case 'expense':
        balanceMap[newTx.walletId] =
            (balanceMap[newTx.walletId] ?? 0) - newTx.amount;
        break;
      case 'income':
        balanceMap[newTx.walletId] =
            (balanceMap[newTx.walletId] ?? 0) + newTx.amount;
        break;
      case 'transfer':
        balanceMap[newTx.walletId] =
            (balanceMap[newTx.walletId] ?? 0) - newTx.amount;
        if (newTx.toWalletId != null) {
          balanceMap[newTx.toWalletId!] =
              (balanceMap[newTx.toWalletId!] ?? 0) + newTx.amount;
        }
        break;
    }

    // 3. Kiểm tra không ví nào bị âm số dư
    balanceMap.forEach((walletId, balance) {
      if (balance < 0) {
        throw Exception('Số dư ví không đủ để thực hiện giao dịch này.');
      }
    });

    return balanceMap;
  }
}
