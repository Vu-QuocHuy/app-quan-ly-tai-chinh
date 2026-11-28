import '../config/ai_flag_profile.dart';

/// Faults accepted by the server's `x-finmi-fault` header.
const aiDebugFaults = {'429', '500', 'timeout'};

/// Debug-only headers for `ai-api` (honoured by the server only when
/// `AI_ALLOW_DEBUG_HEADERS=true`): per-request flag overrides and fault
/// injection. Always empty for release builds ([debug] is `false`).
Map<String, String> aiDebugHeaders({
  required AiFlagProfile profile,
  required bool debug,
  String? fault,
}) {
  if (!debug) return const {};
  final flags = profile.headerValue;
  return {
    'x-finmi-flags': ?flags,
    if (fault != null && aiDebugFaults.contains(fault)) 'x-finmi-fault': fault,
  };
}
