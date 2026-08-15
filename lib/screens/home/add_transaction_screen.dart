import 'dart:typed_data';
import '../../services/ai_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, debugPrint;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/wallet_model.dart';
import '../../models/category_model.dart';
import '../../models/transaction_model.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../../services/template_service.dart';
import '../../utils/constants.dart';
import '../../utils/validation_utils.dart';
import '../../utils/formatters.dart';
import '../../models/quick_template.dart';
import '../../widgets/stream_error_widget.dart';
import '../../widgets/custom_numpad.dart';
import '../../widgets/quick_template_chip.dart';

class AddTransactionScreen extends StatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _locationController = TextEditingController();
  final _picker = ImagePicker();

  final _firestoreService = FirestoreService();
  final _storageService = StorageService();
  final _templateService = TemplateService();

  String _type = 'expense';
  String? _selectedWalletId;
  String? _selectedCategoryId;
  DateTime _selectedDate = DateTime.now();
  Uint8List? _receiptImageBytes;
  bool _isSaving = false;
  bool _walletBalanceExceeded = false;
  bool _budgetExceeded = false;
  bool _isParsing = false;
  bool _isValidating = false;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final ImageSource source = ImageSource.camera;
// Request camera permission on mobile platforms
if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
  var status = await Permission.camera.request();
  if (!status.isGranted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quyền truy cập camera bị từ chối')));
    return;
  }
}
final picked = await _picker.pickImage(source: source, imageQuality: 70);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() => _receiptImageBytes = bytes);
      // After selecting image, automatically parse receipt
      await _parseReceipt();
    }
  }

  // Parse receipt image using AI service and pre-fill fields
  Future<void> _parseReceipt() async {
    if (_receiptImageBytes == null) return;
    // Clear note and location before filling new data
    _noteController.clear();
    _locationController.clear();
    setState(() => _isParsing = true);
    final ai = AiService();
    try {
      final info = await ai.extractReceiptInfo(_receiptImageBytes!);
      if (info != null) {
        // Fill controllers with extracted receipt info
        if (info.total > 0) {
          _amountController.text = AppFormatters.number(info.total);
        }
        if (info.date != null) {
          _selectedDate = info.date!;
        }
        // Note: prioritize items, fall back to merchant name
        if (info.items != null && info.items!.isNotEmpty) {
          final itemLines = info.items!
              .map((it) => '${it.description}: ${AppFormatters.number(it.amount)}đ')
              .join('\n');
          _noteController.text = itemLines;
        } else if (info.merchant.isNotEmpty) {
          _noteController.text = info.merchant;
        }
        // Location (address)
        if (info.address != null && info.address!.isNotEmpty) {
          _locationController.text = info.address!;
        }
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã trích xuất thông tin hoá đơn')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể trích xuất thông tin hoá đơn')));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi khi trích xuất hoá đơn: $e')));
    }
    setState(() => _isParsing = false);
    await _runValidation();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _showNumpad() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CustomNumpad(initialValue: _amountController.text),
    );
    if (result != null) {
      setState(() => _amountController.text = result);
      await _runValidation();
    }
  }

  Future<void> _runValidation() async {
    setState(() => _isValidating = true);
    try {
      final amount = AppFormatters.parseCurrencyInput(_amountController.text);
      
      // Nếu là thu nhập (income) thì không bao giờ bị vượt quá số dư ví hay ngân sách chi tiêu
      if (_type == 'income') {
        setState(() {
          _walletBalanceExceeded = false;
          _budgetExceeded = false;
        });
        return;
      }

      if (_selectedWalletId != null) {
        final exceed = await ValidationUtils.exceedsWalletBalance(
          walletId: _selectedWalletId!,
          amount: amount,
          firestoreService: _firestoreService,
        );
        setState(() => _walletBalanceExceeded = exceed);
      }
      if (_selectedCategoryId != null) {
        final exceed = await ValidationUtils.exceedsCategoryBudget(
          categoryId: _selectedCategoryId!,
          amount: amount,
          firestoreService: _firestoreService,
        );
        setState(() => _budgetExceeded = exceed);
      }
    } catch (e) {
      debugPrint('⚠️ Lỗi khi kiểm tra vượt số dư ví/ngân sách: $e');
      setState(() {
        _walletBalanceExceeded = false;
        _budgetExceeded = false;
      });
    } finally {
      if (mounted) {
        setState(() => _isValidating = false);
      }
    }
  }

  Future<void> _saveAsTemplate() async {
    final titleCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lưu mẫu giao dịch'),
        content: TextField(
          controller: titleCtrl,
          decoration: const InputDecoration(labelText: 'Tên mẫu'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lưu')),
        ],
      ),
    );
    if (confirmed == true && titleCtrl.text.isNotEmpty) {
      final amount = AppFormatters.parseCurrencyInput(_amountController.text);
      await _templateService.createTemplate(
        title: titleCtrl.text,
        amount: amount,
        type: _type,
        walletId: _selectedWalletId ?? '',
        categoryId: _selectedCategoryId ?? '',
        note: _noteController.text,
        location: _locationController.text,
        date: _selectedDate,
        imagePath: null,
      );
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu mẫu')));
    }
  }

  Future<void> _handleSave() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final amount = AppFormatters.parseCurrencyInput(_amountController.text);

    if (uid == null || amount <= 0 || _selectedWalletId == null || _selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập đầy đủ số tiền, ví và danh mục')));
      return;
    }
    if (_walletBalanceExceeded) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Số tiền vượt quá số dư ví')));
      return;
    }
    if (_budgetExceeded) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Giao dịch sẽ vượt quá ngân sách danh mục')));
      return;
    }

    setState(() => _isSaving = true);
    try {
      String? imageUrl;
      if (_receiptImageBytes != null) {
        try {
          imageUrl = await _storageService.uploadReceiptImage(uid, _receiptImageBytes!);
        } catch (e) {
          debugPrint('⚠️ Upload ảnh hóa đơn thất bại, vẫn tiếp tục lưu giao dịch không kèm ảnh: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Không thể lưu ảnh hóa đơn (lỗi kết nối), đang tiếp tục lưu giao dịch...')),
            );
          }
        }
      }
      final tx = AppTransaction(
        transactionId: '',
        userId: uid,
        walletId: _selectedWalletId!,
        categoryId: _selectedCategoryId!,
        amount: amount,
        type: _type,
        note: _noteController.text.trim(),
        image: imageUrl,
        location: _locationController.text.trim(),
        date: _selectedDate,
      );
      await _firestoreService.createTransaction(tx);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      debugPrint('❌ Lỗi khi lưu giao dịch: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể lưu giao dịch. Vui lòng kiểm tra kết nối mạng và thử lại.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final accentColor = _type == 'income' ? AppColors.income : AppColors.expense;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Thêm giao dịch'),
        actions: [
          IconButton(icon: const Icon(Icons.save), tooltip: 'Lưu mẫu', onPressed: _saveAsTemplate),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _typeToggleButton('Chi tiêu', 'expense', AppColors.expense)),
                const SizedBox(width: 12),
                Expanded(child: _typeToggleButton('Thu nhập', 'income', AppColors.income)),
              ],
            ),
            const SizedBox(height: 20),
            StreamBuilder<List<QuickTemplate>>(
              stream: _templateService.streamUserTemplates(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return StreamErrorWidget(error: snapshot.error.toString());
                final templates = snapshot.data ?? [];
                if (templates.isEmpty) return const SizedBox.shrink();
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: templates
                        .map((t) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: QuickTemplateChip(
                                template: t,
                                onSelect: (tmpl) async {
                                  setState(() {
                                    _type = tmpl.type;
                                    _amountController.text = AppFormatters.number(tmpl.amount);
                                    _selectedWalletId = tmpl.walletId.isNotEmpty ? tmpl.walletId : null;
                                    _selectedCategoryId = tmpl.categoryId.isNotEmpty ? tmpl.categoryId : null;
                                    _noteController.text = tmpl.note;
                                    _locationController.text = tmpl.location;
                                  });
                                  await _runValidation();
                                },
                              ),
                            ))
                        .toList(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              readOnly: true,
              onTap: _showNumpad,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: accentColor),
              decoration: const InputDecoration(
                labelText: 'Số tiền',
                suffixText: 'đ',
                border: OutlineInputBorder(),
              ),
            ),
            if (_walletBalanceExceeded)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Số tiền vượt quá số dư ví', style: TextStyle(color: Colors.redAccent)),
              ),
            const SizedBox(height: 20),
            StreamBuilder<List<Wallet>>(
              stream: _firestoreService.streamWallets(uid),
              builder: (context, snap) {
                if (snap.hasError) return StreamErrorWidget(error: snap.error.toString());
                final wallets = snap.data ?? [];
                
                // Tránh lỗi DropdownButton nếu id không tồn tại trong danh sách mới
                if (_selectedWalletId != null && !wallets.any((w) => w.walletId == _selectedWalletId)) {
                  _selectedWalletId = null;
                }

                return DropdownButtonFormField<String>(
                  value: _selectedWalletId,
                  decoration: const InputDecoration(labelText: 'Ví', prefixIcon: Icon(Icons.account_balance_wallet_outlined)),
                  items: wallets.map((w) => DropdownMenuItem(value: w.walletId, child: Text(w.walletName))).toList(),
                  onChanged: (v) async {
                    setState(() => _selectedWalletId = v);
                    await _runValidation();
                  },
                );
              },
            ),
            const SizedBox(height: 16),
            StreamBuilder<List<Category>>(
              stream: _firestoreService.streamCategories(uid),
              builder: (context, snap) {
                if (snap.hasError) return StreamErrorWidget(error: snap.error.toString());
                final allCategories = snap.data ?? [];
                final categories = allCategories.where((c) => c.type == _type).toList();
                
                // Kiểm tra tồn tại dựa trên TOÀN BỘ danh mục (không phụ thuộc _type),
                // để đổi _type không làm mất lựa chọn hợp lệ đang có
                if (_selectedCategoryId != null &&
                    !allCategories.any((c) => c.categoryId == _selectedCategoryId)) {
                  _selectedCategoryId = null;
                }

                return DropdownButtonFormField<String>(
                  value: categories.any((c) => c.categoryId == _selectedCategoryId) ? _selectedCategoryId : null,
                  decoration: const InputDecoration(labelText: 'Danh mục', prefixIcon: Icon(Icons.category_outlined)),
                  items: categories.map((c) => DropdownMenuItem(value: c.categoryId, child: Text(c.name))).toList(),
                  onChanged: (v) async {
                    setState(() => _selectedCategoryId = v);
                    await _runValidation();
                  },
                );
              },
            ),
            if (_budgetExceeded)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Giao dịch sẽ vượt quá ngân sách', style: TextStyle(color: Colors.redAccent)),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              maxLines: null,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: 'Ghi chú',
                prefixIcon: Icon(Icons.notes_outlined),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(labelText: 'Địa điểm (tùy chọn)', prefixIcon: Icon(Icons.location_on_outlined)),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(AppFormatters.date(_selectedDate)),
              trailing: TextButton(onPressed: _pickDate, child: const Text('Đổi ngày')),
            ),
            const Divider(),
            ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.camera_alt_outlined),
                title: Text(
                  _receiptImageBytes == null
                      ? 'Chụp ảnh hóa đơn'
                      : _isParsing
                          ? 'Đang trích xuất hoá đơn...'
                          : 'Đã chọn ảnh hoá đơn',
                ),
                trailing: _isParsing
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
                    : _receiptImageBytes != null
                        ? Image.memory(_receiptImageBytes!, width: 40, height: 40, fit: BoxFit.cover)
                        : null,
                onTap: _pickImage,
                ),
                // Add option to pick from gallery
                IconButton(
                  icon: const Icon(Icons.photo_library_outlined),
                  tooltip: 'Chọn ảnh từ thư viện',
                  onPressed: () async {
                    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
                    if (picked != null) {
                      final bytes = await picked.readAsBytes();
                      setState(() => _receiptImageBytes = bytes);
                      await _parseReceipt();
                    }
                  },
                ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: accentColor, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: (_isSaving || _isParsing || _isValidating) ? null : _handleSave,
                child: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Lưu giao dịch', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeToggleButton(String label, String type, Color color) {
    final selected = _type == type;
    return OutlinedButton(
      onPressed: () => setState(() {
        _type = type;
        _selectedCategoryId = null;
        _selectedWalletId = null;
        // Reset form fields when switching between expense/income
        _amountController.clear();
        _noteController.clear();
        _locationController.clear();
        _receiptImageBytes = null;
        // Do NOT reset selected date; keep user's chosen date
        _walletBalanceExceeded = false;
        _budgetExceeded = false;
        _isSaving = false;
        _isParsing = false;
        _isValidating = false;
      }),
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? color.withOpacity(0.12) : null,
        side: BorderSide(color: selected ? color : Colors.grey.shade300),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(label, style: TextStyle(color: selected ? color : AppColors.textSecondary)),
    );
  }
}
