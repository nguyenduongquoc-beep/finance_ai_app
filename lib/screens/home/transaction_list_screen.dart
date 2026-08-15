import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/transaction_model.dart';
import '../../models/category_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/transaction_card.dart';
import '../../widgets/stream_error_widget.dart';
import 'transaction_detail_screen.dart';

/// 10. Danh sách giao dịch - có filter theo Ngày / Tuần / Tháng
class TransactionListScreen extends StatefulWidget {
  const TransactionListScreen({super.key});

  @override
  State<TransactionListScreen> createState() => _TransactionListScreenState();
}

enum _FilterRange { day, week, month }

class _TransactionListScreenState extends State<TransactionListScreen> {
  final _firestoreService = FirestoreService();
  _FilterRange _filter = _FilterRange.month;
  bool _showAllHistory = false;

  DateTime get _fromDate {
    final now = DateTime.now();
    switch (_filter) {
      case _FilterRange.day:
        return DateTime(now.year, now.month, now.day);
      case _FilterRange.week:
        return now.subtract(Duration(days: now.weekday - 1));
      case _FilterRange.month:
        return DateTime(now.year, now.month, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Giao dịch'),
        actions: [
          IconButton(
            icon: Icon(_showAllHistory ? Icons.filter_list : Icons.history),
            tooltip: _showAllHistory ? 'Lọc theo thời gian' : 'Xem toàn bộ lịch sử',
            onPressed: () => setState(() => _showAllHistory = !_showAllHistory),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _filterChip('Hôm nay', _FilterRange.day),
                const SizedBox(width: 8),
                _filterChip('7 ngày qua', _FilterRange.week),
                const SizedBox(width: 8),
                _filterChip('Tháng này', _FilterRange.month),
              ],
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<AppTransaction>>(
        stream: _showAllHistory 
            ? _firestoreService.streamTransactions(uid) 
            : _firestoreService.streamTransactions(uid, from: _fromDate),
        builder: (context, txSnap) {
          if (txSnap.hasError) return StreamErrorWidget(error: txSnap.error.toString());
          final transactions = txSnap.data ?? [];
          if (!txSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (transactions.isEmpty) {
            return const Center(
              child: Text('Chưa có giao dịch nào', style: TextStyle(color: AppColors.textSecondary)),
            );
          }
          return StreamBuilder<List<Category>>(
            stream: _firestoreService.streamCategories(uid),
            builder: (context, catSnap) {
              if (catSnap.hasError) return StreamErrorWidget(error: catSnap.error.toString());
              final categories = catSnap.data ?? [];
              final grouped = _groupByDay(transactions);

              return ListView.builder(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                itemCount: grouped.length,
                itemBuilder: (context, i) {
                  final entry = grouped.entries.elementAt(i);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(entry.key,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                      ),
                      ...entry.value.map((tx) => TransactionCard(
                            transaction: tx,
                            category: categories
                                .where((c) => c.categoryId == tx.categoryId)
                                .cast<Category?>()
                                .firstWhere((c) => true, orElse: () => null),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => TransactionDetailScreen(transaction: tx),
                              ),
                            ),
                          )),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _filterChip(String label, _FilterRange range) {
    final selected = _filter == range;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = range),
      selectedColor: AppColors.primary,
      labelStyle: TextStyle(color: selected ? Colors.white : AppColors.textPrimary),
    );
  }

  Map<String, List<AppTransaction>> _groupByDay(List<AppTransaction> transactions) {
    final Map<String, List<AppTransaction>> grouped = {};
    for (final tx in transactions) {
      final key = AppFormatters.date(tx.date);
      grouped.putIfAbsent(key, () => []).add(tx);
    }
    return grouped;
  }
}
