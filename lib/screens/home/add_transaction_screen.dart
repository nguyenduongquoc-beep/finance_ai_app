import 'dart:typed_data';
import 'dart:io';
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
import '../../services/theme_controller.dart';
import '../../utils/constants.dart';
import '../../utils/validation_utils.dart';
import '../../utils/formatters.dart';
import '../../models/quick_template.dart';
import '../../widgets/stream_error_widget.dart';
import '../../widgets/custom_numpad.dart';
import '../../widgets/quick_template_chip.dart';
import '../../widgets/app_snackbar.dart';

class AddTransactionScreen extends StatefulWidget {
  final AppTransaction? transactionToEdit;
  const AddTransactionScreen({super.key, this.transactionToEdit});

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
  String? _existingImagePath;
  bool _isSaving = false;
  bool _walletBalanceExceeded = false;
  bool _budgetExceeded = false;
  bool _isParsing = false;
  bool _isValidating = false;

  @override
  void initState() {
    super.initState();
    if (widget.transactionToEdit != null) {
      final tx = widget.transactionToEdit!;
      _type = tx.type;
      _amountController.text = AppFormatters.number(tx.amount);
      _selectedWalletId = tx.walletId.isNotEmpty ? tx.walletId : null;
      _selectedCategoryId = tx.categoryId.isNotEmpty ? tx.categoryId : null;
      _selectedDate = tx.date;
      _noteController.text = tx.note ?? '';
      _locationController.text = tx.location ?? '';
      _existingImagePath = tx.image;

      WidgetsBinding.instance.addPostFrameCallback((_) => _runValidation());
    }
  }

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
    AppSnackbar.show(context, 'Quyền truy cập camera bị từ chối', isError: true);
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
        AppSnackbar.show(context, 'Đã trích xuất thông tin hoá đơn');
      } else {
        AppSnackbar.show(context, 'Không thể trích xuất thông tin hoá đơn', isError: true);
      }
    } catch (e) {
      AppSnackbar.show(context, 'Lỗi khi trích xuất hoá đơn: $e', isError: true);
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
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      
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
          userId: uid,
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
      AppSnackbar.show(context, 'Đã lưu mẫu');
    }
  }

  Future<void> _handleSave() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final amount = AppFormatters.parseCurrencyInput(_amountController.text);

    if (uid == null || amount <= 0 || _selectedWalletId == null || _selectedCategoryId == null) {
      AppSnackbar.show(context, 'Vui lòng nhập đầy đủ số tiền, ví và danh mục', isError: true);
      return;
    }
    if (_walletBalanceExceeded) {
      AppSnackbar.show(context, 'Số tiền vượt quá số dư ví', isError: true);
      return;
    }
    if (_budgetExceeded) {
      AppSnackbar.show(context, 'Giao dịch sẽ vượt quá ngân sách danh mục', isError: true);
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
            AppSnackbar.show(context, 'Không thể lưu ảnh hóa đơn (lỗi kết nối), đang tiếp tục lưu giao dịch...', isError: true);
          }
        }
      }

      if (widget.transactionToEdit != null) {
        final newTx = AppTransaction(
          transactionId: widget.transactionToEdit!.transactionId,
          userId: uid,
          walletId: _selectedWalletId!,
          categoryId: _selectedCategoryId!,
          amount: amount,
          type: _type,
          note: _noteController.text.trim(),
          image: imageUrl ?? _existingImagePath,
          location: _locationController.text.trim(),
          date: _selectedDate,
        );
        await _firestoreService.updateTransactionSafely(widget.transactionToEdit!, newTx);
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
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
      }
    } catch (e) {
      debugPrint('❌ Lỗi khi lưu giao dịch: $e');
      if (mounted) {
        AppSnackbar.show(context, 'Không thể lưu giao dịch. Vui lòng kiểm tra kết nối mạng và thử lại.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, _, __) {
        final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
        final accentColor = _type == 'income' ? AppColors.income : AppColors.expense;

        return Scaffold(
          backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.transactionToEdit != null ? 'Sửa giao dịch' : 'Thêm giao dịch'),
        actions: [
          if (widget.transactionToEdit == null)
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
            if (widget.transactionToEdit == null) ...[
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
            ],
            TextField(
              controller: _amountController,
              readOnly: true,
              onTap: _showNumpad,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: accentColor),
              decoration: InputDecoration(
                labelText: 'Số tiền',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                prefixText: _type == 'expense' ? '- ' : '+ ',
                prefixStyle: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: accentColor),
                suffixText: ' VNĐ',
                suffixStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.normal, color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.card,
                contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
            if (_walletBalanceExceeded)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.expense.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.expense.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppColors.expense, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Số tiền vượt quá số dư ví',
                        style: TextStyle(color: AppColors.expense, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            StreamBuilder<List<Wallet>>(
              stream: _firestoreService.streamWallets(uid),
              builder: (context, snap) {
                if (snap.hasError) return StreamErrorWidget(error: snap.error.toString());
                final wallets = snap.data ?? [];
                
                if (_selectedWalletId != null && !wallets.any((w) => w.walletId == _selectedWalletId)) {
                  _selectedWalletId = null;
                }

                return DropdownButtonFormField<String>(
                  value: _selectedWalletId,
                  decoration: InputDecoration(
                    labelText: 'Ví thanh toán',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                    prefixIcon: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.primary),
                    filled: true,
                    fillColor: AppColors.card,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
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
                
                if (_selectedCategoryId != null &&
                    !allCategories.any((c) => c.categoryId == _selectedCategoryId)) {
                  _selectedCategoryId = null;
                }

                return DropdownButtonFormField<String>(
                  value: categories.any((c) => c.categoryId == _selectedCategoryId) ? _selectedCategoryId : null,
                  decoration: InputDecoration(
                    labelText: 'Danh mục',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                    prefixIcon: const Icon(Icons.category_outlined, color: AppColors.primary),
                    filled: true,
                    fillColor: AppColors.card,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                    ),
                  ),
                  items: categories.map((c) => DropdownMenuItem(value: c.categoryId, child: Text(c.name))).toList(),
                  onChanged: (v) async {
                    setState(() => _selectedCategoryId = v);
                    await _runValidation();
                  },
                );
              },
            ),
            if (_budgetExceeded)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Giao dịch sẽ vượt quá ngân sách danh mục',
                        style: TextStyle(color: AppColors.warning, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              maxLines: null,
              minLines: 1,
              decoration: InputDecoration(
                labelText: 'Ghi chú',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                prefixIcon: const Icon(Icons.notes_outlined, color: AppColors.primary),
                filled: true,
                fillColor: AppColors.card,
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _locationController,
              decoration: InputDecoration(
                labelText: 'Địa điểm (tùy chọn)',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                prefixIcon: const Icon(Icons.location_on_outlined, color: AppColors.primary),
                filled: true,
                fillColor: AppColors.card,
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: ListTile(
                leading: const Icon(Icons.calendar_today_outlined, color: AppColors.primary),
                title: Text(AppFormatters.date(_selectedDate), style: const TextStyle(fontWeight: FontWeight.w500)),
                trailing: TextButton(
                  onPressed: _pickDate,
                  child: const Text('Đổi ngày', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const Divider(),
            const SizedBox(height: 16),
            Text('Ảnh hóa đơn', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: _receiptImageBytes != null
                  ? Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            _receiptImageBytes!,
                            width: double.infinity,
                            height: 120,
                            fit: BoxFit.cover,
                          ),
                        ),
                        if (_isParsing)
                          Container(
                            color: Colors.black54,
                            child: const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(color: Colors.white),
                                  SizedBox(height: 8),
                                  Text('Đang trích xuất hóa đơn...', style: TextStyle(color: Colors.white, fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        Positioned(
                          right: 8,
                          top: 8,
                          child: CircleAvatar(
                            backgroundColor: Colors.black54,
                            radius: 16,
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.close, color: Colors.white, size: 16),
                              onPressed: () => setState(() => _receiptImageBytes = null),
                            ),
                          ),
                        ),
                      ],
                    )
                  : _existingImagePath != null
                      ? Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                File(_existingImagePath!),
                                width: double.infinity,
                                height: 120,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  color: Colors.grey.shade100,
                                  child: const Center(
                                    child: Icon(Icons.broken_image_outlined, color: Colors.grey),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 8,
                              top: 8,
                              child: CircleAvatar(
                                backgroundColor: Colors.black54,
                                radius: 16,
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(Icons.close, color: Colors.white, size: 16),
                                  onPressed: () => setState(() => _existingImagePath = null),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            TextButton.icon(
                              onPressed: _pickImage,
                              icon: const Icon(Icons.camera_alt_outlined, color: AppColors.primary),
                              label: const Text('Chụp ảnh', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                            ),
                            const VerticalDivider(width: 1, indent: 30, endIndent: 30),
                            TextButton.icon(
                              onPressed: () async {
                                final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
                                if (picked != null) {
                                  final bytes = await picked.readAsBytes();
                                  setState(() => _receiptImageBytes = bytes);
                                  await _parseReceipt();
                                }
                              },
                              icon: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
                              label: const Text('Thư viện', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: (_isSaving || _isParsing || _isValidating) ? null : _handleSave,
                child: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        widget.transactionToEdit != null ? 'Cập nhật giao dịch' : 'Lưu giao dịch',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  },
);
  }

  Widget _typeToggleButton(String label, String type, Color color) {
    final selected = _type == type;
    return ElevatedButton(
      onPressed: () => setState(() {
        _type = type;
        _selectedCategoryId = null;
        _selectedWalletId = null;
        _amountController.clear();
        _noteController.clear();
        _locationController.clear();
        _receiptImageBytes = null;
        _existingImagePath = null;
        _walletBalanceExceeded = false;
        _budgetExceeded = false;
        _isSaving = false;
        _isParsing = false;
        _isValidating = false;
      }),
      style: ElevatedButton.styleFrom(
        backgroundColor: selected ? color : AppColors.card,
        foregroundColor: selected ? Colors.white : AppColors.textSecondary,
        elevation: 0,
        side: BorderSide(color: selected ? color : Colors.grey.shade300, width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}
