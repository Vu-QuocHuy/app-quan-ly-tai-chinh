import 'dart:async';
import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../income/data/income_repository.dart';
import '../../invoices/domain/invoice_models.dart';
import '../../ingestion/data/ai_extraction_client.dart';
import '../domain/chat_models.dart';
import '../domain/chat_privacy_policy.dart';
import '../data/voice_file_cleanup.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../../shared/widgets/app_callout.dart';

/// Câu hỏi nhanh hiển thị trên ô nhập, xếp theo mức độ hay dùng. Mỗi câu phải
/// khớp một ý định mà LocalChatAssistant hiểu được để vẫn trả lời khi offline.
const chatQuickPrompts = [
  'Tháng này tôi đã chi bao nhiêu?',
  'Tháng này tôi đã thu bao nhiêu?',
  'So sánh chi tiêu tháng này với tháng trước',
  'Danh mục nào chi nhiều nhất?',
  'Tôi còn bao nhiêu hạn mức ngân sách?',
  'Dự báo chi tiêu đến cuối tháng',
  'Hóa đơn gần đây của tôi',
  'Tôi có khoản chi định kỳ nào không?',
  'Có khoản chi nào bất thường không?',
  'Nếu tôi giảm chi 500.000đ mỗi tháng thì tiết kiệm được bao nhiêu?',
];

