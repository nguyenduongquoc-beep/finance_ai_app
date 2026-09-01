import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/firestore_service.dart';
import '../../services/ai_service.dart';
import '../../services/theme_controller.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';
import '../../widgets/app_snackbar.dart';

/// 17. AI Financial Assistant - Chatbot tài chính (giống ChatGPT)
/// AI đọc dữ liệu Firestore của người dùng -> phân tích -> trả lời
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  _ChatMessage(this.text, this.isUser) : timestamp = DateTime.now();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _aiService = AiService();
  final _firestoreService = FirestoreService();
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _inputFocusNode = FocusNode();

  final List<_ChatMessage> _messages = [
    _ChatMessage(
        'Xin chào! Mình là trợ lý tài chính AI. Hãy hỏi mình về thu chi, ngân sách hoặc '
        'kế hoạch tiết kiệm của bạn nhé. 💡',
        false),
  ];
  bool _isSending = false;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (animated) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      }
    });
  }

  Future<String> _buildFinancialContext(String uid) async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);

    final transactions =
        await _firestoreService.streamTransactions(uid, from: monthStart).first;
    final wallets = await _firestoreService.streamWallets(uid).first;
    final budgets =
        await _firestoreService.streamBudgets(uid, month: AppFormatters.month(now)).first;

    final income = transactions.where((t) => t.type == 'income').fold<double>(0, (a, t) => a + t.amount);
    final expense = transactions.where((t) => t.type == 'expense').fold<double>(0, (a, t) => a + t.amount);
    final totalBalance = wallets.fold<double>(0, (a, w) => a + w.balance);

    final buffer = StringBuffer();
    buffer.writeln('Tổng số dư các ví: ${AppFormatters.number(totalBalance)} đồng');
    buffer.writeln('Thu nhập tháng này: ${AppFormatters.number(income)} đồng');
    buffer.writeln('Chi tiêu tháng này: ${AppFormatters.number(expense)} đồng');
    buffer.writeln('Tiết kiệm ròng tháng này: ${AppFormatters.number(income - expense)} đồng');
    if (budgets.isNotEmpty) {
      buffer.writeln('\nTình trạng ngân sách:');
      for (final b in budgets) {
        final percent = b.limit > 0 ? (b.spent / b.limit * 100).round() : 0;
        buffer.writeln('- Danh mục ${b.categoryId}: đã chi ${AppFormatters.number(b.spent)}/${AppFormatters.number(b.limit)} đ ($percent%)');
      }
    }
    return buffer.toString();
  }

  Future<void> _sendMessage(String text) async {
    if (text.isEmpty || _isSending) return;

    setState(() {
      _messages.add(_ChatMessage(text, true));
      _isSending = true;
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final context = await _buildFinancialContext(uid);
      final reply = await _aiService.chatWithFinancialData(
        userQuestion: text,
        contextData: context,
      );
      if (mounted) {
        setState(() => _messages.add(_ChatMessage(reply, false)));
        _scrollToBottom();
      }
    } catch (e, stackTrace) {
      debugPrint('AI Chat error: $e');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _messages.add(
              _ChatMessage('Xin lỗi, đã có lỗi xảy ra. Vui lòng thử lại sau.', false),
            ));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _handleSend() async {
    final text = _inputController.text.trim();
    await _sendMessage(text);
  }

  void _resetChat() {
    _aiService.resetChatSession();
    setState(() {
      _messages.clear();
      _messages.add(_ChatMessage(
        'Phiên trò chuyện mới bắt đầu. Hỏi mình bất cứ điều gì về tài chính của bạn nhé! 💡',
        false,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, _, __) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary,
                  radius: 18,
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Trợ lý AI',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Color(0xFF4CAF50), // active green dot
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Đang hoạt động',
                          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Phiên mới',
                onPressed: _resetChat,
              ),
              IconButton(
                icon: const Icon(Icons.info_outline),
                tooltip: 'Thông tin',
                onPressed: () {
                  AppSnackbar.show(context, 'Trợ lý AI hỗ trợ quản lý chi tiêu cá nhân');
                },
              ),
            ],
            elevation: 0,
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: _messages.length + (_isSending ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (_isSending && i == _messages.length) {
                      return _TypingIndicator();
                    }
                    final msg = _messages[i];
                    return _ChatBubble(message: msg);
                  },
                ),
              ),
              if (_messages.length == 1)
                _buildSuggestions(),
              _buildInputBar(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSuggestions() {
    final suggestions = [
      'Tháng này tôi chi tiêu bao nhiêu?',
      'Gợi ý tiết kiệm cho tôi',
      'Ngân sách nào sắp vượt hạn mức?',
    ];
    return Container(
      height: 44,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(left: 16),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => ActionChip(
          label: Text(
            suggestions[i],
            style: TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
          ),
          backgroundColor: AppColors.card,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppColors.aiAccent.withOpacity(0.3)),
          ),
          onPressed: _isSending ? null : () {
            _sendMessage(suggestions[i]);
          },
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        decoration: BoxDecoration(
          color: AppColors.card,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, -3),
            )
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                focusNode: _inputFocusNode,
                decoration: InputDecoration(
                  hintText: 'Hỏi Trợ lý AI về chi tiêu của bạn...',
                  hintStyle: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  filled: true,
                  fillColor: AppColors.background,
                  suffixIcon: Icon(Icons.mic_none_outlined, color: AppColors.textSecondary),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _handleSend(),
              ),
            ),
            const SizedBox(width: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _isSending
                    ? AppColors.textSecondary
                    : AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                onPressed: _isSending ? null : _handleSend,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final _ChatMessage message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? AppColors.primary : AppColors.card,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ],
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  color: isUser ? Colors.white : AppColors.textPrimary,
                  height: 1.4,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
              ),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 3))
              ],
            ),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, __) {
                return Row(
                  children: List.generate(3, (i) {
                    final delay = i / 3;
                    final offset = ((_controller.value + delay) % 1.0);
                    final dy = offset < 0.5
                        ? -4.0 * (offset / 0.5)
                        : -4.0 * (1 - (offset - 0.5) / 0.5);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Transform.translate(
                        offset: Offset(0, dy),
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: AppColors.aiAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
