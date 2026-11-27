import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:hoadon_insight/core/config/feature_flags.dart';

void main() {
  test('uses safe defaults when remote config is unavailable', () async {
    final flags = await RemoteConfigService(
      null,
      cache: _MemoryCache(),
    ).load(userId: 'user-1');

    expect(flags.onlineAi, isTrue);
    expect(flags.cloudSync, isTrue);
    expect(flags.externalRates, isTrue);
  });

  test('reads cached flags and applies enabled rollout', () async {
    final now = DateTime.utc(2026, 9, 17, 8);
    final cache = _MemoryCache(
      jsonEncode({
        'fetchedAt': now.toIso8601String(),
        'environment': 'dev',
        'rows': [
          {'key': 'online_ai', 'enabled': false, 'rollout_percentage': 100},
          {'key': 'cloud_sync', 'enabled': true, 'rollout_percentage': 100},
        ],
      }),
    );

    final flags = await RemoteConfigService(
      null,
      cache: cache,
      now: () => now.add(const Duration(hours: 1)),
    ).load(userId: 'user-1');

    expect(flags.onlineAi, isFalse);
    expect(flags.cloudSync, isTrue);
    expect(flags.externalRates, isTrue);
  });

  test('ignores expired cached flags', () async {
    final now = DateTime.utc(2026, 9, 17, 8);
    final cache = _MemoryCache(
      jsonEncode({
        'fetchedAt': now.subtract(const Duration(days: 2)).toIso8601String(),
        'environment': 'dev',
        'rows': [
          {'key': 'online_ai', 'enabled': false, 'rollout_percentage': 100},
        ],
      }),
    );

    final flags = await RemoteConfigService(
      null,
      cache: cache,
      now: () => now,
    ).load(userId: 'user-1');

    expect(flags.onlineAi, isTrue);
  });

  test('AI optimization flags default to OFF (baseline B0)', () async {
    final flags = await RemoteConfigService(
      null,
      cache: _MemoryCache(),
    ).load(userId: 'user-1');

    for (final flag in AiOptimizationFlag.values) {
      expect(flags.isAiEnabled(flag), isFalse, reason: flag.key);
    }
    expect(flags.aiFlagSet, 'none');
  });

  test('reads AI optimization flags with rollout like the server', () async {
    final now = DateTime.utc(2026, 11, 12, 8);
    final cache = _MemoryCache(
      jsonEncode({
        'fetchedAt': now.toIso8601String(),
        'environment': 'dev',
        'rows': [
          {
            'key': 'ai.router.failover',
            'enabled': true,
            'rollout_percentage': 100,
          },
          {
            'key': 'ai.chat.local_router',
            'enabled': true,
            'rollout_percentage': 100,
          },
          // 0% rollout must stay OFF even when enabled.
          {
            'key': 'ai.chat.prompt_v2',
            'enabled': true,
            'rollout_percentage': 0,
          },
          {'key': 'ai.extract.validator', 'enabled': false},
          {'key': 'ai.unknown', 'enabled': true},
        ],
      }),
    );

    final flags = await RemoteConfigService(
      null,
      cache: cache,
      now: () => now,
    ).load(userId: 'user-1');

    expect(flags.isAiEnabled(AiOptimizationFlag.routerFailover), isTrue);
    expect(flags.isAiEnabled(AiOptimizationFlag.chatLocalRouter), isTrue);
    expect(flags.isAiEnabled(AiOptimizationFlag.chatPromptV2), isFalse);
    expect(flags.isAiEnabled(AiOptimizationFlag.extractValidator), isFalse);
    expect(flags.aiFlagSet, 'ai.chat.local_router,ai.router.failover');
    expect(flags.onlineAi, isTrue, reason: 'legacy flags keep defaults');
  });
}

class _MemoryCache implements FeatureFlagCache {
  _MemoryCache([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}
