import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/monitoring/ai_lab_store.dart';
import 'package:hoadon_insight/core/monitoring/ai_telemetry.dart';
import 'package:hoadon_insight/features/ai_lab/application/ai_lab_turn_mapper.dart';

AiTelemetryEvent _turn({
  String route = 'cloud',
  int llmCalls = 1,
  int? durationMs = 2100,
}) => AiTelemetryEvent(
  event: 'chat_turn',
  feature: 'chat',
  occurredAt: DateTime.utc(2026, 11, 28),
  route: route,
  llmCalls: llmCalls,
  durationMs: durationMs,
);

void main() {
  const none = AiLabTurnSignals();

  test('a turn answered with no cloud call is a local turn', () {
    final turn = aiLabTurnFrom(
      messageId: 'm1',
      event: _turn(route: 'local', llmCalls: 0, durationMs: 40),
      signals: none,
    );

    expect(turn.messageId, 'm1');
    expect(turn.route, AiLabRoute.local);
    expect(turn.llmCalls, 0);
    expect(turn.durationMs, 40);
  });

  test('a normal cloud turn keeps its call count and duration', () {
    final turn = aiLabTurnFrom(messageId: 'm2', event: _turn(), signals: none);

    expect(turn.route, AiLabRoute.cloud);
    expect(turn.llmCalls, 1);
    expect(turn.durationMs, 2100);
    expect(turn.provider, isNull);
  });

  test('server failover is shown as a fallback with the provider', () {
    final turn = aiLabTurnFrom(
      messageId: 'm3',
      event: _turn(),
      signals: const AiLabTurnSignals(failoverProvider: 'gemini'),
    );

    expect(turn.route, AiLabRoute.fallback);
    expect(turn.provider, 'gemini');
  });

  test('the client falling back to the offline assistant is a fallback', () {
    final turn = aiLabTurnFrom(
      messageId: 'm4',
      event: _turn(route: 'fallback'),
      signals: none,
    );

    expect(turn.route, AiLabRoute.fallback);
    expect(turn.provider, isNull);
  });

  test('AI_DEGRADED wins over every other signal', () {
    final turn = aiLabTurnFrom(
      messageId: 'm5',
      event: _turn(route: 'fallback'),
      signals: const AiLabTurnSignals(degraded: true, failoverProvider: 'gemini'),
    );

    expect(turn.route, AiLabRoute.degraded);
  });

  test('a missing duration is reported as 0', () {
    final turn = aiLabTurnFrom(
      messageId: 'm6',
      event: _turn(durationMs: null),
      signals: none,
    );

    expect(turn.durationMs, 0);
  });
}
