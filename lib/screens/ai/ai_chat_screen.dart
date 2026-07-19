import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/transaction_model.dart';
import '../../models/wallet_model.dart';
import '../../models/budget_model.dart';
import '../../services/firestore_service.dart';
import '../../services/ai_service.dart';
import '../../utils/constants.dart';
import '../../utils/formatters.dart';

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

  Future<void> _handleSend() async {
    final text = _inputController.text.trim();
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
    } catch (e) {
      if (mounted) {
        setState(() => _messages.add(
              _ChatMessage('Xin lỗi, đã có lỗi xảy ra. Vui lòng thử lại sau.', false),
            ));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.aiAccent.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, color: AppColors.aiAccent, size: 18),
            ),
            const SizedBox(width: 8),
            const Text('AI Financial Assistant'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Phiên mới',
            onPressed: _resetChat,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              itemCount: _messages.length + (_isSending ? 1 : 0),
              itemBuilder: (context, i) {
                // Typing indicator
                if (_isSending && i == _messages.length) {
                  return _TypingIndicator();
                }
                final msg = _messages[i];
                return _ChatBubble(message: msg);
              },
            ),
          ),
          // Suggested questions
          if (_messages.length == 1)
            _buildSuggestions(),
          _buildInputBar(),
        ],
      ),
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
      padding: const EdgeInsets.only(left: 12),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => ActionChip(
          label: Text(suggestions[i], style: const TextStyle(fontSize: 12)),
          backgroundColor: AppColors.aiAccent.withOpacity(0.08),
          side: BorderSide(color: AppColors.aiAccent.withOpacity(0.3)),
          onPressed: () {
            _inputController.text = suggestions[i];
            _handleSend();
          },
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, -2),
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
                  hintText: 'Hỏi AI về tài chính của bạn...',
                  hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                  filled: true,
                  fillColor: AppColors.background,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: _isSending
                    ? AppColors.textSecondary
                    : AppColors.aiAccent,
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.only(right: 6, bottom: 2),
              decoration: BoxDecoration(
                color: AppColors.aiAccent.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, size: 16, color: AppColors.aiAccent),
            ),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  color: isUser ? Colors.white : AppColors.textPrimary,
                  height: 1.45,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 4),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: AppColors.aiAccent.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome, size: 16, color: AppColors.aiAccent),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 2))
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
