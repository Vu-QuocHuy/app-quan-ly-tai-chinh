import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/ai_flag_overrides.dart';
import '../../../core/config/ai_flag_profile.dart';
import '../../../core/config/feature_flags.dart';
import '../../../core/monitoring/ai_lab_store.dart';
import '../../../core/providers/app_providers.dart';
import '../ai_lab_config.dart';
import '../application/ai_lab_actions.dart';
import 'ai_lab_bridge.dart';
import 'ai_lab_metrics.dart';

typedef AiLabBridgeStarter =
    void Function() Function(
      void Function(Object? data, String origin) onMessage,
    );

/// Wraps [child] and, only when the AI Lab is enabled, lets the demo controller
/// page drive [AiLabActions] through `window.postMessage`, and streams
/// `metrics` events back to it (docs/ai-optimization/ailab-protocol.md).
class AiLabBridgeHost extends ConsumerStatefulWidget {
  const AiLabBridgeHost({
    super.key,
    required this.child,
    this.enabled,
    this.startBridge,
    this.postEvent,
    this.now,
  });

  final Widget child;

  /// Defaults to [AiLabConfig.enabled]; tests can force it.
  final bool? enabled;

  /// Defaults to [startAiLabBridge].
  final AiLabBridgeStarter? startBridge;

  /// Defaults to [postAiLabEvent] (no-op outside an iframe).
  final void Function(Map<String, Object?> event)? postEvent;

  /// Clock for the `ts` field and the 4/s throttle.
  final DateTime Function()? now;

  @override
  ConsumerState<AiLabBridgeHost> createState() => _AiLabBridgeHostState();
}

class _AiLabBridgeHostState extends ConsumerState<AiLabBridgeHost> {
  void Function()? _stop;
  AiLabThrottle? _throttle;
  AiFlagOverrides? _overrides;

  bool get _enabled => widget.enabled ?? AiLabConfig.enabled;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    if (!_enabled) return;
    try {
      _stop = (widget.startBridge ?? startAiLabBridge)(_onMessage);
    } catch (_) {
      _stop = null;
    }
    try {
      final AiFlagOverrides overrides = ref.read<AiFlagOverrides>(
        aiFlagOverridesProvider,
      );
      overrides.addListener(_onChanged);
      _overrides = overrides;
      AiLabStore.instance.addListener(_onChanged);
      _throttle = AiLabThrottle(action: _emit, now: _now);
      // On start; after the first frame so provider reads are safe.
      WidgetsBinding.instance.addPostFrameCallback((_) => _throttle?.request());
    } catch (_) {
      // The metrics feed is optional.
    }
  }

  void _onChanged() => _throttle?.request();

  void _emit() {
    try {
      if (!mounted) return;
      final AiFlagOverrides overrides =
          _overrides ?? ref.read<AiFlagOverrides>(aiFlagOverridesProvider);
      final store = AiLabStore.instance;
      final flags =
          overrides.enabled ??
          ref.read(featureFlagsProvider).value?.aiOptimizations ??
          const <AiOptimizationFlag>{};
      final event = buildAiLabMetrics(
        now: _now(),
        launchProfile: AiFlagProfile.active.kind,
        profile: overrides.kind,
        flags: flags,
        serverFlagSet: store.lastServerFlagSet,
        totals: store.totals,
        lastExtract: store.lastExtract,
        turns: store.recentTurns,
        calls: store.recentCalls,
      );
      (widget.postEvent ?? postAiLabEvent)(event);
    } catch (_) {
      // Never let the demo feed break the app.
    }
  }

  void _onMessage(Object? data, String origin) {
    try {
      final command = parseAiLabMessage(data, origin);
      if (command == null || !mounted) return;
      if (command is AiLabHello) {
        _throttle?.flush();
        return;
      }
      runAiLabCommand(ref.read(aiLabActionsProvider), command).catchError((
        Object _,
      ) {
        // Command failures are shown by the AI Lab itself, never fatal.
      });
    } catch (_) {
      // Swallow: a bad message must never crash the app.
    }
  }

  @override
  void dispose() {
    try {
      _stop?.call();
    } catch (_) {}
    _stop = null;
    try {
      _overrides?.removeListener(_onChanged);
      AiLabStore.instance.removeListener(_onChanged);
      _throttle?.dispose();
    } catch (_) {}
    _throttle = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_enabled) {
      // The effective flags (server-provided when there is no override) are
      // part of the metrics event.
      ref.listen(featureFlagsProvider, (_, _) => _onChanged());
    }
    return widget.child;
  }
}
