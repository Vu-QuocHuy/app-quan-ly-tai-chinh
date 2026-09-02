import 'package:supabase_flutter/supabase_flutter.dart';

import '../errors/app_exception.dart';

/// Small adapter around Supabase Edge Functions.
///
/// Keeping this boundary in the app makes the AI clients independent from
/// provider details and keeps the Gemini key on the server-side function.
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
  }) async {
    if (!isConfigured) {
      throw const NetworkException(
        'Hãy đăng nhập Supabase để sử dụng tính năng AI online.',
      );
    }
    try {
      final response = await _client.functions.invoke(functionName, body: body);
      final data = response.data;
      if (data is! Map) {
        throw const ExtractionException('Edge Function trả về dữ liệu rỗng.');
      }
      return Map<String, dynamic>.from(data);
    } on AppException {
      rethrow;
    } on Object catch (error) {
      throw NetworkException(errorMessage, cause: error);
    }
  }
}
