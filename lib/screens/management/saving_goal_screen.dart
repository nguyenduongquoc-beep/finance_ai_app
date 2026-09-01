import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:percent_indicator/percent_indicator.dart';
import '../../models/saving_goal_model.dart';
import '../../services/firestore_service.dart';
import '../../services/ai_service.dart';
import '../../services/theme_controller.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/stream_error_widget.dart';

/// 16. Mục tiêu tiết kiệm - vd: Laptop 25 triệu, đã tiết kiệm 8 triệu (32%)
class SavingGoalScreen extends StatelessWidget {
  const SavingGoalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, _, __) {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        final firestoreService = FirestoreService();

        return Scaffold(
          backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Mục tiêu tiết kiệm')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: () => _showGoalDialog(context, firestoreService, uid),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Thêm mục tiêu', style: TextStyle(color: Colors.white)),
      ),
      body: StreamBuilder<List<SavingGoal>>(
        stream: firestoreService.streamSavingGoals(uid),
        builder: (context, snap) {
          if (snap.hasError) return StreamErrorWidget(error: snap.error.toString());
          final goals = snap.data ?? [];
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (goals.isEmpty) {
            return _buildEmptyState(context, firestoreService, uid);
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: goals.length,
            itemBuilder: (context, i) => _GoalCard(
              goal: goals[i],
              firestoreService: firestoreService,
            ),
          );
        },
      ),
    );
  },
);
  }

  Widget _buildEmptyState(
      BuildContext context, FirestoreService fs, String uid) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.savings_outlined,
                  size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text('Chưa có mục tiêu tiết kiệm',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text('Tạo mục tiêu để AI giúp bạn lên kế hoạch tiết kiệm!',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => _showGoalDialog(context, fs, uid),
              icon: const Icon(Icons.add),
              label: const Text('Tạo mục tiêu đầu tiên'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }

  void _showGoalDialog(
      BuildContext context, FirestoreService firestoreService, String uid) {
    final nameController = TextEditingController();
    final amountController = TextEditingController();
    final monthsController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Mục tiêu tiết kiệm mới'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Tên mục tiêu',
                hintText: 'vd: Mua Laptop',
                prefixIcon: Icon(Icons.flag_outlined),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Số tiền cần (đ)',
                prefixIcon: Icon(Icons.attach_money),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: monthsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Số tháng để đạt mục tiêu',
                prefixIcon: Icon(Icons.calendar_month_outlined),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              final target = AppFormatters.parseCurrencyInput(amountController.text);
              final months = int.tryParse(monthsController.text) ?? 1;
              final name = nameController.text.trim();
              if (name.isEmpty || target <= 0) return;
              await firestoreService.createSavingGoal(SavingGoal(
                goalId: '',
                userId: uid,
                name: name,
                targetAmount: target,
                months: months,
                createdAt: DateTime.now(),
              ));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Tạo mục tiêu'),
          ),
        ],
      ),
    );
  }
}

class _GoalCard extends StatefulWidget {
  final SavingGoal goal;
  final FirestoreService firestoreService;

  const _GoalCard({required this.goal, required this.firestoreService});

  @override
  State<_GoalCard> createState() => _GoalCardState();
}

class _GoalCardState extends State<_GoalCard> {
  final _aiService = AiService();
  String? _aiPlan;
  bool _isLoadingPlan = false;
  bool _planExpanded = false;

  bool get _isCompleted => widget.goal.percentComplete >= 1.0;

  Future<void> _loadAiPlan() async {
    setState(() => _isLoadingPlan = true);
    try {
      final plan = await _aiService.generateSavingPlan(
        goalName: widget.goal.name,
        targetAmount: widget.goal.targetAmount,
        months: widget.goal.months,
      );
      setState(() {
        _aiPlan = plan;
        _isLoadingPlan = false;
        _planExpanded = true;
      });
    } catch (_) {
      setState(() => _isLoadingPlan = false);
    }
  }

  Future<void> _addDeposit() async {
    final amountController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Nạp tiền vào "${widget.goal.name}"'),
        content: TextField(
          controller: amountController,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Số tiền nạp (đ)',
            prefixIcon: Icon(Icons.add_circle_outline),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Nạp'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final deposit = AppFormatters.parseCurrencyInput(amountController.text);
      if (deposit > 0) {
        final newSaved =
            (widget.goal.savedAmount + deposit).clamp(0, widget.goal.targetAmount);
        await widget.firestoreService.updateSavingGoal(
          widget.goal.goalId,
          {'savedAmount': newSaved},
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final pct = goal.percentComplete;
    final color = _isCompleted
        ? AppColors.income
        : pct > 0.75
            ? AppColors.primary
            : AppColors.aiAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 10,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(goal.name,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.bold)),
                          if (_isCompleted) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.income,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text('Hoàn thành! 🎉',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 11)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('Mục tiêu: ${AppFormatters.currency(goal.targetAmount)}',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                Text(
                  '${(pct * 100).round()}%',
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 22),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Progress bar
            LinearPercentIndicator(
              lineHeight: 12,
              percent: pct.clamp(0.0, 1.0),
              backgroundColor: Colors.grey.shade200,
              linearGradient: LinearGradient(colors: [
                color.withOpacity(0.7),
                color,
              ]),
              barRadius: const Radius.circular(8),
              padding: EdgeInsets.zero,
              animation: true,
              animationDuration: 800,
            ),
            const SizedBox(height: 10),
            // Amount row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Đã tiết kiệm: ${AppFormatters.currency(goal.savedAmount)}',
                  style: TextStyle(
                      fontSize: 13,
                      color: color,
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  'Còn: ${AppFormatters.currency(goal.targetAmount - goal.savedAmount)}',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
            if (!_isCompleted) ...[
              const SizedBox(height: 6),
              Text(
                'Cần ${AppFormatters.currency(goal.monthlyRequired)}/tháng '
                '≈ ${AppFormatters.currency(goal.dailyRequired)}/ngày',
                style:
                    TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 14),
            // Action buttons
            if (!_isCompleted)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _addDeposit,
                      icon: const Icon(Icons.savings_outlined, size: 16),
                      label: const Text('Nạp tiền', style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_aiPlan != null || _isLoadingPlan)
                          ? () => setState(() => _planExpanded = !_planExpanded)
                          : _loadAiPlan,
                      icon: _isLoadingPlan
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.aiAccent))
                          : const Icon(Icons.auto_awesome, size: 16),
                      label: Text(
                        _isLoadingPlan
                            ? 'Đang phân tích...'
                            : _aiPlan != null
                                ? (_planExpanded ? 'Ẩn kế hoạch' : 'Xem kế hoạch')
                                : 'AI Kế hoạch',
                        style: const TextStyle(fontSize: 13),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.aiAccent,
                        side: const BorderSide(color: AppColors.aiAccent),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            // AI Plan
            if (_aiPlan != null && _planExpanded) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.aiAccent.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: AppColors.aiAccent.withOpacity(0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.auto_awesome,
                        size: 16, color: AppColors.aiAccent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_aiPlan!,
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: AppColors.textPrimary)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
