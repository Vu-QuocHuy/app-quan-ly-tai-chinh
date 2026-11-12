import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

import '../errors/app_exception.dart';
import '../monitoring/ai_telemetry.dart';

/// Small adapter around Supabase Edge Functions.
///
/// Keeping this boundary in the app makes the AI clients independent from
/// provider details and keeps provider keys on the server-side function.
class SupabaseFunctionClient {
  const SupabaseFunctionClient({
    required SupabaseClient client,
    this.functionName = 'ai-api',
  }) : _client = client;

  final SupabaseClient _client;
  final String functionName;

  bool get isConfigured => _client.auth.currentSession != null;

  Future<Map<String, dynamic>> invoke(
    Map<String, Object?> body, {
    required String errorMessage,
    Future<void>? abortSignal,
  }) async {
    if (!isConfigured) {
      throw const NetworkException(
        'Hãy đăng nhập Supabase để sử dụng tính năng AI online.',
      );
    }
    final action = body['action'];
    final stopwatch = Stopwatch()..start();
    var succeeded = false;
    try {
      final response = await _client.functions.invoke(
        functionName,
        body: body,
        abortSignal: abortSignal,
      );
      final data = response.data;
      if (data is! Map) {
        throw const ExtractionException('Edge Function trả về dữ liệu rỗng.');
      }
      succeeded = true;
      return Map<String, dynamic>.from(data);
    } on AppException {
      rethrow;
    } on http.RequestAbortedException {
      throw const RequestCancelledException();
    } on Object catch (error) {
      throw NetworkException(errorMessage, cause: error);
    } finally {
      stopwatch.stop();
      if (action is String && functionName == 'ai-api') {
        // N3: count every cloud AI call (M6/M7) without logging its content.
        AiTelemetry.instance.recordRemoteCall(
          action,
          duration: stopwatch.elapsed,
          succeeded: succeeded,
          payloadBytes: _approximatePayloadBytes(body),
        );
      }
    }
  }

  /// Cheap size estimate (string fields dominate: base64 images, audio).
  static int _approximatePayloadBytes(Map<String, Object?> body) {
    var total = 0;
    for (final value in body.values) {
      if (value is String) total += value.length;
    }
    return total;
  }
}
