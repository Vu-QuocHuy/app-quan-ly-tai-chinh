import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

/// Uploads a batch of telemetry rows (see `record_ai_client_events`).
typedef AiTelemetryUploader =
    Future<void> Function(List<Map<String, Object?>> batch);

/// One client-side AI telemetry event (N3).
///
/// Never contains user text, amounts or identifiers: only the feature, the
/// route taken (local / cloud / fallback), call counts and timings.
final class AiTelemetryEvent {
  const AiTelemetryEvent({
    required this.event,
    required this.feature,
    required this.occurredAt,
    this.route,
    this.llmCalls = 0,
    this.cloudCalls = 0,
    this.durationMs,
    this.payloadBytes,
    this.flagSet = 'none',
  });

  /// e.g. `chat_turn`, `remote_call`, `dedup_blocked`, `local_answer`.
  final String event;

  /// e.g. `chat`, `extract`, `classify`, `assistant_command`.
  final String feature;

  /// `local`, `cloud`, `fallback`, `error`, `blocked`.
  final String? route;
  final int llmCalls;
  final int cloudCalls;
  final int? durationMs;
  final int? payloadBytes;
  final String flagSet;
  final DateTime occurredAt;

  Map<String, Object?> toJson() => {
    'event': event,
    'feature': feature,
    if (route != null) 'route': route,
    'llmCalls': llmCalls,
    'cloudCalls': cloudCalls,
    if (durationMs != null) 'durationMs': durationMs,
    if (payloadBytes != null) 'payloadBytes': payloadBytes,
    'flagSet': flagSet,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
  };

  static AiTelemetryEvent? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final event = raw['event'];
    final feature = raw['feature'];
    final occurredAt = DateTime.tryParse('${raw['occurredAt']}');
    if (event is! String || feature is! String || occurredAt == null) {
      return null;
    }
    int? asInt(Object? value) => value is num ? value.toInt() : null;
    return AiTelemetryEvent(
      event: event,
      feature: feature,
      route: raw['route'] is String ? raw['route'] as String : null,
      llmCalls: asInt(raw['llmCalls']) ?? 0,
      cloudCalls: asInt(raw['cloudCalls']) ?? 0,
      durationMs: asInt(raw['durationMs']),
      payloadBytes: asInt(raw['payloadBytes']),
      flagSet: raw['flagSet'] is String ? raw['flagSet'] as String : 'none',
      occurredAt: occurredAt,
    );
  }
}

abstract interface class AiTelemetryStore {
  Future<List<String>> read();

  Future<void> write(List<String> rows);
}

class SharedPreferencesAiTelemetryStore implements AiTelemetryStore {
  const SharedPreferencesAiTelemetryStore();

  static const key = 'ai.telemetry.v1';

  @override
  Future<List<String>> read() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getStringList(key) ?? const [];
  }

  @override
  Future<void> write(List<String> rows) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(key, rows);
  }
}

/// Tracks one user-visible AI interaction (e.g. one chat question) from the
/// moment it starts until the answer is shown (M6, M7, M9).
final class AiTurn {
  AiTurn._(this._telemetry, this.feature) : _stopwatch = Stopwatch()..start();

  final AiTelemetry _telemetry;
  final String feature;
  final Stopwatch _stopwatch;
  int llmCalls = 0;
  int cloudCalls = 0;
  bool _fallback = false;
  bool _ended = false;

  /// The cloud path failed and the answer came from `LocalChatAssistant`.
  void markFallback() => _fallback = true;

  void end({String? route}) {
    if (_ended) return;
    _ended = true;
    _stopwatch.stop();
    _telemetry._endTurn(
      this,
      route ?? (_fallback ? 'fallback' : (cloudCalls == 0 ? 'local' : 'cloud')),
      _stopwatch.elapsedMilliseconds,
    );
  }
}

/// Client-side AI telemetry: ring buffer persisted locally, CSV export for
/// the benchmark report and optional upload behind `ai.telemetry.upload`.
final class AiTelemetry {
  AiTelemetry({
    AiTelemetryStore? store,
    DateTime Function()? clock,
    this.capacity = 1000,
    this.uploadBatchSize = 20,
  }) : _store = store ?? const SharedPreferencesAiTelemetryStore(),
       _clock = clock ?? DateTime.now;

  static final instance = AiTelemetry();

