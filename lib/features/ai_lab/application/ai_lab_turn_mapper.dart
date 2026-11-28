import '../../../core/monitoring/ai_lab_store.dart';
import '../../../core/monitoring/ai_telemetry.dart';

/// Builds the badge data of one chat turn from its `chat_turn` telemetry event
/// and the server signals seen during the turn.
///
/// Priority: `AI_DEGRADED` > server failover (shown with its provider) >
/// client fallback to the offline assistant > local > cloud.
AiLabTurn aiLabTurnFrom({
  required String messageId,
  required AiTelemetryEvent event,
  required AiLabTurnSignals signals,
}) {
  final AiLabRoute route;
  if (signals.degraded) {
    route = AiLabRoute.degraded;
  } else if (signals.failoverProvider != null || event.route == 'fallback') {
    route = AiLabRoute.fallback;
  } else if (event.route == 'local') {
    route = AiLabRoute.local;
  } else {
    route = AiLabRoute.cloud;
  }
  return AiLabTurn(
    messageId: messageId,
    route: route,
    llmCalls: event.llmCalls,
    durationMs: event.durationMs ?? 0,
    provider: signals.failoverProvider,
  );
}
