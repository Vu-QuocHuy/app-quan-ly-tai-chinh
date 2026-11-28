import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/monitoring/ai_telemetry.dart';
import '../../chat/application/chat_metrics.dart';
import 'ai_lab_providers.dart';

/// What one benchmark question produced.
@immutable
class AiLabChatOutcome {
  const AiLabChatOutcome({
    required this.route,
    this.llmCalls = 0,
    this.cloudCalls = 0,
    this.durationMs = 0,
    this.answerText,
  });

  /// The question got no turn before the per-question timeout.
  const AiLabChatOutcome.timeout(int durationMs)
    : this(route: 'timeout', durationMs: durationMs);

  /// `local`, `cloud`, `command`, another [ChatRoute] name, `timeout`, `error`.
  final String route;
  final int llmCalls;
  final int cloudCalls;
  final int durationMs;
  final String? answerText;
}

/// Sends one question to the chat and reports how it was served.
abstract interface class AiLabChatDriver {
  Future<AiLabChatOutcome> ask(String question);
}

/// Route label used in the CSV (`ChatRoute.llm` is the cloud path).
String aiLabRouteLabel(ChatRoute route) =>
    route == ChatRoute.llm ? 'cloud' : route.name;

/// Real driver: asks through [aiLabPromptRequestProvider] (the mounted chat
/// screen sends it), measures with [ChatMetricsRecorder.turns] (route) and the
/// `chat_turn` [AiTelemetry] event (network-layer calls and duration), then
/// reads the reply published in [aiLabLastAnswerProvider].
class ProviderChatDriver implements AiLabChatDriver {
  ProviderChatDriver(
    this._ref, {
    AiTelemetry? telemetry,
    this.timeout = const Duration(seconds: 60),
    this.answerGrace = const Duration(seconds: 3),
  }) : _telemetry = telemetry ?? AiTelemetry.instance;

  final Ref _ref;
  final AiTelemetry _telemetry;

  /// Per question: no turn within this long yields a `timeout` outcome.
  final Duration timeout;

  /// How long to wait for the reply text after the turn was recorded.
  final Duration answerGrace;

  @override
  Future<AiLabChatOutcome> ask(String question) async {
    final recorder = _ref.read(chatMetricsRecorderProvider);
    final previousAnswerId = _ref.read(aiLabLastAnswerProvider)?.messageId;
    final metric = Completer<ChatTurnMetric>();
    final event = Completer<AiTelemetryEvent>();
    final subscriptions = [
      recorder.turns.listen((value) {
        if (!metric.isCompleted) metric.complete(value);
      }),
      _telemetry.stream
          .where((value) => value.event == 'chat_turn')
          .listen((value) {
            if (!event.isCompleted) event.complete(value);
          }),
    ];
    final stopwatch = Stopwatch()..start();
    final requests = _ref.read(aiLabPromptRequestProvider.notifier);
    try {
      requests.state = question;
      await Future.wait([metric.future, event.future]).timeout(timeout);
      final answer = await _awaitAnswer(previousAnswerId);
      final telemetryEvent = await event.future;
      return AiLabChatOutcome(
        route: aiLabRouteLabel((await metric.future).route),
        llmCalls: telemetryEvent.llmCalls,
        cloudCalls: telemetryEvent.cloudCalls,
        durationMs: telemetryEvent.durationMs ?? stopwatch.elapsedMilliseconds,
        answerText: answer,
      );
    } on TimeoutException {
      if (requests.state == question) requests.state = null;
      return AiLabChatOutcome.timeout(stopwatch.elapsedMilliseconds);
    } finally {
      for (final subscription in subscriptions) {
        unawaited(subscription.cancel());
      }
    }
  }

  /// The chat screen publishes the reply right after the turn ends; wait a
  /// short while for a message other than the one that was there before.
  Future<String?> _awaitAnswer(String? previousId) async {
    final deadline = DateTime.now().add(answerGrace);
    while (true) {
      final answer = _ref.read(aiLabLastAnswerProvider);
      if (answer != null && answer.messageId != previousId) return answer.text;
      if (!DateTime.now().isBefore(deadline)) return null;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}
