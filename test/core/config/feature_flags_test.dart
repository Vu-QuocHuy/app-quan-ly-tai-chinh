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
}

class _MemoryCache implements FeatureFlagCache {
  _MemoryCache([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}
