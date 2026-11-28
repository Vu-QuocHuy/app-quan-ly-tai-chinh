import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/monitoring/ai_telemetry.dart';
import 'package:hoadon_insight/features/chat/application/chat_metrics.dart';

void main() {
  test('turns stream emits each recorded chat turn with its route', () async {
    final recorder = ChatMetricsRecorder(log: false);
    final received = <ChatTurnMetric>[];
    final subscription = recorder.turns.listen(received.add);

    recorder.recordTurn(
      const ChatTurnMetric(
        route: ChatRoute.local,
        llmCalls: 0,
        latencyMs: 40,
        localIntent: 'expenseTotal',
      ),
    );
    recorder.recordTurn(
      const ChatTurnMetric(route: ChatRoute.command, llmCalls: 2, latencyMs: 3000),
    );
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(received.map((turn) => turn.route), [ChatRoute.local, ChatRoute.command]);
    expect(received.first.localIntent, 'expenseTotal');
  });

  test('classification on device is also reported to AiTelemetry', () {
    final telemetry = AiTelemetry(
      store: _MemoryStore(),
      clock: () => DateTime.utc(2026, 11, 28),
    );
    final recorder = ChatMetricsRecorder(log: false, telemetry: telemetry);

    recorder.recordLocalClassification(matched: true);

    expect(recorder.events.single['kind'], 'classify');
    expect(telemetry.events.single.event, 'local_answer');
    expect(telemetry.events.single.feature, 'classify');
    expect(telemetry.events.single.llmCalls, 0);
  });

  test('without a telemetry sink only the recorder is updated', () {
    final recorder = ChatMetricsRecorder(log: false);

    recorder.recordLocalClassification(matched: false);

    expect(recorder.events, hasLength(1));
  });
}

class _MemoryStore implements AiTelemetryStore {
  List<String> rows = [];

  @override
  Future<List<String>> read() async => rows;

  @override
  Future<void> write(List<String> value) async => rows = value;
}
