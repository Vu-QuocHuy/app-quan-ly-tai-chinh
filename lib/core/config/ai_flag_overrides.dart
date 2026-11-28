import 'package:flutter/foundation.dart';

import '../../features/ai_lab/ai_lab_config.dart';
import 'ai_flag_profile.dart';
import 'feature_flags.dart';

/// The AI optimisation flags in force for THIS app instance, changeable at
/// runtime by the AI Lab (debug builds with `--dart-define=AI_LAB=true`).
///
/// Starts from [AiFlagProfile.active]: `server` means "no override" (the flags
/// served by `app_feature_flags` apply). Runtime changes are only accepted when
/// [canChange] is true; otherwise every setter is a no-op and the object
/// behaves exactly like the static profile (release builds).
class AiFlagOverrides extends ChangeNotifier {
  AiFlagOverrides({AiFlagProfile? profile, bool? allowChanges})
    : canChange = allowChanges ?? (kDebugMode && AiLabConfig.enabled),
      _enabled = (profile ?? AiFlagProfile.active).enabledFlags == null
          ? null
          : {...(profile ?? AiFlagProfile.active).enabledFlags!};

  static final AiFlagOverrides instance = AiFlagOverrides();

  /// Whether runtime changes are accepted.
  final bool canChange;

  Set<AiOptimizationFlag>? _enabled;
  int _revision = 0;

  /// Enabled flags, or `null` when the server flags apply (no override).
  Set<AiOptimizationFlag>? get enabled {
    final value = _enabled;
    return value == null ? null : Set.unmodifiable(value);
  }

  /// Bumped on every effective change; lets providers re-evaluate.
  int get revision => _revision;

  /// Whether [flag] is on in the override. `false` while there is none.
  bool isOn(AiOptimizationFlag flag) => _enabled?.contains(flag) ?? false;

  int get enabledCount => _enabled?.length ?? 0;

  AiFlagProfileKind get kind {
    final value = _enabled;
    if (value == null) return AiFlagProfileKind.server;
    if (value.isEmpty) return AiFlagProfileKind.b0;
    if (value.length == AiOptimizationFlag.values.length) {
      return AiFlagProfileKind.b1;
    }
    return AiFlagProfileKind.custom;
  }

  /// `x-finmi-flags` value (all 10 flags as `key=1|0`), `null` without override.
  String? get headerValue {
    final value = _enabled;
    if (value == null) return null;
    return AiOptimizationFlag.values
        .map((flag) => '${flag.key}=${value.contains(flag) ? 1 : 0}')
        .join(',');
  }

  void setFlag(AiOptimizationFlag flag, bool on) =>
      _change((set) => on ? set.add(flag) : set.remove(flag));

  void setAll(bool on) => _change((set) {
    final before = set.length;
    if (on) {
      set.addAll(AiOptimizationFlag.values);
    } else {
      set.clear();
    }
    return set.length != before;
  });

  /// Applies `{flagKey: bool}`: unknown keys are ignored and absent keys keep
  /// their value. Without any known key nothing changes.
  void applyMap(Map<String, bool> values) {
    final known = <AiOptimizationFlag, bool>{
      for (final entry in values.entries)
        ?AiOptimizationFlag.fromKey(entry.key): entry.value,
    };
    if (known.isEmpty) return;
    _change((set) {
      var changed = false;
      for (final entry in known.entries) {
        changed |= entry.value ? set.add(entry.key) : set.remove(entry.key);
      }
      return changed;
    });
  }

  /// Replaces the AI flags of [fromServer]; product flags stay as served.
  FeatureFlags apply(FeatureFlags fromServer) {
    final value = _enabled;
    if (value == null) return fromServer;
    return FeatureFlags(
      onlineAi: fromServer.onlineAi,
      cloudSync: fromServer.cloudSync,
      externalRates: fromServer.externalRates,
      aiOptimizations: Set.unmodifiable(value),
    );
  }

  /// Runs [mutate] on a copy of the current set (all-off when following the
  /// server). It returns whether it changed anything.
  void _change(bool Function(Set<AiOptimizationFlag> set) mutate) {
    if (!canChange) return;
    final wasServer = _enabled == null;
    final next = {...?_enabled};
    final changed = mutate(next);
    if (!changed && !wasServer) return;
    _enabled = next;
    _revision++;
    notifyListeners();
  }
}
