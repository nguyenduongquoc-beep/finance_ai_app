import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/transaction_model.dart';
import '../../models/category_model.dart';
import '../../services/firestore_service.dart';
import '../../services/theme_controller.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/transaction_card.dart';
import '../../widgets/stream_error_widget.dart';
import 'transaction_detail_screen.dart';

/// 10. Danh sách giao dịch - có bộ lọc tìm kiếm, loại giao dịch, ngày/tháng
class TransactionListScreen extends StatefulWidget {
  const TransactionListScreen({super.key});

  @override
  State<TransactionListScreen> createState() => _TransactionListScreenState();
}

class _TransactionListScreenState extends State<TransactionListScreen> {
  final _firestoreService = FirestoreService();
  final _searchController = TextEditingController();
  
  String _searchQuery = '';
  String _typeFilter = 'all'; // 'all' | 'expense' | 'income'
  DateTime? _selectedDate;    // ngày cụ thể được chọn (null = không lọc theo ngày)
  DateTime? _selectedMonth;   // tháng cụ thể được chọn (null = không lọc theo tháng)

  late final String _uid;
  late Stream<List<AppTransaction>> _transactionsStream;
  late final Stream<List<Category>> _categoriesStream;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _categoriesStream = _firestoreService.streamCategories(_uid);
    _transactionsStream = _buildStream(_uid);
  }

  void _refreshTransactionsStream() {
    _transactionsStream = _buildStream(_uid);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Stream<List<AppTransaction>> _buildStream(String uid) {
    if (_selectedDate != null) {
      final start = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
      final end = start.add(const Duration(days: 1)).subtract(const Duration(seconds: 1));
      return _firestoreService.streamTransactions(uid, from: start, to: end);
    }
    if (_selectedMonth != null) {
      final start = DateTime(_selectedMonth!.year, _selectedMonth!.month, 1);
      final end = DateTime(_selectedMonth!.year, _selectedMonth!.month + 1, 1)
          .subtract(const Duration(seconds: 1));
      return _firestoreService.streamTransactions(uid, from: start, to: end);
    }
    return _firestoreService.streamTransactions(uid); // mặc định: toàn bộ lịch sử
  }

  String _formatMonthHeader(String monthStr) {
    final parts = monthStr.split('/');
    if (parts.length == 2) {
      final month = int.tryParse(parts[0]) ?? 0;
      final year = parts[1];
      return 'Tháng $month, $year';
    }
    return monthStr;
  }

  String _formatDayHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final compareDate = DateTime(date.year, date.month, date.day);

    if (compareDate == today) {
      return 'Hôm nay';
    } else if (compareDate == yesterday) {
      return 'Hôm qua';
    } else {
      final dayStr = date.day.toString();
      final monthStr = date.month.toString().padLeft(2, '0');
      return '$dayStr tháng $monthStr';
    }
  }

  Future<void> _selectSpecificDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _selectedMonth = null;
        _refreshTransactionsStream();
      });
    }
  }

  Future<void> _selectSpecificMonth() async {
    final now = DateTime.now();
    int selectedMonthVal = _selectedMonth?.month ?? now.month;
    int selectedYearVal = _selectedMonth?.year ?? now.year;
    final List<int> years = List.generate(5, (index) => now.year - 4 + index);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Chọn tháng/năm'),
              content: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  DropdownButton<int>(
                    value: selectedMonthVal,
                    items: List.generate(12, (index) => index + 1).map((m) {
                      return DropdownMenuItem<int>(
                        value: m,
                        child: Text('Tháng $m'),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setDialogState(() => selectedMonthVal = v);
                      }
                    },
                  ),
                  DropdownButton<int>(
                    value: selectedYearVal,
                    items: years.map((y) {
                      return DropdownMenuItem<int>(
                        value: y,
                        child: Text(y.toString()),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setDialogState(() => selectedYearVal = v);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Chọn'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true) {
      setState(() {
        _selectedMonth = DateTime(selectedYearVal, selectedMonthVal, 1);
        _selectedDate = null;
        _refreshTransactionsStream();
      });
    }
  }

  void _showFilterOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Lọc giao dịch',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.today, color: AppColors.primary),
                title: Text('Chọn theo ngày cụ thể', style: GoogleFonts.inter()),
                onTap: () {
                  Navigator.pop(context);
                  _selectSpecificDate();
                },
              ),
              ListTile(
                leading: const Icon(Icons.calendar_month, color: AppColors.primary),
                title: Text('Chọn theo tháng', style: GoogleFonts.inter()),
                onTap: () {
                  Navigator.pop(context);
                  _selectSpecificMonth();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTypeTag(String label, String type) {
    final isActive = _typeFilter == type;
    return GestureDetector(
      onTap: () => setState(() => _typeFilter = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? Colors.transparent : AppColors.textSecondary.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: isActive ? Colors.white : AppColors.textPrimary,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
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

  Map<String, List<AppTransaction>> _groupByMonth(List<AppTransaction> transactions) {
    final Map<String, List<AppTransaction>> grouped = {};
    for (final tx in transactions) {
      final key = AppFormatters.month(tx.date);
      grouped.putIfAbsent(key, () => []).add(tx);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            title: Text(
              'Giao dịch',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.bold,
                fontSize: 24,
                color: AppColors.textPrimary,
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.calendar_today_outlined, color: AppColors.textPrimary),
                onPressed: () => _showFilterOptions(context),
              ),
            ],
          ),
          body: Column(
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Tìm kiếm giao dịch...',
                    hintStyle: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 14),
                    prefixIcon: Icon(Icons.search, color: AppColors.textSecondary, size: 20),
                    filled: true,
                    fillColor: AppColors.card,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
          ),
          
          // Type filter tags row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildTypeTag('Tất cả', 'all'),
                const SizedBox(width: 8),
                _buildTypeTag('Thu nhập', 'income'),
                const SizedBox(width: 8),
                _buildTypeTag('Chi tiêu', 'expense'),
              ],
            ),
          ),
          
          // Date Filter Chip (if active)
          if (_selectedDate != null || _selectedMonth != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  label: Text(
                    _selectedDate != null
                        ? '📅 ${AppFormatters.date(_selectedDate!)}'
                        : '📅 ${_formatMonthHeader(AppFormatters.month(_selectedMonth!))}',
                    style: GoogleFonts.inter(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide.none,
                  ),
                  deleteIcon: const Icon(Icons.close, size: 16, color: AppColors.primary),
                  onDeleted: () {
                    setState(() {
                      _selectedDate = null;
                      _selectedMonth = null;
                      _refreshTransactionsStream();
                    });
                  },
                ),
              ),
            ),
            
          // Transaction List
          Expanded(
            child: StreamBuilder<List<AppTransaction>>(
              stream: _transactionsStream,
              builder: (context, txSnap) {
                if (txSnap.hasError) return StreamErrorWidget(error: txSnap.error.toString());
                if (!txSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                final transactions = txSnap.data ?? [];
                if (transactions.isEmpty && _selectedDate == null && _selectedMonth == null) {
                  return Center(
                    child: Text(
                      'Chưa có giao dịch nào',
                      style: GoogleFonts.inter(color: AppColors.textSecondary),
                    ),
                  );
                }
                
                return StreamBuilder<List<Category>>(
                  stream: _categoriesStream,
                  builder: (context, catSnap) {
                    if (catSnap.hasError) return StreamErrorWidget(error: catSnap.error.toString());
                    final categories = catSnap.data ?? [];
                    
                    // Client-side filtering
                    final filteredTransactions = transactions.where((tx) {
                      final category = categories.cast<Category?>().firstWhere(
                        (c) => c?.categoryId == tx.categoryId,
                        orElse: () => null,
                      );
                      
                      final matchesSearch = _searchQuery.isEmpty ||
                          (tx.note?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
                          (category?.name.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
                          
                      final matchesType = _typeFilter == 'all' || tx.type == _typeFilter;
                      
                      return matchesSearch && matchesType;
                    }).toList();
                    
                    if (filteredTransactions.isEmpty) {
                      return Center(
                        child: Text(
                          'Không tìm thấy giao dịch phù hợp',
                          style: GoogleFonts.inter(color: AppColors.textSecondary),
                        ),
                      );
                    }
                    
                    // Display modes:
                    // 1. Specific Date Selected -> flat list
                    if (_selectedDate != null) {
                      return ListView.builder(
                        padding: const EdgeInsets.only(top: 8, bottom: 24),
                        itemCount: filteredTransactions.length,
                        itemBuilder: (context, idx) {
                          final tx = filteredTransactions[idx];
                          return TransactionCard(
                            transaction: tx,
                            category: categories.cast<Category?>().firstWhere(
                              (c) => c?.categoryId == tx.categoryId,
                              orElse: () => null,
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => TransactionDetailScreen(transaction: tx),
                              ),
                            ),
                          );
                        },
                      );
                    }
                    
                    // 2. Specific Month Selected -> group by day
                    if (_selectedMonth != null) {
                      final groupedByDay = _groupByDay(filteredTransactions);
                      return ListView.builder(
                        padding: const EdgeInsets.only(top: 8, bottom: 24),
                        itemCount: groupedByDay.length,
                        itemBuilder: (context, i) {
                          final entry = groupedByDay.entries.elementAt(i);
                          final firstTx = entry.value.first;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: Text(
                                  _formatDayHeader(firstTx.date),
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textSecondary,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              ...entry.value.map((tx) => TransactionCard(
                                    transaction: tx,
                                    category: categories.cast<Category?>().firstWhere(
                                      (c) => c?.categoryId == tx.categoryId,
                                      orElse: () => null,
                                    ),
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
                    }
                    
                    // 3. Default (All history / no date-month filter) -> group by month
                    final groupedByMonth = _groupByMonth(filteredTransactions);
                    return ListView.builder(
                      padding: const EdgeInsets.only(top: 8, bottom: 24),
                      itemCount: groupedByMonth.length,
                      itemBuilder: (context, i) {
                        final entry = groupedByMonth.entries.elementAt(i);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Text(
                                _formatMonthHeader(entry.key),
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            ...entry.value.map((tx) => TransactionCard(
                                  transaction: tx,
                                  category: categories.cast<Category?>().firstWhere(
                                    (c) => c?.categoryId == tx.categoryId,
                                    orElse: () => null,
                                  ),
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
          ),
            ],
          ),
        );
      },
    );
  }
}
