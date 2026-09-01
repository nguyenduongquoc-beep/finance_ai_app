import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/transaction_model.dart';
import '../../models/category_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/stream_error_widget.dart';
import '../../widgets/app_snackbar.dart';

/// 19. Báo cáo AI - Tổng hợp tháng: tiết kiệm, chi nhiều nhất, tăng %, khuyến nghị
/// Có thể xuất PDF (TODO: dùng package pdf / printing để xuất file)
class AiReportScreen extends StatelessWidget {
  const AiReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final firestoreService = FirestoreService();
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Báo cáo tháng ${now.month}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () {
              AppSnackbar.show(context, 'TODO: Xuất PDF - dùng package pdf/printing');
            },
          ),
        ],
      ),
      body: StreamBuilder<List<AppTransaction>>(
        stream: firestoreService.streamTransactions(uid, from: monthStart),
        builder: (context, txSnap) {
          if (txSnap.hasError) return StreamErrorWidget(error: txSnap.error.toString());
          final transactions = txSnap.data ?? [];
          if (!txSnap.hasData) return const Center(child: CircularProgressIndicator());

          return StreamBuilder<List<Category>>(
            stream: firestoreService.streamCategories(uid),
            builder: (context, catSnap) {
              if (catSnap.hasError) return StreamErrorWidget(error: catSnap.error.toString());
              final categories = catSnap.data ?? [];

              final income = transactions
                  .where((t) => t.type == 'income')
                  .fold<double>(0, (a, t) => a + t.amount);
              final expense = transactions
                  .where((t) => t.type == 'expense')
                  .fold<double>(0, (a, t) => a + t.amount);
              final savings = income - expense;

              final Map<String, double> byCategory = {};
              for (final tx in transactions.where((t) => t.type == 'expense')) {
                byCategory[tx.categoryId] = (byCategory[tx.categoryId] ?? 0) + tx.amount;
              }
              String topCategoryName = 'Chưa có dữ liệu';
              double topAmount = 0;
              if (byCategory.isNotEmpty) {
                final topEntry =
                    byCategory.entries.reduce((a, b) => a.value > b.value ? a : b);
                topAmount = topEntry.value;
                final cat = categories
                    .where((c) => c.categoryId == topEntry.key)
                    .cast<Category?>()
                    .firstWhere((c) => true, orElse: () => null);
                topCategoryName = cat?.name ?? 'Khác';
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _reportRow('Tiết kiệm được', AppFormatters.currency(savings), AppColors.income),
                  _reportRow('Chi nhiều nhất', '$topCategoryName (${AppFormatters.currency(topAmount)})',
                      AppColors.expense),
                  _reportRow('Tổng thu', AppFormatters.currency(income), AppColors.textPrimary),
                  _reportRow('Tổng chi', AppFormatters.currency(expense), AppColors.textPrimary),
                  const SizedBox(height: 16),
                  Card(
                    color: AppColors.aiAccent.withOpacity(0.08),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.lightbulb_outline, color: AppColors.aiAccent),
                            SizedBox(width: 8),
                            Text('Khuyến nghị từ AI',
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          ]),
                          SizedBox(height: 8),
                          Text(
                            'Dựa trên dữ liệu chi tiêu tháng này, hãy xem mục AI Insight để '
                            'nhận phân tích chi tiết và gợi ý cắt giảm chi tiêu phù hợp.',
                            style: TextStyle(height: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _reportRow(String label, String value, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(label),
        trailing: Text(value,
            style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
