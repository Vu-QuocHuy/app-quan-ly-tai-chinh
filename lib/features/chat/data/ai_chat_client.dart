import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/supabase_function_client.dart';
import '../domain/chat_models.dart';

class AiChatClient {
  AiChatClient({
    SupabaseClient? supabaseClient,
    Uuid? uuid,
    this.enabled = true,
    this.locale = 'vi-VN',
  }) : _functions = supabaseClient == null
           ? null
           : SupabaseFunctionClient(client: supabaseClient),
       _uuid = uuid ?? const Uuid();

  final SupabaseFunctionClient? _functions;
  final Uuid _uuid;
  final bool enabled;
  final String locale;

  bool get isConfigured => enabled && _functions?.isConfigured == true;

  Future<ChatReply> answer(
    String question, {
    required List<ChatFact> facts,
    bool allowToolCalls = false,
  }) async {
    if (!isConfigured) {
      throw const NetworkException(
        'Chatbot AI chưa được cấu hình hoặc bạn chưa đăng nhập.',
      );
    }
    final data = await _functions!.invoke({
      'action': 'chat',
      'requestId': _uuid.v4(),
      'locale': locale,
      'question': question,
      'facts': facts
          .map((fact) => {'key': fact.key, 'value': fact.value})
          .toList(),
      'allowToolCalls': allowToolCalls,
    }, errorMessage: 'Không thể kết nối chatbot AI lúc này.');
    final answer = data['answer'];
    if (answer is! String || answer.trim().isEmpty) {
      throw const FormatException(
        'Chatbot AI trả về câu trả lời không hợp lệ.',
      );
    }
    final rawCitations = data['citations'];
    final rawToolCall = data['toolCall'];
    if (rawToolCall != null && rawToolCall is! Map) {
      throw const FormatException('Chatbot AI trả về tool call không hợp lệ.');
    }
    final toolCall = rawToolCall is Map
        ? ChatToolCall(
            name: rawToolCall['name'] as String,
            period: rawToolCall['period'] as String,
          )
        : null;
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
      toolCall: toolCall,
    );
  }
}
