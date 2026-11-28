import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai_lab_config.dart';
import '../application/ai_lab_actions.dart';
import 'ai_lab_bridge.dart';

/// Wraps [child] and, only when the AI Lab is enabled, lets the demo controller
/// page drive [AiLabActions] through `window.postMessage`.
class AiLabBridgeHost extends ConsumerStatefulWidget {
  const AiLabBridgeHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AiLabBridgeHost> createState() => _AiLabBridgeHostState();
}

class _AiLabBridgeHostState extends ConsumerState<AiLabBridgeHost> {
  void Function()? _stop;

  @override
  void initState() {
    super.initState();
    if (!AiLabConfig.enabled) return;
    try {
      _stop = startAiLabBridge(_onMessage);
    } catch (_) {
      _stop = null;
    }
  }

  void _onMessage(Object? data, String origin) {
    try {
      final command = parseAiLabMessage(data, origin);
      if (command == null || !mounted) return;
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
