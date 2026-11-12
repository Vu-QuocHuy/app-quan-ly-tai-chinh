import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_environment.dart';

enum AppFeatureFlag {
  onlineAi('online_ai'),
  cloudSync('cloud_sync'),
  externalRates('external_rates');

  const AppFeatureFlag(this.key);

  final String key;
}

/// AI optimization switches used to compare baseline (B0, all OFF) with the
/// optimized build (B1). Rows live in `public.app_feature_flags`; the server
/// evaluates the same keys in `supabase/functions/_shared/ai_platform.ts`.
enum AiOptimizationFlag {
  /// TV1 – O1/O3: Gemini `thinkingLevel: low` + `maxOutputTokens` (server).
  extractThinkingLow('ai.extract.thinking_low'),

  /// TV1 – O2: resize receipts to 1600 px before upload (client).
  extractImage1600('ai.extract.image_1600'),

  /// TV1 – O4: hash + duplicate check before calling `extract` (client).
  extractPrecheckDedup('ai.extract.precheck_dedup'),

  /// TV1 – O5: arithmetic validator instead of fixed confidence (client).
  extractValidator('ai.extract.validator'),

  /// TV2 – H3: answer standard lookups locally, 0 LLM calls (client).
  chatLocalRouter('ai.chat.local_router'),

  /// TV2 – H2/H4: skip `assistant_command` for questions, send FACTS in the
  /// first `chat` call (client).
  chatMergeCalls('ai.chat.merge_calls'),

  /// TV2 – H5: shorter `answerChat` system prompt (server).
  chatPromptV2('ai.chat.prompt_v2'),

  /// TV2 – H8: run `merchant-rules-v1` on device (client).
  classifyLocal('ai.classify.local'),

  /// TV3 – N5: circuit breaker + failover 9Router → Gemini → local (server).
  routerFailover('ai.router.failover'),

  /// TV3 – N3: upload client AI telemetry to `ai_client_events` (client).
  telemetryUpload('ai.telemetry.upload');

  const AiOptimizationFlag(this.key);

  final String key;

  static AiOptimizationFlag? fromKey(String key) {
    for (final flag in values) {
      if (flag.key == key) return flag;
    }
    return null;
  }
}

@immutable
class FeatureFlags {
  const FeatureFlags({
    this.onlineAi = true,
    this.cloudSync = true,
    this.externalRates = true,
    this.aiOptimizations = const {},
  });

  static const defaults = FeatureFlags();

  final bool onlineAi;
  final bool cloudSync;
  final bool externalRates;

  /// Enabled AI optimization flags. Missing = OFF (baseline behaviour).
  final Set<AiOptimizationFlag> aiOptimizations;

  bool isAiEnabled(AiOptimizationFlag flag) => aiOptimizations.contains(flag);

  /// Stable label matching `ai_request_metrics.flag_set` (`none` = B0).
  String get aiFlagSet {
    final keys = aiOptimizations.map((flag) => flag.key).toList()..sort();
    return keys.isEmpty ? 'none' : keys.join(',');
  }

  FeatureFlags _withAi(AiOptimizationFlag flag, bool value) => FeatureFlags(
    onlineAi: onlineAi,
    cloudSync: cloudSync,
    externalRates: externalRates,
    aiOptimizations: value
        ? {...aiOptimizations, flag}
        : aiOptimizations.where((item) => item != flag).toSet(),
  );

  bool isEnabled(AppFeatureFlag flag) => switch (flag) {
    AppFeatureFlag.onlineAi => onlineAi,
    AppFeatureFlag.cloudSync => cloudSync,
    AppFeatureFlag.externalRates => externalRates,
  };

  FeatureFlags _with(AppFeatureFlag flag, bool value) => switch (flag) {
    AppFeatureFlag.onlineAi => FeatureFlags(
      onlineAi: value,
      cloudSync: cloudSync,
      externalRates: externalRates,
      aiOptimizations: aiOptimizations,
    ),
    AppFeatureFlag.cloudSync => FeatureFlags(
      onlineAi: onlineAi,
      cloudSync: value,
      externalRates: externalRates,
      aiOptimizations: aiOptimizations,
    ),
    AppFeatureFlag.externalRates => FeatureFlags(
      onlineAi: onlineAi,
      cloudSync: cloudSync,
      externalRates: value,
      aiOptimizations: aiOptimizations,
    ),
  };

