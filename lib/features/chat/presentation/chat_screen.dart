import 'dart:async';
import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/cupertino.dart';
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
import '../domain/assistant_command.dart';
import '../domain/voice_activity.dart';
import '../data/assistant_command_client.dart';
import '../application/assistant_actions.dart';
import '../application/assistant_read_tools.dart';
import '../data/voice_file_cleanup.dart';
import 'voice_waveform.dart';
import '../../../core/localization/app_strings.dart';
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

const chatQuickPromptsEn = [
  'How much did I spend this month?',
  'How much did I earn this month?',
  'Compare spending this month with last month',
  'Which category has the highest spending?',
  'How much budget do I have left?',
  'Forecast spending until the end of the month',
  'My recent invoices',
  'Do I have any recurring expenses?',
  'Are there any unusual expenses?',
  'If I save 500,000 VND each month, how much will I save?',
];

const _enToViPromptMap = {
  'How much did I spend this month?': 'Tháng này tôi đã chi bao nhiêu?',
  'How much did I earn this month?': 'Tháng này tôi đã thu bao nhiêu?',
  'Compare spending this month with last month':
      'So sánh chi tiêu tháng này với tháng trước',
  'Which category has the highest spending?': 'Danh mục nào chi nhiều nhất?',
  'How much budget do I have left?': 'Tôi còn bao nhiêu hạn mức ngân sách?',
  'Forecast spending until the end of the month':
      'Dự báo chi tiêu đến cuối tháng',
  'My recent invoices': 'Hóa đơn gần đây của tôi',
  'Do I have any recurring expenses?': 'Tôi có khoản chi định kỳ nào không?',
  'Are there any unusual expenses?': 'Có khoản chi nào bất thường không?',
  'If I save 500,000 VND each month, how much will I save?':
      'Nếu tôi giảm chi 500.000đ mỗi tháng thì tiết kiệm được bao nhiêu?',
};

