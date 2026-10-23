import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/network/supabase_function_client.dart';
import '../domain/assistant_command.dart';
import '../../invoices/domain/invoice_models.dart';

class AssistantCommandClient {
  const AssistantCommandClient({
    this.functions,
    this.locale = 'vi-VN',
    this.enabled = true,
  });
  final SupabaseFunctionClient? functions;
  final String locale;
  final bool enabled;
  bool get isConfigured => enabled && functions?.isConfigured == true;

  Future<AssistantCommand> interpret(
    String text, {
    required List<CategoryEntity> categories,
    AssistantCommand? pending,
    AssistantCommand? last,
  }) async {
    if (!isConfigured) throw StateError('AI unavailable');
    final result = await functions!.invoke({
      'action': 'assistant_command',
      'requestId': const Uuid().v4(),
      'locale': locale,
      'text': text,
      'today': AssistantCommand.dateKey(DateTime.now()),
      'categories': categories
          .map((c) => {'id': c.id, 'name': c.name, 'kind': c.kind.name})
          .toList(),
      'pending': pending?.toJson(),
      'last': last?.toJson(),
    }, errorMessage: 'FinmiAI unavailable');
    final command = result['command'];
    if (command is! Map) {
      throw const FormatException('Invalid assistant response');
    }
    return AssistantCommand.fromJson(Map<String, dynamic>.from(command));
  }
}

final assistantCommandClientProvider = Provider<AssistantCommandClient>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const AssistantCommandClient(enabled: false);
  final chat = ref.watch(aiChatClientProvider);
  return AssistantCommandClient(
    functions: SupabaseFunctionClient(client: client),
    enabled: chat.enabled,
    locale: ref.watch(appLocaleProvider).languageCode == 'en'
        ? 'en-US'
        : 'vi-VN',
  );
});