  Map<String, bool> toJson() => {
    for (final flag in AppFeatureFlag.values) flag.key: isEnabled(flag),
    for (final flag in AiOptimizationFlag.values) flag.key: isAiEnabled(flag),
  };
}

abstract interface class FeatureFlagCache {
  Future<String?> read();

  Future<void> write(String value);
}

class SharedPreferencesFeatureFlagCache implements FeatureFlagCache {
  const SharedPreferencesFeatureFlagCache();

  static const key = 'remote.feature_flags.v1';

  @override
  Future<String?> read() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(key);
  }

  @override
  Future<void> write(String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, value);
  }
}

class RemoteConfigService {
  RemoteConfigService(
    this._client, {
    FeatureFlagCache? cache,
    DateTime Function()? now,
    this.cacheTtl = const Duration(hours: 24),
  }) : _cache = cache ?? const SharedPreferencesFeatureFlagCache(),
       _now = now ?? DateTime.now;

  final SupabaseClient? _client;
  final FeatureFlagCache _cache;
  final DateTime Function() _now;
  final Duration cacheTtl;

  Future<FeatureFlags> load({required String? userId}) async {
    final remoteRows = await _fetchRemote(userId);
    if (remoteRows != null) {
      try {
        await _cache.write(
          jsonEncode({
            'fetchedAt': _now().toUtc().toIso8601String(),
            'environment': AppEnvironment.current.name,
            'rows': remoteRows,
          }),
        );
      } on Object {
        return _evaluate(remoteRows, userId);
      }
      return _evaluate(remoteRows, userId);
    }

    final cached = await _readCache();
    if (cached != null) return _evaluate(cached, userId);
    return FeatureFlags.defaults;
  }

  Future<List<Map<String, Object?>>?> _fetchRemote(String? userId) async {
    final client = _client;
    if (client == null || userId == null || userId.trim().isEmpty) return null;
    try {
      final response = await client
          .from('app_feature_flags')
          .select('key, enabled, rollout_percentage')
          .eq('environment', AppEnvironment.current.name)
          .timeout(const Duration(seconds: 4));
      return response
          .whereType<Map>()
          .map((row) => Map<String, Object?>.from(row))
          .toList(growable: false);
    } on Object {
      return null;
    }
  }

  Future<List<Map<String, Object?>>?> _readCache() async {
    try {
      final raw = await _cache.read();
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['rows'] is! List) return null;
      final fetchedAt = DateTime.tryParse('${decoded['fetchedAt']}');
      if (fetchedAt == null ||
          _now().toUtc().difference(fetchedAt) > cacheTtl) {
        return null;
      }
      if (decoded['environment'] != AppEnvironment.current.name) return null;
      return (decoded['rows'] as List)
          .whereType<Map>()
          .map((row) => Map<String, Object?>.from(row))
          .toList(growable: false);
    } on Object {
      return null;
    }
  }

  FeatureFlags _evaluate(Iterable<Map<String, Object?>> rows, String? userId) {
    var flags = FeatureFlags.defaults;
    for (final row in rows) {
      final key = row['key'];
      final enabled = row['enabled'];
      if (key is! String || enabled is! bool) continue;
      final rollout = row['rollout_percentage'];
      final rolloutPercentage = rollout is num
          ? rollout.toInt().clamp(0, 100)
          : 100;
      final aiFlag = AiOptimizationFlag.fromKey(key);
      if (aiFlag != null) {
        final active = enabled && _isInRollout(key, rolloutPercentage, userId);
        flags = flags._withAi(aiFlag, active);
        continue;
      }
      AppFeatureFlag? flag;
      for (final candidate in AppFeatureFlag.values) {
        if (candidate.key == key) {
          flag = candidate;
          break;
        }
      }
      if (flag == null) continue;
      final active =
          enabled && _isInRollout(flag.key, rolloutPercentage, userId);
      flags = flags._with(flag, active);
    }
    return flags;
  }

  bool _isInRollout(String flagKey, int percentage, String? userId) {
    if (percentage <= 0 || userId == null || userId.trim().isEmpty) {
      return false;
    }
    if (percentage >= 100) return true;
    final digest = sha256.convert(utf8.encode('${userId.trim()}:$flagKey'));
    var bucket = 0;
    for (final byte in digest.bytes.take(4)) {
      bucket = (bucket << 8) | byte;
    }
    return bucket % 100 < percentage;
  }
}
