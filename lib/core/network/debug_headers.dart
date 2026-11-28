/// Faults accepted by the server's `x-finmi-fault` header.
const aiDebugFaults = {'429', '500', 'timeout'};

/// Debug-only headers for `ai-api` (honoured by the server only when
/// `AI_ALLOW_DEBUG_HEADERS=true`): per-request flag overrides and fault
/// injection. Always empty for release builds ([debug] is `false`).
///
/// [flagsHeader] is `AiFlagOverrides.instance.headerValue` (all 10 flags as
/// `key=1|0`), or `null` when the server flags apply.
Map<String, String> aiDebugHeaders({
  required String? flagsHeader,
  required bool debug,
  String? fault,
}) {
  if (!debug) return const {};
  return {
    'x-finmi-flags': ?flagsHeader,
    if (fault != null && aiDebugFaults.contains(fault)) 'x-finmi-fault': fault,
  };
}
