import 'package:flutter/foundation.dart';

/// One `ai-api` call as seen by the AI Lab overlay (debug builds only).
///
/// Built from the optional `_meta` object that the server returns when
/// `AI_EXPOSE_USAGE_META=true`. Every field can be missing: the overlay must
/// show "—" instead of failing.
@immutable
final class AiLabCall {
  const AiLabCall({
    required this.action,
    required this.durationMs,
    this.llmCalls = 0,
    this.inputTokens,
    this.outputTokens,
    this.thinkingTokens,
    this.provider,
    this.failover = false,
    this.model,
    this.serverFlagSet,
  });

  /// Tolerant parser for `_meta`: wrong types are ignored, never thrown.
  factory AiLabCall.fromMeta(
    Object? meta, {
    required String action,
    required int durationMs,
  }) {
    final map = meta is Map ? meta : const <Object?, Object?>{};
    int? asInt(String key) {
      final value = map[key];
      return value is int ? value : (value is num ? value.toInt() : null);
    }

    String? asString(String key) {
      final value = map[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    return AiLabCall(
      action: action,
      durationMs: durationMs,
      llmCalls: asInt('llmCalls') ?? 0,
      inputTokens: asInt('inputTokens'),
      outputTokens: asInt('outputTokens'),
      thinkingTokens: asInt('thinkingTokens'),
      provider: asString('provider'),
      failover: map['failover'] == true,
      model: asString('model'),
      serverFlagSet: asString('flagSet'),
    );
  }

  final String action;
  final int durationMs;
  final int llmCalls;
  final int? inputTokens;
  final int? outputTokens;
  final int? thinkingTokens;
  final String? provider;
  final bool failover;
  final String? model;

  /// `flag_set` label evaluated by the server for this request.
  final String? serverFlagSet;

  /// Sum of the token parts that are present, or `null` when none is known.
  int? get totalTokens {
    final parts = [inputTokens, outputTokens, thinkingTokens];
    if (parts.every((part) => part == null)) return null;
    return parts.fold<int>(0, (sum, part) => sum + (part ?? 0));
  }
}

enum AiLabRoute { local, cloud, fallback, degraded }

/// Outcome of one chat turn, shown as a badge under the assistant bubble.
@immutable
final class AiLabTurn {
  const AiLabTurn({
    required this.messageId,
    required this.route,
    required this.llmCalls,
    required this.durationMs,
    this.provider,
  });

  final String messageId;
  final AiLabRoute route;
  final int llmCalls;
  final int durationMs;
  final String? provider;
}

@immutable
final class AiLabTotals {
  const AiLabTotals({
    this.llmCalls = 0,
    this.tokens = 0,
    this.savedLlmCalls = 0,
  });

  final int llmCalls;
  final int tokens;

  /// LLM calls avoided versus the B0 chat flow (3 calls per lookup question).
  final int savedLlmCalls;
}

/// What the server did while a chat turn was running.
@immutable
final class AiLabTurnSignals {
  const AiLabTurnSignals({this.degraded = false, this.failoverProvider});

  /// The server answered `AI_DEGRADED` (9Router and Gemini both failed).
  final bool degraded;

  /// Provider that took over after 9Router failed (for example `gemini`).
  final String? failoverProvider;
}

/// State behind the AI Lab overlay. Only fed in debug builds.
class AiLabStore extends ChangeNotifier {
  AiLabStore({this.capacity = 200});

  static final instance = AiLabStore();

  /// B0 makes 3 `ai-api` calls for a lookup question (spec §5.2, scene 1).
  static const baselineChatLlmCalls = 3;
  static const faults = {'429', '500', 'timeout'};
  static const _extractActions = {'extract', 'extract_status'};

  final int capacity;
  final Map<String, AiLabTurn> _turns = {};
  AiLabTotals _totals = const AiLabTotals();
  AiLabCall? _lastExtract;
  String? _fault;
  String? _lastServerFlagSet;
  bool _tamperExtractTotal = false;
  bool _degraded = false;
  String? _failoverProvider;

  AiLabTotals get totals => _totals;

  /// Latest OCR call that reported token usage.
  AiLabCall? get lastExtract => _lastExtract;

  /// Latest `flag_set` label reported by the server, or `null` if unknown.
  String? get lastServerFlagSet => _lastServerFlagSet;

  /// `x-finmi-fault` value sent with every `ai-api` call, or `null`.
  String? get fault => _fault;
  set fault(String? value) {
    if (value != null && !faults.contains(value)) {
      throw ArgumentError.value(value, 'fault', 'phải là một trong $faults');
    }
    if (value == _fault) return;
    _fault = value;
    notifyListeners();
  }

  /// Simulated OCR error for demo scene 6 (total is distorted on purpose).
  bool get tamperExtractTotal => _tamperExtractTotal;
  set tamperExtractTotal(bool value) {
    if (value == _tamperExtractTotal) return;
    _tamperExtractTotal = value;
    notifyListeners();
  }

  /// The server returned `AI_DEGRADED` during the current chat turn.
  void markDegraded() => _degraded = true;

  /// Signals collected since the previous call; reading clears them.
  AiLabTurnSignals takeTurnSignals() {
    final signals = AiLabTurnSignals(
      degraded: _degraded,
      failoverProvider: _failoverProvider,
    );
    _degraded = false;
    _failoverProvider = null;
    return signals;
  }

  void recordCall(AiLabCall call) {
    if (call.failover) _failoverProvider = call.provider ?? 'gemini';
    _totals = AiLabTotals(
      llmCalls: _totals.llmCalls + call.llmCalls,
      tokens: _totals.tokens + (call.totalTokens ?? 0),
      savedLlmCalls: _totals.savedLlmCalls,
    );
    final serverFlagSet = call.serverFlagSet;
    if (serverFlagSet != null) _lastServerFlagSet = serverFlagSet;
    if (_extractActions.contains(call.action) && call.totalTokens != null) {
      _lastExtract = call;
    }
    notifyListeners();
  }

  void recordTurn(AiLabTurn turn) {
    _turns.remove(turn.messageId);
    _turns[turn.messageId] = turn;
    while (_turns.length > capacity) {
      _turns.remove(_turns.keys.first);
    }
    final saved = baselineChatLlmCalls - turn.llmCalls;
    _totals = AiLabTotals(
      llmCalls: _totals.llmCalls,
      tokens: _totals.tokens,
      savedLlmCalls: _totals.savedLlmCalls + (saved > 0 ? saved : 0),
    );
    notifyListeners();
  }

  AiLabTurn? turnFor(String messageId) => _turns[messageId];

  void reset() {
    _turns.clear();
    _totals = const AiLabTotals();
    _lastExtract = null;
    _lastServerFlagSet = null;
    _fault = null;
    _tamperExtractTotal = false;
    _degraded = false;
    _failoverProvider = null;
    notifyListeners();
  }
}