  /// Actions that run an LLM / VLM on the server.
  static const llmActions = {
    'chat',
    'assistant_command',
    'draft_transaction',
    'extract',
    'extract_submit',
  };

  /// Job status polling and cancellations are bookkeeping, not AI work.
  static const _bookkeepingActions = {
    'extract_status',
    'extract_cancel',
    'extract_retry',
  };

  final AiTelemetryStore _store;
  final DateTime Function() _clock;
  final int capacity;
  final int uploadBatchSize;

  final List<AiTelemetryEvent> _events = [];
  final List<AiTelemetryEvent> _pendingUpload = [];
  AiTelemetryUploader? _uploader;
  String _flagSet = 'none';
  AiTurn? _currentTurn;
  bool _loaded = false;
  bool _persistScheduled = false;
  Future<void>? _uploading;

  String get flagSet => _flagSet;

  List<AiTelemetryEvent> get events => List.unmodifiable(_events);

  /// Called whenever feature flags are (re)loaded.
  void configure({required String flagSet, AiTelemetryUploader? uploader}) {
    _flagSet = flagSet;
    _uploader = uploader;
    if (uploader == null) _pendingUpload.clear();
  }

  /// Starts a turn; remote calls made until [AiTurn.end] are attributed to it.
  AiTurn beginTurn(String feature) {
    final turn = AiTurn._(this, _safe(feature));
    _currentTurn = turn;
    return turn;
  }

  AiTurn? get currentTurn => _currentTurn;

  /// Called by `SupabaseFunctionClient` for every `ai-api` invocation.
  void recordRemoteCall(
    String action, {
    required Duration duration,
    required bool succeeded,
    int? payloadBytes,
  }) {
    if (_bookkeepingActions.contains(action)) return;
    final isLlm = llmActions.contains(action);
    final turn = _currentTurn;
    if (turn != null && !turn._ended) {
      turn.cloudCalls += 1;
      if (isLlm) turn.llmCalls += 1;
    }
    record(
      AiTelemetryEvent(
        event: 'remote_call',
        feature: _safe(action),
        route: succeeded ? 'cloud' : 'error',
        llmCalls: isLlm ? 1 : 0,
        cloudCalls: 1,
        durationMs: duration.inMilliseconds,
        payloadBytes: payloadBytes,
        flagSet: _flagSet,
        occurredAt: _clock().toUtc(),
      ),
    );
  }

  /// TV1 – O4: a duplicate receipt was blocked before any network call.
  void recordDuplicateBlocked({int? payloadBytes}) => record(
    AiTelemetryEvent(
      event: 'dedup_blocked',
      feature: 'extract',
      route: 'blocked',
      payloadBytes: payloadBytes,
      flagSet: _flagSet,
      occurredAt: _clock().toUtc(),
    ),
  );

  /// TV2 – H3/H8: a request was answered on device with 0 cloud calls.
  void recordLocal(String feature, {Duration? duration}) => record(
    AiTelemetryEvent(
      event: 'local_answer',
      feature: _safe(feature),
      route: 'local',
      durationMs: duration?.inMilliseconds,
      flagSet: _flagSet,
      occurredAt: _clock().toUtc(),
    ),
  );

  void record(AiTelemetryEvent event) {
    _events.add(event);
    if (_events.length > capacity) {
      _events.removeRange(0, _events.length - capacity);
    }
    if (_uploader != null) {
      _pendingUpload.add(event);
      if (_pendingUpload.length >= uploadBatchSize) unawaited(upload());
    }
    developer.log(
      jsonEncode(event.toJson()),
      name: 'hoadon_insight.ai_telemetry',
    );
    _schedulePersist();
  }

  void _endTurn(AiTurn turn, String route, int durationMs) {
    if (identical(_currentTurn, turn)) _currentTurn = null;
    record(
      AiTelemetryEvent(
        event: '${turn.feature}_turn',
        feature: turn.feature,
        route: route,
        llmCalls: turn.llmCalls,
        cloudCalls: turn.cloudCalls,
        durationMs: durationMs,
        flagSet: _flagSet,
        occurredAt: _clock().toUtc(),
      ),
    );
  }