Future<void> showFinmiAssistant(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        final media = MediaQuery.of(context);
        return Padding(
          padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
          child: SizedBox(
            height:
                (media.size.height -
                    media.viewInsets.bottom -
                    media.padding.top) *
                (media.viewInsets.bottom > 0 ? .95 : .7),
            child: const ChatScreen(embedded: true),
          ),
        );
      },
    );

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({this.embedded = false, super.key});
  final bool embedded;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  static const _localAnswerTimeout = Duration(seconds: 2);
  static const _llmAnswerTimeout = Duration(seconds: 30);

  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _uuid = const Uuid();
  final _audioRecorder = AudioRecorder();
  late List<ChatMessage> _messages;
  bool _sending = false;
  bool _recording = false;
  bool _startingRecording = false;
  bool _transcribing = false;
  ChatMessage? _pendingVoiceMessage;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  List<double> _voiceLevels = List.filled(40, .06);
  String? _connectionNote;
  TransactionDraftResult? _draftConversation;
  final Map<String, _TransactionDraft> _draftCards = {};
  String? _savingDraftMessageId;

  @override
  void initState() {
    super.initState();
    _messages = [_welcomeMessage()];
    unawaited(
      ref
          .read(chatHistoryStoreProvider)
          .clearAll(includeLegacy: true)
          .catchError((Object _) {}),
    );
  }

  @override
  void dispose() {
    unawaited(_amplitudeSubscription?.cancel());
    _inputController.dispose();
    _scrollController.dispose();
    unawaited(
      (_recording || _transcribing
              ? _audioRecorder.cancel()
              : Future<void>.value())
          .then((_) => _audioRecorder.dispose()),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Trợ lý tài chính',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Đóng trợ lý',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                children: [
                  if (_connectionNote != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: AppCallout(
                        icon: Icons.cloud_off_outlined,
                        tone: CalloutTone.warning,
                        message: _connectionNote!,
                        liveRegion: true,
                      ),
                    ),
                  Expanded(child: _buildMessages(context)),
                  if (constraints.maxHeight >= 350) _buildSuggestions(context),
                  _buildComposer(context),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    return widget.embedded ? content : Scaffold(body: SafeArea(child: content));
  }

  Widget _buildMessages(BuildContext context) {
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Bắt đầu bằng một câu hỏi về thu chi của bạn.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      itemCount:
          _messages.length +
          (_pendingVoiceMessage != null ? 1 : 0) +
          (_sending ? 1 : 0),
      itemBuilder: (context, index) {
        if (_pendingVoiceMessage != null && index == _messages.length) {
          return Semantics(
            liveRegion: true,
            child: _MessageBubble(
              message: _pendingVoiceMessage!,
              accessory: const SizedBox(
                width: 200,
                child: LinearProgressIndicator(),
              ),
            ),
          );
        }
        if (_sending && index == _messages.length) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Semantics(liveRegion: true, child: Text('Đang suy nghĩ…')),
            ),
          );
        }
        final message = _messages[index];
        final draft = _draftCards[message.id];
        return _MessageBubble(
          message: message,
          accessory: draft == null ? null : _buildDraftCard(message.id, draft),
        );
      },
    );
  }

  Widget _buildSuggestions(BuildContext context) {
    if (_sending || _recording || _transcribing) {
      return const SizedBox.shrink();
    }
    const suggestions = chatQuickPrompts;
    return SizedBox(
      height: 48 * (MediaQuery.textScalerOf(context).scale(14) / 14),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
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
    if (_recording) return _buildRecordingComposer(context);
    final busy = _sending || _transcribing || _startingRecording;
    final canSend = !busy && _inputController.text.trim().isNotEmpty;
    final canRecord = !busy;
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
                enabled: !busy,
                minLines: 1,
                maxLines: 3,
                textInputAction: TextInputAction.newline,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Nhắn trợ lý',
                  hintText: 'Ví dụ: Vừa ăn trưa hết 45 nghìn',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Semantics(
              button: true,
              label: 'Nói câu hỏi hoặc mô tả giao dịch',
              child: IconButton.filledTonal(
                tooltip: 'Nói câu hỏi hoặc giao dịch',
                onPressed: canRecord ? _startVoiceInput : null,
                icon: const Icon(Icons.mic_none),
              ),
            ),
            const SizedBox(width: 4),
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

  Widget _buildRecordingComposer(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            IconButton.filledTonal(
              tooltip: 'Xóa bản ghi âm',
              onPressed: _cancelVoiceInput,
              icon: const Icon(Icons.delete_outline),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                label: 'Sóng âm ghi âm',
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: CustomPaint(
                    painter: _VoiceWaveformPainter(
                      _voiceLevels,
                      colors.primary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filled(
              tooltip: 'Gửi bản ghi âm',
              onPressed: _finishVoiceInput,
              icon: const Icon(Icons.send_outlined),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancelVoiceInput() async {
    if (!_recording) return;
    setState(() {
      _recording = false;
      _transcribing = true;
    });
    try {
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;
      await _audioRecorder.cancel();
    } on Object catch (error) {
      if (mounted) setState(() => _connectionNote = friendlyMessage(error));
    } finally {
      if (mounted) setState(() => _transcribing = false);
    }
  }

  Future<void> _startVoiceInput() async {
    if (_sending || _transcribing || _startingRecording || _recording) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _startingRecording = true);
    try {
      if (!await _audioRecorder.hasPermission()) {
        throw StateError('Bạn cần cấp quyền micro để nhập bằng giọng nói.');
      }
      final path = kIsWeb
          ? 'voice-${_uuid.v4()}.wav'
          : '${(await getTemporaryDirectory()).path}/voice-${_uuid.v4()}.wav';
      if (!mounted) return;
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      if (!mounted) {
        await _audioRecorder.cancel();
        return;
      }
      setState(() {
        _recording = true;
        _voiceLevels = List.filled(40, .06);
        _connectionNote = null;
      });
      _amplitudeSubscription = _audioRecorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .listen((amplitude) {
            if (!mounted || !_recording) return;
            final level = ((amplitude.current + 60) / 60).clamp(.06, 1.0);
            setState(() {
              _voiceLevels = [..._voiceLevels.skip(1), level];
            });
          });
    } on Object catch (error) {
      if (mounted) setState(() => _connectionNote = friendlyMessage(error));
    } finally {
      if (mounted) setState(() => _startingRecording = false);
    }
  }

  Future<void> _finishVoiceInput() async {
    if (!_recording) return;
    String? recordingPath;
    setState(() {
      _recording = false;
      _transcribing = true;
      _pendingVoiceMessage = ChatMessage(
        id: _uuid.v4(),
        role: ChatMessageRole.user,
        text: 'Đang chuyển giọng nói thành văn bản…',
        createdAt: DateTime.now(),
      );
    });
    _scrollToEnd();
    try {
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;
      recordingPath = await _audioRecorder.stop();
      if (recordingPath == null) {
        throw StateError('Không có bản ghi âm để gửi.');
      }
      final audio = XFile(recordingPath);
      if (await audio.length() > 15 * 1024 * 1024) {
        throw StateError('Bản ghi vượt quá giới hạn 15 MB.');
      }
      final bytes = await audio.readAsBytes();
      await _audioRecorder.cancel();
      await deleteVoiceFile(recordingPath);
      recordingPath = null;
      final client = ref.read(supabaseClientProvider);
      if (client == null) throw StateError('Chưa kết nối được dịch vụ AI.');
      final response = await client.functions.invoke(
        'ai-api',
        body: {
          'action': 'transcribe',
          'requestId': _uuid.v4(),
          'audioBase64': base64Encode(bytes),
        },
      );
      final data = response.data;
      if (data is! Map || data['text'] is! String) {
        throw const FormatException(
          'Dịch vụ phiên âm trả dữ liệu không hợp lệ.',
        );
      }
      final transcript = (data['text'] as String).trim();
      if (transcript.isEmpty) {
        throw StateError('Không nhận diện được lời nói. Hãy thử lại.');
      }
      if (!mounted) return;
      final current = _inputController.text.trim();
      _inputController.text = current.isEmpty
          ? transcript
          : '$current $transcript';
      _inputController.selection = TextSelection.collapsed(
        offset: _inputController.text.length,
      );
      setState(() {
        _connectionNote = null;
        _pendingVoiceMessage = null;
        _transcribing = false;
      });
      await _send(_inputController.text);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _pendingVoiceMessage = null;
          _messages = [
            ..._messages,
            ChatMessage(
              id: _uuid.v4(),
              role: ChatMessageRole.user,
              text: friendlyMessage(error),
              createdAt: DateTime.now(),
            ),
          ];
        });
        _scrollToEnd();
      }
    } finally {
      if (recordingPath != null) {
        try {
          await _audioRecorder.cancel();
        } on Object {
          // The recorder may already have been disposed when this screen closed.
        }
        await deleteVoiceFile(recordingPath);
      }
      if (mounted) setState(() => _transcribing = false);
    }
  }

  Future<void> _send(String value) async {
    final question = value.trim();
    if (question.isEmpty || _sending) return;
    final isBlockedQuestion = ChatPrivacyPolicy.isBlockedQuestion(question);
    final isDraftFollowUp =
        !isBlockedQuestion &&
        _draftConversation != null &&
        (_isDraftCancellation(question) ||
            _looksLikeDraftAnswer(question) ||
            _looksLikeTransactionEntry(question));
    final draftRequest =
        (!isBlockedQuestion && _looksLikeTransactionEntry(question)) ||
        isDraftFollowUp;
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

    if (isBlockedQuestion) {
      setState(() {
        _messages = [
          ..._messages,
          ChatMessage(
            id: _uuid.v4(),
            role: ChatMessageRole.assistant,
            text: ChatPrivacyPolicy.outOfScopeMessage,
            createdAt: DateTime.now(),
          ),
        ];
        _sending = false;
      });
      _scrollToEnd();
      return;
    }

    try {
      if (draftRequest) {
        await _handleTransactionMessage(question);
        return;
      }
      final reply = await _answerWithLlm(question);
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
      _scrollToEnd();
    } on Object {
      if (!mounted) return;
      final reply = await _answerFallback(question, draftRequest: draftRequest);
      if (!mounted) return;
      setState(() {
        _messages = [
          ..._messages,
          ChatMessage(
            id: _uuid.v4(),
            role: ChatMessageRole.assistant,
            text: reply.text,
            createdAt: DateTime.now(),
            citations: reply.citations,
          ),
        ];
        _sending = false;
      });
      _scrollToEnd();
    }
  }

  Future<ChatReply> _answerFallback(
    String question, {
    required bool draftRequest,
  }) async {
    try {
      if (ChatPrivacyPolicy.isBlockedQuestion(question)) {
        return const ChatReply(text: ChatPrivacyPolicy.outOfScopeMessage);
      }
      if (!ChatPrivacyPolicy.isPersonalFinanceQuestion(question)) {
        return const ChatReply(
          text:
              'Mình chưa kết nối được AI để xác định đúng phạm vi câu hỏi. '
              'Bạn có thể hỏi về thu chi, hóa đơn hoặc ngân sách trong ứng dụng nhé.',
        );
      }
      return await ref
          .read(localChatAssistantProvider)
          .answer(question)
          .timeout(_localAnswerTimeout);
    } on Object {
      // Use a short offline response if local finance data is unavailable too.
    }
    return ChatReply(
      text: draftRequest
          ? 'Mình chưa tạo được bản nháp lúc này, nên chưa có khoản thu/chi nào được lưu. Bạn thử lại sau nhé.'
          : 'Mình đang mất kết nối với trợ lý AI nên chưa trả lời được câu này. Bạn thử lại sau nhé.',
    );
  }

  Future<ChatReply> _answerWithLlm(String question) async {
    final client = ref.read(aiChatClientProvider);
    final plan = await client
        .answer(question, facts: const [], allowToolCalls: true)
        .timeout(_llmAnswerTimeout);
    if (plan.toolCall == null) return plan;

    final facts =
        (await ref
                .read(localChatAssistantProvider)
                .executeTool(plan.toolCall!)
                .timeout(_localAnswerTimeout))
            .facts;
    final answer = await client
        .answer(question, facts: facts)
        .timeout(_llmAnswerTimeout);
    if (answer.toolCall != null) {
      throw const FormatException('Chatbot vượt quá số lượt gọi công cụ.');
    }
    return answer;
  }

  Future<void> _handleTransactionMessage(String question) async {
    if (_draftConversation != null && _isDraftCancellation(question)) {
      final pendingCardIds = _draftCards.keys.toSet();
      setState(() {
        _draftConversation = null;
        _draftCards.clear();
        _messages = [
          for (final message in _messages)
            if (pendingCardIds.contains(message.id))
              ChatMessage(
                id: message.id,
                role: message.role,
                text: 'Bản nháp đã bị hủy.',
                createdAt: message.createdAt,
              )
            else
              message,
          ChatMessage(
            id: _uuid.v4(),
            role: ChatMessageRole.assistant,
            text:
                'Đã hủy bản nháp rồi nhé, chưa có khoản thu/chi nào được lưu đâu bạn yên tâm.',
            createdAt: DateTime.now(),
          ),
        ];
        _sending = false;
      });
      _scrollToEnd();
      return;
    }

    final categories = [
      ...await ref.read(incomeCategoriesProvider.future),
      ...await ref.read(categoriesProvider.future),
    ];
    final now = DateTime.now();
    final previous = _draftConversation;
    final result = await ref
        .read(aiExtractionClientProvider)
        .draftTransaction(
          question,
          today: now,
          categories: categories,
          previous: previous,
        );
    if (!mounted) return;

    if (!result.isTransaction) {
      final reply = await _answerWithLlm(question);
      if (!mounted) return;
      setState(() {
        _messages = [
          ..._messages,
          ChatMessage(
            id: _uuid.v4(),
            role: ChatMessageRole.assistant,
            text: reply.text,
            createdAt: DateTime.now(),
            citations: reply.citations,
          ),
        ];
        _sending = false;
      });
      _scrollToEnd();
      return;
    }

    final previousCardIds = _draftCards.keys.toSet();
    _draftConversation = result;
    if (!result.isReady) {
      setState(() {
        _draftCards.clear();
        _messages = [
          for (final message in _messages)
            if (previousCardIds.contains(message.id))
              ChatMessage(
                id: message.id,
                role: message.role,
                text: 'Bản nháp này đã được cập nhật trong tin nhắn mới hơn.',
                createdAt: message.createdAt,
              )
            else
              message,
          ChatMessage(
            id: _uuid.v4(),
            role: ChatMessageRole.assistant,
            text: result.clarification.isEmpty
                ? 'Bạn cho mình biết số tiền và đây là khoản thu hay khoản chi nhé.'
                : result.clarification,
            createdAt: DateTime.now(),
          ),
        ];
        _sending = false;
      });
      _scrollToEnd();
      return;
    }

    final date = result.date ?? DateTime(now.year, now.month, now.day);
    final isIncome = result.type == 'income';
    final categoryKind = isIncome ? CategoryKind.income : CategoryKind.expense;
    final category =
        categories
            .where(
              (item) =>
                  item.id == result.categoryId && item.kind == categoryKind,
            )
            .firstOrNull ??
        categories
            .where(
              (item) =>
                  item.kind == categoryKind &&
                  item.name.trim().toLowerCase() == 'khác',
            )
            .firstOrNull;
    final draft = _TransactionDraft(
      isIncome: isIncome,
      amountMinor: result.amountMinor!,
      date: date,
      description: result.description,
      categoryId: category?.id,
      categoryName: category?.name,
      possibleDuplicate: await _hasPotentialDuplicate(
        isIncome: isIncome,
        amountMinor: result.amountMinor!,
        date: date,
        description: result.description,
        categoryId: category?.id,
      ),
    );
    if (!mounted) return;
    final messageId = _uuid.v4();
    setState(() {
      _draftCards.clear();
      _draftCards[messageId] = draft;
      _messages = [
        for (final message in _messages)
          if (previousCardIds.contains(message.id))
            ChatMessage(
              id: message.id,
              role: message.role,
              text: 'Bản nháp này đã được cập nhật trong tin nhắn mới hơn.',
              createdAt: message.createdAt,
            )
          else
            message,
        ChatMessage(
          id: messageId,
          role: ChatMessageRole.assistant,
          text: '',
          createdAt: DateTime.now(),
        ),
      ];
      _sending = false;
    });
    _scrollToEnd();
  }

  Future<bool> _hasPotentialDuplicate({
    required bool isIncome,
    required int amountMinor,
    required DateTime date,
    required String description,
    required String? categoryId,
  }) async {
    try {
      if (isIncome) {
        return await ref
            .read(incomeRepositoryProvider)
            .hasPotentialDuplicate(amountMinor, date);
      }
      final candidate = InvoiceEntity(
        id: _uuid.v4(),
        sellerName: description.isEmpty ? 'Khoản chi' : description,
        notes: description,
        currencyCode: 'VND',
        subtotalMinor: amountMinor,
        taxMinor: 0,
        totalMinor: amountMinor,
        sourceType: InvoiceSourceType.manual,
        status: InvoiceStatus.confirmed,
        categoryId: categoryId,
        issuedAt: date,
        createdAt: date,
        updatedAt: date,
      );
      final matches = await ref
          .read(invoiceRepositoryProvider)
          .findDuplicateCandidates(candidate);
      return matches.any(
        (item) =>
            item.status == InvoiceStatus.confirmed &&
            item.totalMinor == amountMinor &&
            _sameDay(item.issuedAt ?? item.createdAt, date),
      );
    } on Object {
      return false;
    }
  }

  Widget _buildDraftCard(String messageId, _TransactionDraft draft) {
    final busy = _savingDraftMessageId == messageId;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${draft.isIncome ? 'Khoản thu' : 'Khoản chi'} · ${MoneyFormatter.format(draft.amountMinor)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (draft.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(draft.description),
          ],
          const SizedBox(height: 4),
          Text(
            '${MaterialLocalizations.of(context).formatMediumDate(draft.date)} · ${draft.categoryName ?? 'Chưa phân loại'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (draft.possibleDuplicate) ...[
            const SizedBox(height: 10),
            const AppCallout(
              tone: CalloutTone.warning,
              title: 'Có thể trùng giao dịch',
              message:
                  'Đã có khoản cùng số tiền trong ngày này. Hãy kiểm tra trước khi lưu.',
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: busy ? null : () => _discardDraft(messageId),
                child: const Text('Bỏ qua'),
              ),
              FilledButton.icon(
                onPressed: busy ? null : () => _saveDraft(messageId, draft),
                icon: busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(
                  draft.possibleDuplicate ? 'Vẫn lưu' : 'Xác nhận lưu',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _saveDraft(String messageId, _TransactionDraft draft) async {
    if (_savingDraftMessageId != null) return;
    setState(() => _savingDraftMessageId = messageId);
    try {
      if (draft.isIncome) {
        await ref
            .read(incomeRepositoryProvider)
            .save(
              draft.amountMinor,
              source: IncomeSource.manual,
              categoryId: draft.categoryId,
              receivedAt: draft.date,
              note: draft.description,
            );
      } else {
        final now = DateTime.now();
        await ref
            .read(invoiceRepositoryProvider)
            .saveInvoice(
              InvoiceEntity(
                id: _uuid.v4(),
                sellerName: draft.description.isEmpty
                    ? draft.categoryName ?? 'Khoản chi'
                    : draft.description,
                notes: draft.description,
                currencyCode: 'VND',
                subtotalMinor: draft.amountMinor,
                taxMinor: 0,
                totalMinor: draft.amountMinor,
                sourceType: InvoiceSourceType.manual,
                status: InvoiceStatus.confirmed,
                categoryId: draft.categoryId,
                issuedAt: draft.date,
                createdAt: now,
                updatedAt: now,
                confirmedAt: now,
              ),
            );
      }
      if (!mounted) return;
      final label = draft.isIncome ? 'thu' : 'chi';
      setState(() {
        _draftCards.remove(messageId);
        _draftConversation = null;
        _messages = [
          for (final message in _messages)
            if (message.id == messageId)
              ChatMessage(
                id: message.id,
                role: message.role,
                text:
                    '✅ Đã lưu khoản $label ${MoneyFormatter.format(draft.amountMinor)} vào sổ chi tiêu cho bạn rồi nhé!',
                createdAt: message.createdAt,
              )
            else
              message,
        ];
      });
      _scrollToEnd();
    } on Object catch (error) {
      if (mounted) setState(() => _connectionNote = friendlyMessage(error));
    } finally {
      if (mounted) setState(() => _savingDraftMessageId = null);
    }
  }

  void _discardDraft(String messageId) {
    setState(() {
      _draftCards.remove(messageId);
      _draftConversation = null;
      _messages = [
        for (final message in _messages)
          if (message.id == messageId)
            ChatMessage(
              id: message.id,
              role: message.role,
              text: 'Đã bỏ bản nháp. Chưa có giao dịch nào được lưu.',
              createdAt: message.createdAt,
            )
          else
            message,
      ];
    });
  }

  bool _isDraftCancellation(String text) => RegExp(
    r'^(thôi|huỷ|hủy|bỏ qua|không lưu)( nhé| nha)?[.! ]*$',
    caseSensitive: false,
    unicode: true,
  ).hasMatch(text.trim());

  // shortcut: starts AI parsing only for transaction verbs or currency markers.
  bool _looksLikeTransactionEntry(String value) {
    final text = value.toLowerCase().trim();
    const questionMarkers = [
      '?',
      'bao nhiêu',
      'nhiều nhất',
      'tổng',
      'so sánh',
      'tháng này',
      'tháng trước',
      'có nên',
      'nên mua',
      'nào tốt',
      'nên chọn',
      'tư vấn',
      'đánh giá',
      'tại sao',
      'làm sao',
      'thế nào',
      'là gì',
      'danh mục',
      'gần đây',
      'mới nhất',
      'định kỳ',
      'dự báo',
      'bất thường',
      'gợi ý',
      'liệt kê',
    ];
    if (questionMarkers.any(text.contains)) return false;
    const actions = [
      'mua',
      'trả',
      'thanh toán',
      'chi',
      'tiêu',
      'ăn',
      'uống',
      'đổ xăng',
      'đi chợ',
      'đặt',
      'nhận',
      'thu',
      'lương',
      'thưởng',
      'bán',
      'chuyển',
      'ghi lại',
      'ghi nhận',
      'đóng tiền',
      'nộp tiền',
      'hoàn tiền',
    ];
    if (actions.any(
      (action) => RegExp(
        '(^|\\s)${RegExp.escape(action)}(?=\\s|\$)',
        unicode: true,
      ).hasMatch(text),
    )) {
      return true;
    }
    return RegExp(
      r'\d+(?:[.,]\d+)?\s*(k|nghìn|ngàn|triệu|tr|đồng|vnd|₫)\b',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(text);
  }

  bool _looksLikeDraftAnswer(String value) => RegExp(
    r'^\s*(?:\d+(?:[.,]\d+)?\s*(?:k|nghìn|ngàn|triệu|tr|đồng|vnd|₫)?|hôm nay|hôm qua|ngày\s+\d{1,2}(?:[/-]\d{1,2}(?:[/-]\d{2,4})?)?)\s*$',
    caseSensitive: false,
    unicode: true,
  ).hasMatch(value);

  bool _sameDay(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  ChatMessage _welcomeMessage() => ChatMessage(
    id: 'welcome',
    role: ChatMessageRole.assistant,
    text:
        'Chào bạn! Mình là Finmi. Bạn muốn xem thu chi, ngân sách hay ghi nhanh một giao dịch?',
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

class _VoiceWaveformPainter extends CustomPainter {
  const _VoiceWaveformPainter(this.levels, this.color);

  final List<double> levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final spacing = size.width / levels.length;
    final paint = Paint()
      ..color = color
      ..strokeWidth = (spacing * .5).clamp(1.0, 3.0)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < levels.length; i++) {
      final halfHeight = (size.height - 12) * levels[i] / 2;
      final x = spacing * (i + .5);
      canvas.drawLine(
        Offset(x, size.height / 2 - halfHeight),
        Offset(x, size.height / 2 + halfHeight),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_VoiceWaveformPainter oldDelegate) =>
      oldDelegate.levels != levels || oldDelegate.color != color;
}

class _TransactionDraft {
  const _TransactionDraft({
    required this.isIncome,
    required this.amountMinor,
    required this.date,
    required this.description,
    required this.categoryId,
    required this.categoryName,
    required this.possibleDuplicate,
  });

  final bool isIncome;
  final int amountMinor;
  final DateTime date;
  final String description;
  final String? categoryId;
  final String? categoryName;
  final bool possibleDuplicate;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, this.accessory});

  final ChatMessage message;
  final Widget? accessory;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatMessageRole.user;
    final scheme = Theme.of(context).colorScheme;
    final color = isUser
        ? scheme.primaryContainer
        : scheme.surfaceContainerHigh;
    return Semantics(
      label: message.text.isEmpty
          ? 'Bản nháp giao dịch'
          : '${isUser ? 'Bạn' : 'Trợ lý'}: ${message.text}',
      explicitChildNodes: true,
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Card(
            color: color,
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.text.isNotEmpty) Text(message.text),
                  if (accessory != null) ...[
                    const SizedBox(height: 10),
                    accessory!,
                  ],
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
                                    citation.sourceType == 'local'
                                        ? citation.label
                                        : '${citation.label} · ${citation.sourceId}',
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
