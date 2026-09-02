import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers/app_providers.dart';
import '../domain/chat_models.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _uuid = const Uuid();
  List<ChatMessage> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  String? _connectionNote;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHistory());
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(chatApiClientProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Trợ lý chi tiêu'),
            Text(
              'Hỏi về hóa đơn và ngân sách',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Xóa lịch sử trò chuyện',
            onPressed: _messages.isEmpty || _sending ? null : _clearHistory,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!api.isConfigured)
              const _InfoBanner(
                icon: Icons.offline_bolt_outlined,
                message:
                    'Chế độ local: câu hỏi về dữ liệu đã lưu vẫn hoạt động. '
                    'Đăng nhập Supabase để bật Gemini và dữ liệu bên ngoài.',
              ),
            if (_connectionNote != null)
              _InfoBanner(
                icon: Icons.cloud_off_outlined,
                message: _connectionNote!,
                color: Theme.of(context).colorScheme.errorContainer,
              ),
            Expanded(child: _buildMessages(context)),
            _buildSuggestions(context),
            _buildComposer(context),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages(BuildContext context) {
    if (_loading) {
      return Center(
        child: Semantics(
          label: 'Đang tải lịch sử trò chuyện',
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Bắt đầu bằng một câu hỏi về chi tiêu của bạn.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount: _messages.length + (_sending ? 1 : 0),
      itemBuilder: (context, index) {
        if (_sending && index == _messages.length) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Semantics(
                label: 'Trợ lý đang suy nghĩ',
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _MessageBubble(message: _messages[index]);
      },
    );
  }

  Widget _buildSuggestions(BuildContext context) {
    if (_messages.length > 1 || _sending) return const SizedBox.shrink();
    const suggestions = [
      'Tháng này tôi đã chi bao nhiêu?',
      'Danh mục nào chi nhiều nhất?',
      'Tôi có khoản chi định kỳ nào không?',
      'Có khoản chi nào bất thường không?',
    ];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        scrollDirection: Axis.horizontal,
        itemCount: suggestions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => ActionChip(
          label: Text(suggestions[index]),
          onPressed: () => _send(suggestions[index]),
        ),
      ),
    );
  }

  Widget _buildComposer(BuildContext context) {
    final canSend = !_sending && _inputController.text.trim().isNotEmpty;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                enabled: !_sending,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.newline,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Hỏi trợ lý',
                  hintText: 'Ví dụ: So sánh chi tiêu tháng này với tháng trước',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: 'Gửi câu hỏi',
              child: IconButton.filled(
                tooltip: 'Gửi câu hỏi',
                onPressed: canSend ? () => _send(_inputController.text) : null,
                icon: const Icon(Icons.send_outlined),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadHistory() async {
    final loaded = await ref.read(chatHistoryStoreProvider).load();
    if (!mounted) return;
    setState(() {
      _messages = loaded.isEmpty ? [_welcomeMessage()] : loaded;
      _loading = false;
    });
    _scrollToEnd();
  }

  Future<void> _send(String value) async {
    final question = value.trim();
    if (question.isEmpty || _sending) return;
    final userMessage = ChatMessage(
      id: _uuid.v4(),
      role: ChatMessageRole.user,
      text: question,
      createdAt: DateTime.now(),
    );
    setState(() {
      _inputController.clear();
      _messages = [..._messages, userMessage];
      _sending = true;
      _connectionNote = null;
    });
    _scrollToEnd();

    try {
      final local = await ref.read(localChatAssistantProvider).answer(question);
      var reply = local;
      final api = ref.read(chatApiClientProvider);
      if (api.isConfigured) {
        try {
          reply = await api.ask(
            question: question,
            history: _messages,
            facts: local.facts,
          );
        } on Object catch (_) {
          if (mounted) {
            setState(() {
              _connectionNote =
                  'Gemini tạm thời không kết nối được; đang hiển thị kết quả local.';
            });
          }
        }
      }
      final assistantMessage = ChatMessage(
        id: _uuid.v4(),
        role: ChatMessageRole.assistant,
        text: reply.text,
        createdAt: DateTime.now(),
        citations: reply.citations,
      );
      if (!mounted) return;
      final updated = [..._messages, assistantMessage];
      setState(() {
        _messages = updated;
        _sending = false;
      });
      await ref.read(chatHistoryStoreProvider).save(updated);
      _scrollToEnd();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _messages = [
          ..._messages,
          ChatMessage(
            id: _uuid.v4(),
            role: ChatMessageRole.assistant,
            text: 'Không thể đọc dữ liệu local lúc này: $error',
            createdAt: DateTime.now(),
          ),
        ];
        _sending = false;
      });
      _scrollToEnd();
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa lịch sử trò chuyện?'),
        content: const Text('Các tin nhắn đã lưu trên thiết bị sẽ bị xóa.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa lịch sử'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(chatHistoryStoreProvider).clear();
    if (!mounted) return;
    setState(() => _messages = [_welcomeMessage()]);
  }

  ChatMessage _welcomeMessage() => ChatMessage(
    id: 'welcome',
    role: ChatMessageRole.assistant,
    text:
        'Xin chào! Mình có thể giúp bạn xem tổng chi, ngân sách, danh mục, '
        'so sánh tháng và khoản chi định kỳ.',
    createdAt: DateTime.now(),
  );

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.message, this.color});

  final IconData icon;
  final String message;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color ?? Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatMessageRole.user;
    final scheme = Theme.of(context).colorScheme;
    final color = isUser
        ? scheme.primaryContainer
        : scheme.surfaceContainerHigh;
    return Semantics(
      label: '${isUser ? 'Bạn' : 'Trợ lý'}: ${message.text}',
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Card(
            color: color,
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message.text),
                  if (message.citations.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Divider(height: 1),
                    const SizedBox(height: 6),
                    for (final citation in message.citations)
                      if (citation.sourceType == 'invoice')
                        Semantics(
                          button: true,
                          label: '${citation.label}: ${citation.sourceId}',
                          child: TextButton.icon(
                            onPressed: () => context.push(
                              '/invoices/${Uri.encodeComponent(citation.sourceId)}',
                            ),
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: Text(citation.label),
                          ),
                        )
                      else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.source_outlined, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${citation.label} · ${citation.sourceId}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  if (citation.url case final url?)
                                    Text(
                                      url,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
