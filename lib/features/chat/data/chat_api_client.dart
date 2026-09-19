import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/supabase_function_client.dart';
import '../domain/chat_models.dart';
import '../domain/chat_privacy_policy.dart';

class ChatApiClient {
  ChatApiClient({SupabaseClient? supabaseClient, Uuid? uuid})
    : _supabaseFunctions = supabaseClient == null
          ? null
          : SupabaseFunctionClient(client: supabaseClient),
      _uuid = uuid ?? const Uuid();

  final SupabaseFunctionClient? _supabaseFunctions;
  final Uuid _uuid;

  bool get isConfigured => _supabaseFunctions?.isConfigured == true;

  Future<ChatReply> ask({
    required String question,
    required Iterable<ChatMessage> history,
    required Iterable<ChatFact> facts,
    bool allowExternalData = true,
  }) async {
    if (!isConfigured) {
      throw const NetworkException('Chatbot backend chưa được cấu hình.');
    }
    final body = {
      'action': 'chat',
      'requestId': _uuid.v4(),
      'locale': 'vi-VN',
      'question': ChatPrivacyPolicy.redactPersonalData(question.trim()),
      'facts': ChatPrivacyPolicy.factsForExternal(
        facts,
      ).map((fact) => fact.toJson()).toList(growable: false),
      'history': ChatPrivacyPolicy.historyForExternal(history)
          .map((message) => {'role': message.role.name, 'text': message.text})
          .toList(growable: false),
      'allowExternalData': allowExternalData,
    };
    final data = await _supabaseFunctions!.invoke(
      body,
      errorMessage:
          'Không thể kết nối chatbot. Bạn vẫn có thể hỏi các dữ liệu đã lưu offline.',
    );
    return _fromJson(data);
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
