import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How one chat turn was served. `local` and `fixed` cost 0 cloud calls.
enum ChatRoute {
  /// H3 local router answered from SQLite.
  local,

  /// Static reply from [ChatPrivacyPolicy] (identity / refusal).
  fixed,

  /// Went to the `chat` LLM action (with or without prefetched FACTS).
  llm,

  /// Went through `assistant_command` first.
  command,

  /// Transaction draft (`draft_transaction`).
  draft,

  /// LLM failed; answered by the offline fallback.
  fallback,
}

/// One client-side measurement for KPIs M6 (LLM calls/question),
/// M7 (local offload rate) and M9 (chat latency p50/p95).
@immutable
class ChatTurnMetric {
  const ChatTurnMetric({
    required this.route,
    required this.llmCalls,
    required this.latencyMs,
    this.localIntent,
    this.prefetchedTools = const [],
  });

  final ChatRoute route;
  final int llmCalls;
  final int latencyMs;
  final String? localIntent;
  final List<String> prefetchedTools;

  Map<String, Object?> toJson() => {
    'kind': 'chat_turn',
    'route': route.name,
    'llm_calls': llmCalls,
    'latency_ms': latencyMs,
    if (localIntent != null) 'local_intent': localIntent,
    if (prefetchedTools.isNotEmpty) 'prefetched_tools': prefetchedTools,
  };
}

/// In-memory ring buffer + `debugPrint` sink (`finmi_ai_metric {...}`), so
/// the evaluation script can read the log without any network call. Question
/// text is never recorded.
class ChatMetricsRecorder {
  ChatMetricsRecorder({this.capacity = 500, this.log = true});

  final int capacity;
  final bool log;
  final _events = ListQueue<Map<String, Object?>>();

  void recordTurn(ChatTurnMetric metric) => record(metric.toJson());

  /// H8: a merchant classification served on device instead of `classify`.
  void recordLocalClassification({required bool matched}) => record({
    'kind': 'classify',
    'route': 'local',
    'llm_calls': 0,
    'matched': matched,
  });

  void record(Map<String, Object?> event) {
    final entry = {...event, 'at': DateTime.now().toUtc().toIso8601String()};
    _events.addLast(entry);
    while (_events.length > capacity) {
      _events.removeFirst();
    }
    if (log) debugPrint('finmi_ai_metric ${jsonEncode(entry)}');
  }

  List<Map<String, Object?>> get events => List.unmodifiable(_events);

  void clear() => _events.clear();
}

final chatMetricsRecorderProvider = Provider<ChatMetricsRecorder>(
  (ref) => ChatMetricsRecorder(),
);