  /// Restores events persisted by a previous app session.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final rows = await _store.read();
      final restored = rows
          .map((row) => AiTelemetryEvent.fromJson(jsonDecode(row)))
          .whereType<AiTelemetryEvent>()
          .toList();
      _events.insertAll(0, restored);
      if (_events.length > capacity) {
        _events.removeRange(0, _events.length - capacity);
      }
    } on Object {
      // Corrupt telemetry is not worth failing the app for.
    }
  }

  Future<void> clear() async {
    _events.clear();
    _pendingUpload.clear();
    await _store.write(const []);
  }

  /// Uploads pending events when `ai.telemetry.upload` is ON.
  Future<void> upload() {
    final running = _uploading;
    if (running != null) return running;
    final future = _uploadPending().whenComplete(() => _uploading = null);
    _uploading = future;
    return future;
  }

  Future<void> _uploadPending() async {
    final uploader = _uploader;
    while (uploader != null && _pendingUpload.isNotEmpty) {
      final batch = _pendingUpload.take(100).toList(growable: false);
      try {
        await uploader([for (final event in batch) event.toJson()]);
        _pendingUpload.removeRange(0, batch.length);
      } on Object catch (error) {
        developer.log(
          'Không gửi được telemetry AI.',
          name: 'hoadon_insight.ai_telemetry',
          error: error.runtimeType.toString(),
        );
        return;
      }
    }
  }

  /// CSV for TV4 (M6, M7, M9, M10 dedup).
  String exportCsv() {
    final buffer = StringBuffer(
      'occurred_at,event,feature,route,llm_calls,cloud_calls,duration_ms,'
      'payload_bytes,flag_set\n',
    );
    for (final event in _events) {
      buffer.writeln(
        [
          event.occurredAt.toUtc().toIso8601String(),
          event.event,
          event.feature,
          event.route ?? '',
          event.llmCalls,
          event.cloudCalls,
          event.durationMs ?? '',
          event.payloadBytes ?? '',
          '"${event.flagSet}"',
        ].join(','),
      );
    }
    return buffer.toString();
  }

  /// Aggregates for one feature's turns (default: chat), per flag set.
  AiTurnSummary summarize({String feature = 'chat', String? flagSet}) {
    final turns = _events
        .where(
          (event) =>
              event.event == '${feature}_turn' &&
              (flagSet == null || event.flagSet == flagSet),
        )
        .toList();
    final durations =
        turns.map((event) => event.durationMs).whereType<int>().toList()
          ..sort();
    int? percentile(double p) {
      if (durations.isEmpty) return null;
      final index = ((durations.length - 1) * p).round();
      return durations[index];
    }

    return AiTurnSummary(
      turnCount: turns.length,
      averageLlmCalls: turns.isEmpty
          ? 0
          : turns.fold<int>(0, (sum, event) => sum + event.llmCalls) /
                turns.length,
      localRate: turns.isEmpty
          ? 0
          : turns.where((event) => event.route == 'local').length /
                turns.length,
      fallbackCount: turns.where((event) => event.route == 'fallback').length,
      p50DurationMs: percentile(0.5),
      p95DurationMs: percentile(0.95),
      duplicateBlockedCount: _events
          .where(
            (event) =>
                event.event == 'dedup_blocked' &&
                (flagSet == null || event.flagSet == flagSet),
          )
          .length,
    );
  }

  void _schedulePersist() {
    if (_persistScheduled) return;
    _persistScheduled = true;
    scheduleMicrotask(() async {
      _persistScheduled = false;
      try {
        await _store.write([
          for (final event in _events) jsonEncode(event.toJson()),
        ]);
      } on Object {
        // Persisting telemetry is best effort.
      }
    });
  }

  static String _safe(String value) {
    final normalized = value.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9_.]'),
      '_',
    );
    if (normalized.isEmpty) return 'unknown';
    return normalized.length <= 32 ? normalized : normalized.substring(0, 32);
  }
}

final class AiTurnSummary {
  const AiTurnSummary({
    required this.turnCount,
    required this.averageLlmCalls,
    required this.localRate,
    required this.fallbackCount,
    required this.p50DurationMs,
    required this.p95DurationMs,
    required this.duplicateBlockedCount,
  });

  final int turnCount;

  /// M6 – average LLM calls per question.
  final double averageLlmCalls;

  /// M7 – share of turns answered with 0 cloud calls.
  final double localRate;
  final int fallbackCount;

  /// M9 – chat latency.
  final int? p50DurationMs;
  final int? p95DurationMs;

  /// M10 – receipts blocked before calling `extract`.
  final int duplicateBlockedCount;
}
