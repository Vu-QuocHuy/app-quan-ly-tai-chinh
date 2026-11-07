import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_environment.dart';

enum AppFeatureFlag {
  onlineAi('online_ai'),
  cloudSync('cloud_sync'),
  externalRates('external_rates'),

  // TV2 – chatbot/classify optimisations. Turn a row OFF in
  // `app_feature_flags` to measure the B0 baseline, ON for B1.
  /// H3: answer standard lookups from local SQLite with 0 LLM calls.
  chatLocalRouter('ai.chat.local_router'),

  /// H2: skip the `assistant_command` call for read-only questions.
  chatSkipCommand('ai.chat.skip_command'),

  /// H4: prefetch local FACTS and send them with the first `chat` call.
  chatPrefetchFacts('ai.chat.prefetch_facts'),

  /// H5: compact `answerChat` system prompt + `max_tokens`.
  chatCompactPrompt('ai.chat.compact_prompt'),

  /// H8: run `merchant-rules-v1` on device instead of calling `classify`.
  classifyLocal('ai.classify.local');

  const AppFeatureFlag(this.key);

  final String key;
}

@immutable
class FeatureFlags {
  const FeatureFlags({
    this.onlineAi = true,
    this.cloudSync = true,
    this.externalRates = true,
    this.chatLocalRouter = true,
    this.chatSkipCommand = true,
    this.chatPrefetchFacts = true,
    this.chatCompactPrompt = true,
    this.classifyLocal = true,
  });

  static const defaults = FeatureFlags();

  final bool onlineAi;
  final bool cloudSync;
  final bool externalRates;
  final bool chatLocalRouter;
  final bool chatSkipCommand;
  final bool chatPrefetchFacts;
  final bool chatCompactPrompt;
  final bool classifyLocal;

  bool isEnabled(AppFeatureFlag flag) => switch (flag) {
    AppFeatureFlag.onlineAi => onlineAi,
    AppFeatureFlag.cloudSync => cloudSync,
    AppFeatureFlag.externalRates => externalRates,
    AppFeatureFlag.chatLocalRouter => chatLocalRouter,
    AppFeatureFlag.chatSkipCommand => chatSkipCommand,
    AppFeatureFlag.chatPrefetchFacts => chatPrefetchFacts,
    AppFeatureFlag.chatCompactPrompt => chatCompactPrompt,
    AppFeatureFlag.classifyLocal => classifyLocal,
  };

  FeatureFlags _with(AppFeatureFlag flag, bool value) {
    bool v(AppFeatureFlag candidate) =>
        candidate == flag ? value : isEnabled(candidate);
    return FeatureFlags(
      onlineAi: v(AppFeatureFlag.onlineAi),
      cloudSync: v(AppFeatureFlag.cloudSync),
      externalRates: v(AppFeatureFlag.externalRates),
      chatLocalRouter: v(AppFeatureFlag.chatLocalRouter),
      chatSkipCommand: v(AppFeatureFlag.chatSkipCommand),
      chatPrefetchFacts: v(AppFeatureFlag.chatPrefetchFacts),
      chatCompactPrompt: v(AppFeatureFlag.chatCompactPrompt),
      classifyLocal: v(AppFeatureFlag.classifyLocal),
    );
  }

  Map<String, bool> toJson() => {
    for (final flag in AppFeatureFlag.values) flag.key: isEnabled(flag),
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
      AppFeatureFlag? flag;
      for (final candidate in AppFeatureFlag.values) {
        if (candidate.key == key) {
          flag = candidate;
          break;
        }
      }
      if (flag == null) continue;
      final rollout = row['rollout_percentage'];
      final rolloutPercentage = rollout is num
          ? rollout.toInt().clamp(0, 100)
          : 100;
      final active = enabled && _isInRollout(flag, rolloutPercentage, userId);
      flags = flags._with(flag, active);
    }
    return flags;
  }

  bool _isInRollout(AppFeatureFlag flag, int percentage, String? userId) {
    if (percentage <= 0 || userId == null || userId.trim().isEmpty) {
      return false;
    }
    if (percentage >= 100) return true;
    final digest = sha256.convert(utf8.encode('${userId.trim()}:${flag.key}'));
    var bucket = 0;
    for (final byte in digest.bytes.take(4)) {
      bucket = (bucket << 8) | byte;
    }
    return bucket % 100 < percentage;
  }
}
