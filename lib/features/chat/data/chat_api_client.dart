import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/supabase_function_client.dart';
import '../domain/chat_models.dart';

class ChatApiClient {
  ChatApiClient({
    required String baseUrl,
    SupabaseClient? supabaseClient,
    Future<String?> Function()? appCheckTokenProvider,
    Dio? dio,
    Uuid? uuid,
  }) : _baseUrl = baseUrl,
       _supabaseFunctions = supabaseClient == null
           ? null
           : SupabaseFunctionClient(client: supabaseClient),
       _appCheckTokenProvider = appCheckTokenProvider,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 8),
               receiveTimeout: const Duration(seconds: 20),
             ),
           ),
       _uuid = uuid ?? const Uuid();

  final String _baseUrl;
  final SupabaseFunctionClient? _supabaseFunctions;
  final Future<String?> Function()? _appCheckTokenProvider;
  final Dio _dio;
  final Uuid _uuid;

  bool get isConfigured =>
      _supabaseFunctions?.isConfigured == true || _baseUrl.trim().isNotEmpty;

  Future<ChatReply> ask({
    required String question,
    required Iterable<ChatMessage> history,
    required Iterable<ChatFact> facts,
  }) async {
    if (!isConfigured) {
      throw const NetworkException('Chatbot backend chưa được cấu hình.');
    }
    try {
      final body = {
        'action': 'chat',
        'requestId': _uuid.v4(),
        'locale': 'vi-VN',
        'question': question.trim(),
        'facts': facts.map((fact) => fact.toJson()).toList(growable: false),
        'history': history
            .toList(growable: false)
            .reversed
            .take(8)
            .toList()
            .reversed
            .map((message) => {'role': message.role.name, 'text': message.text})
            .toList(growable: false),
      };
      final data = _supabaseFunctions != null
          ? await _supabaseFunctions.invoke(
              body,
              errorMessage:
                  'Không thể kết nối chatbot. Bạn vẫn có thể hỏi các dữ liệu đã lưu offline.',
            )
          : await _invokeLegacy(body);
      return _fromJson(data);
    } on DioException catch (error) {
      throw NetworkException(
        'Không thể kết nối chatbot. Bạn vẫn có thể hỏi các dữ liệu đã lưu offline.',
        cause: error,
      );
    }
  }

  Future<Map<String, dynamic>> _invokeLegacy(Map<String, Object?> body) async {
    final token = await _appCheckTokenProvider?.call();
    final response = await _dio.post<Map<String, dynamic>>(
      '$_baseUrl/v1/chat',
      data: body,
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          if (token != null && token.isNotEmpty) 'X-Firebase-AppCheck': token,
        },
      ),
    );
    return response.data ?? const {};
  }

  ChatReply _fromJson(Map<String, dynamic> json) {
    final answer = json['answer'];
    if (answer is! String || answer.trim().isEmpty) {
      throw const ExtractionException(
        'Chatbot trả về câu trả lời không hợp lệ.',
      );
    }
    final rawCitations = json['citations'];
    final citations = rawCitations is List
        ? rawCitations
              .whereType<Map>()
              .map(
                (item) =>
                    ChatCitation.fromJson(Map<String, Object?>.from(item)),
              )
              .toList(growable: false)
        : const <ChatCitation>[];
    return ChatReply(
      text: answer.trim(),
      citations: citations,
      usedExternalData: json['usedExternalData'] == true,
    );
  }
}
