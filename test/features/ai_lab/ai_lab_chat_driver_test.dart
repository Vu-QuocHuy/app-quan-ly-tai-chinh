import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/monitoring/ai_telemetry.dart';
import 'package:hoadon_insight/features/ai_lab/application/ai_lab_chat_driver.dart';
import 'package:hoadon_insight/features/ai_lab/application/ai_lab_providers.dart';
import 'package:hoadon_insight/features/chat/application/chat_metrics.dart';

class _MemoryStore implements AiTelemetryStore {
  @override
  Future<List<String>> read() async => const [];

  @override
  Future<void> write(List<String> rows) async {}
}

void main() {
  late AiTelemetry telemetry;
  late ChatMetricsRecorder recorder;
  late ProviderContainer container;
  late ProviderChatDriver driver;

  setUp(() {
    telemetry = AiTelemetry(store: _MemoryStore());
    recorder = ChatMetricsRecorder(log: false);
    final driverProvider = Provider<ProviderChatDriver>(
      (ref) => ProviderChatDriver(
        ref,
        telemetry: telemetry,
        timeout: const Duration(milliseconds: 300),
        answerGrace: const Duration(milliseconds: 100),
      ),
    );
    container = ProviderContainer(
      overrides: [chatMetricsRecorderProvider.overrideWithValue(recorder)],
    );
    driver = container.read(driverProvider);
  });

  tearDown(() => container.dispose());

  /// Plays the part of the chat screen: takes the request, resets it, then
  /// records the metric, ends the telemetry turn and publishes the answer.
  void fakeChatScreen({
    required ChatRoute route,
    required int llmCalls,
    String? answer,
    bool publishAnswer = true,
    String messageId = 'm1',
  }) {
    late final ProviderSubscription<String?> sub;
    sub = container.listen<String?>(aiLabPromptRequestProvider, (_, next) {
      if (next == null) return;
      sub.close();
      container.read(aiLabPromptRequestProvider.notifier).state = null;
      scheduleMicrotask(() async {
        final turn = telemetry.beginTurn('chat');
        for (var i = 0; i < llmCalls; i++) {
          telemetry.recordRemoteCall(
            'chat',
            duration: const Duration(milliseconds: 5),
            succeeded: true,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 12));
        recorder.recordTurn(
          ChatTurnMetric(route: route, llmCalls: llmCalls, latencyMs: 12),
        );
        turn.end();
        if (publishAnswer) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          container.read(aiLabLastAnswerProvider.notifier).state =
              AiLabAnswer(messageId: messageId, text: answer ?? '');
        }
      });
    });
  }

  test('cloud: route llm -> "cloud", lấy llm/cloud/duration từ telemetry',
      () async {
    fakeChatScreen(route: ChatRoute.llm, llmCalls: 2, answer: 'Xin chào');

    final outcome = await driver.ask('Tháng này tôi chi bao nhiêu?');

    expect(outcome.route, 'cloud');
    expect(outcome.llmCalls, 2);
    expect(outcome.cloudCalls, 2);
    expect(outcome.durationMs, greaterThanOrEqualTo(10));
    expect(outcome.answerText, 'Xin chào');
    expect(container.read(aiLabPromptRequestProvider), isNull);
  });

  test('local: 0 lượt gọi', () async {
    fakeChatScreen(route: ChatRoute.local, llmCalls: 0, answer: '10.545.000');

    final outcome = await driver.ask('q');

    expect(outcome.route, 'local');
    expect(outcome.llmCalls, 0);
    expect(outcome.cloudCalls, 0);
    expect(outcome.answerText, '10.545.000');
  });

  test('command và các route khác giữ tên ChatRoute', () async {
    fakeChatScreen(route: ChatRoute.command, llmCalls: 1, answer: 'ok');
    expect((await driver.ask('q')).route, 'command');
  });

  test('route fallback giữ nguyên tên', () async {
    fakeChatScreen(route: ChatRoute.fallback, llmCalls: 1, answer: 'ok');
    expect((await driver.ask('q')).route, 'fallback');
  });

  test('câu trả lời cũ (messageId trùng) không bị đọc nhầm', () async {
    container.read(aiLabLastAnswerProvider.notifier).state = const AiLabAnswer(
      messageId: 'old',
      text: 'cũ',
    );
    fakeChatScreen(
      route: ChatRoute.local,
      llmCalls: 0,
      publishAnswer: false,
    );

    final outcome = await driver.ask('q');

    expect(outcome.route, 'local');
    expect(outcome.answerText, isNull);
  });

  test('timeout: route timeout, không ném, và rút yêu cầu chưa được nhận',
      () async {
    final outcome = await driver.ask('không ai trả lời');

    expect(outcome.route, 'timeout');
    expect(outcome.llmCalls, 0);
    expect(outcome.answerText, isNull);
    expect(container.read(aiLabPromptRequestProvider), isNull);
  });

  test('hai lượt liên tiếp, lượt sau không nhận sự kiện lượt trước', () async {
    fakeChatScreen(route: ChatRoute.llm, llmCalls: 1, answer: 'một');
    final first = await driver.ask('a');
    fakeChatScreen(
      route: ChatRoute.local,
      llmCalls: 0,
      answer: 'hai',
      messageId: 'm2',
    );
    final second = await driver.ask('b');

    expect(first.route, 'cloud');
    expect(second.route, 'local');
    expect(second.answerText, 'hai');
  });
}
