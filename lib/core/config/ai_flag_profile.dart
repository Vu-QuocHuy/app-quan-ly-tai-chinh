import 'package:flutter/foundation.dart';

import 'feature_flags.dart';

enum AiFlagProfileKind { server, b0, b1, custom }

/// Forces the AI optimisation flags of one app instance (debug builds only).
///
/// Chosen with `--dart-define=AI_FLAG_PROFILE=<value>`:
/// - `server` (default): use the flags served by `app_feature_flags`;
/// - `b0`: every `ai.*` optimisation OFF (baseline);
/// - `b1`: every `ai.*` optimisation ON;
/// - `only:<key>[,<key>...]`: just the listed flags ON.
///
/// This lets two web instances (ports 8080/8081) run B0 and B1 side by side
/// against the same Supabase project. The same choice is sent to the server
/// as the `x-finmi-flags` header, see `aiDebugHeaders`.
@immutable
final class AiFlagProfile {
  const AiFlagProfile._(this.kind, this._enabled);

  static const _raw = String.fromEnvironment(
    'AI_FLAG_PROFILE',
    defaultValue: 'server',
  );

  /// The profile of this build: `server` unless this is a debug build with a
  /// valid `AI_FLAG_PROFILE`.
  static final AiFlagProfile active = AiFlagProfile.fromEnvironment();

  static const _server = AiFlagProfile._(AiFlagProfileKind.server, null);

  factory AiFlagProfile.fromEnvironment({
    bool debug = kDebugMode,
    String raw = _raw,
  }) {
    if (!debug) return _server;
    try {
      return AiFlagProfile.parse(raw);
    } on FormatException {
      return _server;
    }
  }

  /// Throws [FormatException] for an unknown profile or flag key.
  factory AiFlagProfile.parse(String raw) {
    final value = raw.trim();
    switch (value) {
      case 'server':
        return _server;
      case 'b0':
        return const AiFlagProfile._(AiFlagProfileKind.b0, {});
      case 'b1':
        return AiFlagProfile._(
          AiFlagProfileKind.b1,
          AiOptimizationFlag.values.toSet(),
        );
    }
    const prefix = 'only:';
    if (value.startsWith(prefix)) {
      final keys = value
          .substring(prefix.length)
          .split(',')
          .map((key) => key.trim())
          .where((key) => key.isNotEmpty);
      final enabled = <AiOptimizationFlag>{};
      for (final key in keys) {
        final flag = AiOptimizationFlag.fromKey(key);
        if (flag == null) {
          throw FormatException('Unknown AI flag "$key" in AI_FLAG_PROFILE');
        }
        enabled.add(flag);
      }
      if (enabled.isEmpty) {
        throw const FormatException('AI_FLAG_PROFILE "only:" needs a flag key');
      }
      return AiFlagProfile._(AiFlagProfileKind.custom, enabled);
    }
    throw FormatException('Unknown AI_FLAG_PROFILE "$raw"');
  }

  final AiFlagProfileKind kind;

  /// `null` for the server profile.
  final Set<AiOptimizationFlag>? _enabled;

  /// Replaces the AI optimisation flags of [fromServer]; the product flags
  /// (`online_ai`, `cloud_sync`, `external_rates`) always stay as served.
  FeatureFlags apply(FeatureFlags fromServer) {
    final enabled = _enabled;
    if (enabled == null) return fromServer;
    return FeatureFlags(
      onlineAi: fromServer.onlineAi,
      cloudSync: fromServer.cloudSync,
      externalRates: fromServer.externalRates,
      aiOptimizations: Set.unmodifiable(enabled),
    );
  }

  /// Value of the `x-finmi-flags` header: `key=1,key=0,...` for all 10 flags,
  /// or `null` for the server profile.
  String? get headerValue {
    final enabled = _enabled;
    if (enabled == null) return null;
    return AiOptimizationFlag.values
        .map((flag) => '${flag.key}=${enabled.contains(flag) ? 1 : 0}')
        .join(',');
  }

  String get label => switch (kind) {
    AiFlagProfileKind.b0 => 'B0 – GỐC',
    AiFlagProfileKind.b1 => 'B1 – TỐI ƯU',
    AiFlagProfileKind.custom => 'TÙY CHỈNH',
    AiFlagProfileKind.server => 'SERVER',
  };
}
