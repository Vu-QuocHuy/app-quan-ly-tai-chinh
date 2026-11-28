import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_exception.dart';

/// The structured `code` an Edge Function put in its error body
/// (for example `AI_DEGRADED` or `MODEL_RATE_LIMITED`), or `null`.
///
/// Looks through [NetworkException.cause], because `SupabaseFunctionClient`
/// wraps the original [FunctionException].
String? functionErrorCode(Object error) {
  if (error is NetworkException) {
    final cause = error.cause;
    return cause == null ? null : functionErrorCode(cause);
  }
  if (error is FunctionException) {
    final details = error.details;
    if (details is Map) {
      final code = details['code'];
      if (code is String) return code;
    }
  }
  return null;
}