Future<void> showFinmiAssistant(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
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

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  static const _maxVoiceRecordingSeconds = 30;
  static const _localAnswerTimeout = Duration(seconds: 2);
  static const _llmAnswerTimeout = Duration(seconds: 30);

  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final _uuid = const Uuid();
  late final _chatSessionId = _uuid.v4();
  final _audioRecorder = AudioRecorder();
  late List<ChatMessage> _messages;
  bool _sending = false;
  bool _recording = false;
  bool _startingRecording = false;
  int _voiceSession = 0;
  bool _transcribing = false;
  // Blocks input while a recording is being discarded; unlike _transcribing
  // it shows no transcription progress.
  bool _cancellingVoice = false;
  Timer? _recordingTimer;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  VoiceActivity _voiceActivity = VoiceActivity();
  final _voiceLevel = VoiceLevelSamples();
  String _voiceLocale = 'vi-VN';
  String? _connectionNote;
  TransactionDraftResult? _draftConversation;
  final Map<String, _TransactionDraft> _draftCards = {};
  String? _savingDraftMessageId;
  AssistantCommand? _pendingCommand;
  AssistantCommand? _duplicateCommand;
  String? _commandAccount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    _voiceSession++;
    _recordingTimer?.cancel();
    unawaited(_amplitudeSubscription?.cancel());
    _inputController.dispose();
    _scrollController.dispose();
    _voiceLevel.dispose();
    unawaited(
      (_recording || _startingRecording || _transcribing
              ? _audioRecorder.cancel()
              : Future<void>.value())
          .then((_) => _audioRecorder.dispose()),
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_cancelVoiceInput());
    }
  }

  Future<void> _cancelVoiceInput() async {
    _voiceSession++;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    final stoppingAmplitude = _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    final wasRecording = _recording || _startingRecording;
    setState(() {
      _recording = false;
      _cancellingVoice = wasRecording;
    });
    try {
      await stoppingAmplitude;
      if (wasRecording) await _audioRecorder.cancel();
    } on Object catch (error) {
      if (mounted) setState(() => _connectionNote = friendlyMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _cancellingVoice = false;
          _transcribing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(assistantActionsProvider(_chatSessionId));
    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    width: 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  'assets/branding/finmi/icon.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Icon(
                    CupertinoIcons.chat_bubble_2_fill,
                    color: Theme.of(context).colorScheme.primary,
                    size: 18,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  context.tr.isEn ? 'Finmi Assistant' : 'Trợ lý Finmi',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: context.tr.isEn ? 'Close assistant' : 'Đóng trợ lý',
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
          padding: const EdgeInsets.all(24),
          child: Text(
            context.tr.isEn
                ? 'Start by asking a question about your income or expenses.'
                : 'Bắt đầu bằng một câu hỏi về thu chi của bạn.',
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
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Semantics(
                liveRegion: true,
                label: context.tr.isEn
                    ? 'Assistant is thinking'
                    : 'Trợ lý đang suy nghĩ',
                child: Text(
                  context.tr.isEn ? 'Thinking ...' : 'Đang suy nghĩ ...',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
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
    if (_sending || _recording || _transcribing || _startingRecording) {
      return const SizedBox.shrink();
    }
    final isEn = context.tr.isEn;
    final suggestions = isEn ? chatQuickPromptsEn : chatQuickPrompts;
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
    final busy =
        _sending || _transcribing || _cancellingVoice || _startingRecording;
    final canSend =
        !busy && !_recording && _inputController.text.trim().isNotEmpty;
    final canRecord = !busy;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isListening = _recording || _transcribing;

    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isListening)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
                  child: _transcribing
                      ? _buildTranscribingProgress(context)
                      : Row(
                          children: [
                            Icon(Icons.mic, size: 16, color: scheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Semantics(
                                label: context.tr.isEn
                                    ? 'Listening'
                                    : 'Đang nghe',
                                child: VoiceWaveform(
                                  level: _voiceLevel,
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: TextField(
                        controller: _inputController,
                        enabled: !busy && !_recording,
                        minLines: 1,
                        maxLines: 4,
                        scrollPhysics: const ClampingScrollPhysics(),
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        textAlignVertical: TextAlignVertical.center,
                        onChanged: (_) => setState(() {}),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                          height: 1.35,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: context.tr.isEn
                              ? 'Message assistant…'
                              : 'Nhắn trợ lý…',
                          hintStyle: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: 0.7,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          filled: true,
                          fillColor: scheme.surfaceContainerHighest.withValues(
                            alpha: 0.35,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide(
                              color: scheme.outlineVariant,
                              width: 1.25,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide(
                              color: scheme.outlineVariant,
                              width: 1.25,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide(
                              color: scheme.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_recording)
                    IconButton(
                      tooltip: context.tr.isEn
                          ? 'Cancel recording'
                          : 'Xóa bản ghi âm',
                      onPressed: _cancelVoiceInput,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    label: _recording
                        ? (context.tr.isEn ? 'Stop and send' : 'Dừng và gửi')
                        : 'Nói câu hỏi hoặc mô tả giao dịch, tối đa $_maxVoiceRecordingSeconds giây',
                    child: IconButton.filledTonal(
                      tooltip: _recording
                          ? (context.tr.isEn ? 'Stop and send' : 'Dừng và gửi')
                          : 'Nói câu hỏi hoặc giao dịch · tối đa $_maxVoiceRecordingSeconds giây',
                      onPressed: canRecord ? _toggleVoiceInput : null,
                      style: IconButton.styleFrom(
                        fixedSize: const Size(44, 44),
                        minimumSize: const Size(44, 44),
                        padding: EdgeInsets.zero,
                      ),
                      icon: Icon(
                        _transcribing
                            ? Icons.hourglass_top
                            : _recording
                            ? Icons.stop_rounded
                            : Icons.mic_none,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Semantics(
                    button: true,
                    label: context.tr.isEn ? 'Send question' : 'Gửi câu hỏi',
                    child: IconButton(
                      tooltip: context.tr.isEn
                          ? 'Send question'
                          : 'Gửi câu hỏi',
                      onPressed: canSend
                          ? () => _send(_inputController.text)
                          : null,
                      style: IconButton.styleFrom(
                        fixedSize: const Size(44, 44),
                        minimumSize: const Size(44, 44),
                        padding: EdgeInsets.zero,
                        backgroundColor: canSend
                            ? scheme.primary
                            : scheme.surfaceContainerHighest.withValues(
                                alpha: 0.5,
                              ),
                        foregroundColor: canSend
                            ? Colors.white
                            : scheme.onSurfaceVariant.withValues(alpha: 0.38),
                        disabledBackgroundColor: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        disabledForegroundColor: scheme.onSurfaceVariant
                            .withValues(alpha: 0.38),
                      ),
                      icon: Icon(
                        Icons.send_rounded,
                        size: 19,
                        color: canSend
                            ? Colors.white
                            : scheme.onSurfaceVariant.withValues(alpha: 0.38),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Step 1 of a voice question: the recording is being transcribed. Step 2
  /// (the assistant answering) uses the regular thinking indicator.
  Widget _buildTranscribingProgress(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = context.tr.isEn
        ? 'Converting speech to text…'
        : 'Đang chuyển giọng nói thành văn bản…';
    return Semantics(
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.graphic_eq, size: 16, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                minHeight: 3,
                color: scheme.primary,
                backgroundColor: scheme.primary.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleVoiceInput() async {
    if (_recording) {
      await _finishVoiceInput();
      return;
    }
    if (_sending || _transcribing || _cancellingVoice || _startingRecording) {
      return;
    }
    final session = ++_voiceSession;

    final tr = context.tr;
    _voiceLocale = tr.isEn ? 'en-US' : 'vi-VN';
    _voiceActivity = VoiceActivity();
    setState(() => _startingRecording = true);
    try {
      if (!await _audioRecorder.hasPermission()) {
        throw StateError(
          tr.isEn
              ? 'Microphone permission required for voice input.'
              : 'Bạn cần cấp quyền micro để nhập bằng giọng nói.',
        );
      }
      if (!mounted || session != _voiceSession) return;
      final path = kIsWeb
          ? 'voice-${_uuid.v4()}.wav'
          : '${(await getTemporaryDirectory()).path}/voice-${_uuid.v4()}.wav';
      if (!mounted || session != _voiceSession) return;
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      if (!mounted || session != _voiceSession) {
        await _audioRecorder.cancel();
        return;
      }
      setState(() {
        _recording = true;
        _connectionNote = null;
      });
      _amplitudeSubscription = _audioRecorder
          .onAmplitudeChanged(const Duration(milliseconds: 200))
          .listen(
            (amplitude) {
              if (session == _voiceSession) {
                _voiceLevel.add(_normalizeDecibels(amplitude.current));
              }
              if (mounted &&
                  session == _voiceSession &&
                  _recording &&
                  _voiceActivity.sample(amplitude.current, DateTime.now())) {
                unawaited(_finishVoiceInput());
              }
            },
            onError: (Object _) {
              /* Manual stop and the hard limit remain available. */
            },
          );
      _recordingTimer = Timer(
        const Duration(seconds: _maxVoiceRecordingSeconds),
        () => unawaited(_finishVoiceInput()),
      );
    } on Object catch (error) {
      if (mounted) setState(() => _connectionNote = friendlyMessage(error));
    } finally {
      if (mounted) setState(() => _startingRecording = false);
    }
  }

  /// Maps recorder loudness (dBFS, roughly -60 silent to 0 loud) to 0–1.
  static double _normalizeDecibels(double decibels) {
    if (!decibels.isFinite) return 0;
    return ((decibels + 50) / 45).clamp(0.0, 1.0);
  }

  /// Stops recording (manual stop, silence or the hard limit), transcribes the
  /// audio through `ai-api` and sends the result to the assistant. The same
  /// flow runs on every platform, including web.
  Future<void> _finishVoiceInput() async {
    if (!_recording) return;
    if (_transcribing) return;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    unawaited(_amplitudeSubscription?.cancel());
    _amplitudeSubscription = null;

    final session = _voiceSession;
    final requestLocale = _voiceLocale;
    var transcribed = false;
    String? recordingPath;
    setState(() {
      _recording = false;
      _transcribing = true;
    });
    try {
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
      if (!mounted || session != _voiceSession) return;
      final client = ref.read(supabaseClientProvider);
      if (client == null) throw StateError('Chưa kết nối được dịch vụ AI.');
      final response = await client.functions.invoke(
        'ai-api',
        body: {
          'action': 'transcribe',
          'locale': requestLocale,
          'requestId': _uuid.v4(),
          'audioBase64': base64Encode(bytes),
        },
      );
      if (!mounted || session != _voiceSession) return;
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
      setState(() => _connectionNote = null);
      transcribed = true;
    } on Object catch (error) {
      if (mounted) setState(() => _connectionNote = friendlyMessage(error));
    } finally {
      if (recordingPath != null) {
        try {
          await _audioRecorder.cancel();
        } on Object {
          // The recorder may already have been disposed when this screen closed.
        }
        await deleteVoiceFile(recordingPath);
      }
      if (mounted && session == _voiceSession) {
        setState(() => _transcribing = false);
        if (transcribed) unawaited(_send(_inputController.text));
      }
    }
  }

  Future<void> _send(String value) async {
    final question = value.trim();
    if (question.isEmpty ||
        _sending ||
        _recording ||
        _startingRecording ||
        _transcribing ||
        _cancellingVoice) {
      return;
    }
    final effectiveQuestion = _enToViPromptMap[question] ?? question;
    final account = ref.read(authUserProvider).valueOrNull?.id;
    if (_commandAccount != account) {
      _pendingCommand = null;
      _duplicateCommand = null;
      ref.read(assistantActionsProvider(_chatSessionId)).reset();
      _commandAccount = account;
    }
    final isBlockedQuestion = ChatPrivacyPolicy.isBlockedQuestion(
      effectiveQuestion,
    );
    final isDraftFollowUp =
        !isBlockedQuestion &&
        _draftConversation != null &&
        (_isDraftCancellation(effectiveQuestion) ||
            _looksLikeDraftAnswer(effectiveQuestion) ||
            _looksLikeTransactionEntry(effectiveQuestion));
    final draftRequest =
        (!isBlockedQuestion && _looksLikeTransactionEntry(effectiveQuestion)) ||
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

    final fixedReply = ChatPrivacyPolicy.fixedReply(question, context.tr.isEn);
    if (fixedReply != null) {
      _appendCommandReply(fixedReply);
      return;
    }
    if (isBlockedQuestion) {
      setState(() {
        _messages = [
          ..._messages,
          ChatMessage(
            id: _uuid.v4(),
            role: ChatMessageRole.assistant,
            text: ChatPrivacyPolicy.refusal(context.tr.isEn),
            createdAt: DateTime.now(),
          ),
        ];
        _sending = false;
      });
      _scrollToEnd();
      return;
    }

    try {
      if (ref.read(assistantCommandClientProvider).isConfigured) {
        await _handleAssistantCommand(question);
        return;
      }
      if (draftRequest) {
        await _handleTransactionMessage(effectiveQuestion);
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
      final reply = await _answerFallback(
        effectiveQuestion,
        draftRequest: draftRequest,
      );
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

  void _appendCommandReply(
    String text, {
    List<ChatCitation> citations = const [],
  }) {
    if (!mounted) return;
    setState(() {
      _messages = [
        ..._messages,
        ChatMessage(
          id: _uuid.v4(),
          role: ChatMessageRole.assistant,
          text: text,
          citations: citations,
          createdAt: DateTime.now(),
        ),
      ];
      _sending = false;
    });
    _scrollToEnd();
  }

  Future<void> _handleAssistantCommand(String question) async {
    final en = context.tr.isEn;
    final actions = ref.read(assistantActionsProvider(_chatSessionId));
    final account = ref.read(authUserProvider).valueOrNull?.id;
    final confirmed =
        _duplicateCommand != null &&
        RegExp(
          r'^(đồng ý|xác nhận|vẫn lưu|ghi thêm|có|yes|confirm|save anyway|record another)[.! ]*$',
          caseSensitive: false,
        ).hasMatch(question.trim());
    try {
      final categories = [
        ...await ref.read(incomeCategoriesProvider.future),
        ...await ref.read(categoriesProvider.future),
      ];
      final command = confirmed
          ? _duplicateCommand!
          : await ref
                .read(assistantCommandClientProvider)
                .interpret(
                  question,
                  categories: categories,
                  pending: _pendingCommand,
                  last: actions.last,
                );
      if (!mounted || account != ref.read(authUserProvider).valueOrNull?.id) {
        if (mounted) {
          _pendingCommand = null;
          _duplicateCommand = null;
          actions.reset();
          _appendCommandReply(
            en
                ? 'Account changed. Please send your request again.'
                : 'Tài khoản đã thay đổi. Hãy gửi lại yêu cầu.',
          );
        }
        return;
      }
      _duplicateCommand = null;
      if (command.kind == 'cancel') {
        _pendingCommand = null;
        _appendCommandReply(
          en
              ? 'Cancelled the pending request. Saved entries are unchanged.'
              : 'Đã hủy yêu cầu đang chờ. Các khoản đã lưu vẫn được giữ.',
        );
        return;
      }
      if (command.kind == 'identity' || command.kind == 'reject') {
        _pendingCommand = null;
        _appendCommandReply(
          command.kind == 'identity'
              ? (en
                    ? 'I’m FinmiAI, your financial assistant.'
                    : 'Tôi là FinmiAI, trợ lý tài chính của bạn.')
              : ChatPrivacyPolicy.refusal(en),
        );
        return;
      }
      if (command.kind == 'query') {
        _pendingCommand = null;
        final reply = await _answerWithLlm(question);
        _appendCommandReply(reply.text, citations: reply.citations);
        return;
      }
      _pendingCommand = command;
      final missing = command.clarification(en);
      if (missing != null) {
        _appendCommandReply(missing);
        return;
      }
      final result = await actions.execute(
        command,
        english: en,
        allowDuplicate: confirmed,
      );
      if (!mounted) return;
      _duplicateCommand = result.confirmDuplicate ? command : null;
      _pendingCommand = result.confirmDuplicate || result.needsInput
          ? command
          : null;
      _appendCommandReply(result.text);
      if (result.route != null) {
        final router = GoRouter.of(context);
        if (widget.embedded) Navigator.of(context).pop();
        router.push(result.route!);
      }
    } on Object {
      if (!mounted) return;
      // A failed write can be an ambiguous network result. Never reroute it to
      // a different writer, automatically retry, or announce success.
      _appendCommandReply(
        en
            ? 'I could not confirm this request. Check your records before retrying; no automatic retry was made.'
            : 'Chưa xác nhận được kết quả yêu cầu. Hãy kiểm tra sổ trước khi thử lại; ứng dụng không tự gửi lại lệnh.',
      );
    }
  }

  Future<ChatReply> _answerFallback(
    String question, {
    required bool draftRequest,
  }) async {
    if (context.tr.isEn) {
      return const ChatReply(
        text:
            'FinmiAI is currently offline. Please reconnect to ask questions or record transactions in English.',
      );
    }
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

    final extraFacts = await readAssistantFacts(ref, plan.toolCall!.name);
    final facts =
        extraFacts ??
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
    text: ref.read(appLocaleProvider).languageCode == 'en'
        ? 'I’m FinmiAI, your financial assistant. Ask about your finances or record income, expenses, debts and group funds.'
        : 'Tôi là FinmiAI, trợ lý tài chính của bạn. Bạn có thể hỏi về tài chính hoặc ghi thu chi, nợ và quỹ nhóm.',
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
    final isEn = context.tr.isEn;
    final isUser = message.role == ChatMessageRole.user;
    final scheme = Theme.of(context).colorScheme;
    final color = isUser
        ? scheme.primaryContainer
        : scheme.surfaceContainerHigh;
    final displayText = message.id == 'welcome'
        ? (isEn
              ? 'Hello! I can help you check total income, total expense, budgets, categories, '
                    'month comparisons, and recurring transactions. You can also describe income or expenses '
                    'to create drafts before confirming and saving.'
              : 'Xin chào! Mình có thể giúp bạn xem tổng thu, tổng chi, ngân sách, danh mục, '
                    'so sánh tháng và khoản chi định kỳ. Bạn cũng có thể mô tả khoản thu/chi để '
                    'tạo bản nháp rồi xác nhận trước khi lưu.')
        : message.text;

    return Semantics(
      label: displayText.isEmpty
          ? (isEn ? 'Transaction draft' : 'Bản nháp giao dịch')
          : '${isUser ? (isEn ? 'You' : 'Bạn') : (isEn ? 'Assistant' : 'Trợ lý')}: $displayText',
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
                  if (displayText.isNotEmpty) Text(displayText),
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
