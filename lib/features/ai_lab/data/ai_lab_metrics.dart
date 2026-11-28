import 'dart:async';

import '../../../core/config/ai_flag_profile.dart';
import '../../../core/config/feature_flags.dart';
import '../../../core/monitoring/ai_lab_store.dart';

/// Builds the `metrics` event of docs/ai-optimization/ailab-protocol.md §2.
///
/// Pure: everything it reports comes from the arguments ([now] included).
Map<String, Object?> buildAiLabMetrics({
  required DateTime now,
  required AiFlagProfileKind launchProfile,
  required AiFlagProfileKind profile,
  required Set<AiOptimizationFlag> flags,
  required String? serverFlagSet,
  required AiLabTotals totals,
  required AiLabCall? lastExtract,
  required List<AiLabTurn> turns,
  required List<AiLabCall> calls,
}) {
  final keys =
      AiOptimizationFlag.values
          .where(flags.contains)
          .map((flag) => flag.key)
          .toList()
        ..sort();
  return <String, Object?>{
    'ailab': 1,
    'event': 'metrics',
    'ts': now.millisecondsSinceEpoch,
    'launchProfile': launchProfile.name,
    'profile': profile.name,
    'enabledCount': keys.length,
    'flagSet': keys.isEmpty ? 'none' : keys.join(','),
    'flags': <String, bool>{
      for (final flag in AiOptimizationFlag.values)
        flag.key: flags.contains(flag),
    },
    'serverFlagSet': serverFlagSet,
    'totals': <String, Object?>{
      'llmCalls': totals.llmCalls,
      'tokens': totals.tokens,
      'savedLlmCalls': totals.savedLlmCalls,
      'costUsd': totals.costUsd,
      'savedUsd': totals.savedUsd,
      'savedOcrCalls': totals.savedOcrCalls,
    },
    'lastExtract': lastExtract == null
        ? null
        : <String, Object?>{
            'inputTokens': lastExtract.inputTokens,
            'thinkingTokens': lastExtract.thinkingTokens,
            'outputTokens': lastExtract.outputTokens,
            'durationMs': lastExtract.durationMs,
            'provider': lastExtract.provider,
          },
    'turns': [
      for (final turn in turns)
        <String, Object?>{
          'messageId': turn.messageId,
          'route': turn.route.name,
          'llmCalls': turn.llmCalls,
          'durationMs': turn.durationMs,
          'provider': turn.provider,
        },
    ],
    'calls': [
      for (final call in calls)
        <String, Object?>{
          'action': call.action,
          'durationMs': call.durationMs,
          'llmCalls': call.llmCalls,
          'provider': call.provider,
          'failover': call.failover,
          'inputTokens': call.inputTokens,
          'outputTokens': call.outputTokens,
          'thinkingTokens': call.thinkingTokens,
        },
    ],
  };
}

typedef AiLabTimerFactory = Timer Function(Duration delay, void Function() run);

/// Runs [action] at most once per [interval] (default 4 per second). A request
/// made inside the quiet period is not lost: it fires once, as soon as the
/// interval has elapsed (trailing emission).
class AiLabThrottle {
  AiLabThrottle({
    required this.action,
    this.interval = const Duration(milliseconds: 250),
    DateTime Function()? now,
    AiLabTimerFactory? timerFactory,
  }) : _now = now ?? DateTime.now,
       _timerFactory = timerFactory ?? Timer.new;

  final void Function() action;
  final Duration interval;
  final DateTime Function() _now;
  final AiLabTimerFactory _timerFactory;

  DateTime? _last;
  Timer? _pending;
  bool _disposed = false;

  /// Whether a trailing run is waiting for its timer.
  bool get hasPending => _pending != null;

  /// Asks for a run: now if the interval has passed, else once it does.
  void request() {
    if (_disposed || _pending != null) return;
    final last = _last;
    final wait = last == null ? Duration.zero : interval - _now().difference(last);
    if (wait <= Duration.zero) {
      _fire();
    } else {
      _pending = _timerFactory(wait, () {
        _pending = null;
        _fire();
      });
    }
  }

  /// Runs now (a `hello` must be answered at once) and drops a waiting run.
  void flush() {
    if (_disposed) return;
    _pending?.cancel();
    _pending = null;
    _fire();
  }

  void dispose() {
    _disposed = true;
    _pending?.cancel();
    _pending = null;
  }

  void _fire() {
    _last = _now();
    try {
      action();
    } catch (_) {
      // The demo feed must never break the app.
    }
  }
}
