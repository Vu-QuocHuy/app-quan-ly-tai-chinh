import 'package:flutter_test/flutter_test.dart';

import 'package:hoadon_insight/core/monitoring/ai_telemetry.dart';

void main() {
  AiTelemetry telemetry({AiTelemetryStore? store}) => AiTelemetry(
    store: store ?? _MemoryStore(),
    clock: () => DateTime.utc(2026, 11, 12, 8),
  );

  test('a chat turn without cloud calls is counted as local', () {
    final subject = telemetry()..configure(flagSet: 'ai.chat.local_router');
    subject.beginTurn('chat').end();

    final summary = subject.summarize();
    expect(summary.turnCount, 1);
    expect(summary.averageLlmCalls, 0);
    expect(summary.localRate, 1);
    expect(subject.events.single.flagSet, 'ai.chat.local_router');
  });

  test('remote calls are attributed to the current turn', () {
    final subject = telemetry();
    final turn = subject.beginTurn('chat');
    subject.recordRemoteCall(
      'assistant_command',
      duration: const Duration(milliseconds: 900),
      succeeded: true,
    );
    subject.recordRemoteCall(
      'chat',
      duration: const Duration(milliseconds: 1200),
      succeeded: true,
    );
    subject.recordRemoteCall(
      'extract_status',
      duration: const Duration(milliseconds: 50),
      succeeded: true,
    );
    turn.end();

    final summary = subject.summarize();
    expect(summary.averageLlmCalls, 2);
    expect(summary.localRate, 0);
    expect(
      subject.events.where((event) => event.event == 'remote_call'),
      hasLength(2),
      reason: 'job status polling is bookkeeping, not AI work',
    );
  });

  test('fallback turns and duplicate blocks are reported', () {
    final subject = telemetry();
    final turn = subject.beginTurn('chat');
    subject.recordRemoteCall(
      'chat',
      duration: const Duration(milliseconds: 300),
      succeeded: false,
    );
    turn
      ..markFallback()
      ..end()
      ..end();
    subject.recordDuplicateBlocked(payloadBytes: 250000);

    final summary = subject.summarize();
    expect(summary.turnCount, 1, reason: 'end() is idempotent');
    expect(summary.fallbackCount, 1);
    expect(summary.duplicateBlockedCount, 1);
  });

  test('exports CSV and uploads in batches when enabled', () async {
    final uploaded = <List<Map<String, Object?>>>[];
    final subject = AiTelemetry(
      store: _MemoryStore(),
      clock: () => DateTime.utc(2026, 11, 12, 8),
      uploadBatchSize: 2,
    )..configure(flagSet: 'none', uploader: (batch) async => uploaded.add(batch));

    subject.recordLocal('classify');
    subject.recordLocal('chat');
    await subject.upload();

    expect(uploaded.expand((batch) => batch), hasLength(2));
    final csv = subject.exportCsv().trim().split('\n');
    expect(csv.first, startsWith('occurred_at,event,feature,route'));
    expect(csv, hasLength(3));
    expect(csv[1], contains('local_answer,classify,local'));
  });

  test('restores persisted events', () async {
    final store = _MemoryStore();
    final first = telemetry(store: store);
    first.recordLocal('chat');
    await Future<void>.delayed(Duration.zero);

    final second = telemetry(store: store);
    await second.load();
    expect(second.events, hasLength(1));
    expect(second.events.single.feature, 'chat');
  });
}

class _MemoryStore implements AiTelemetryStore {
  List<String> rows = const [];

  @override
  Future<List<String>> read() async => rows;

  @override
  Future<void> write(List<String> rows) async => this.rows = List.of(rows);
}
