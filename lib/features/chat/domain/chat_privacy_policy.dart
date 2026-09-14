import 'chat_models.dart';

abstract final class ChatPrivacyPolicy {
  static const _publicFactKeys = {
    'period',
    'invoice_count',
    'total_minor_vnd',
    'previous_total_minor_vnd',
    'budget_count',
    'budget_limit_minor_vnd',
    'forecast_total_minor_vnd',
    'recurring_count',
    'anomaly_count',
    'external_exchange_rate',
    'external_exchange_updated_at',
  };

  static List<ChatFact> factsForExternal(Iterable<ChatFact> facts) {
    return facts
        .where((fact) => _publicFactKeys.contains(fact.key))
        .map((fact) => ChatFact(fact.key, _clean(fact.value, 500)))
        .take(20)
        .toList(growable: false);
  }

  static List<ChatMessage> historyForExternal(Iterable<ChatMessage> history) {
    return history
        .where((message) => message.role == ChatMessageRole.user)
        .toList(growable: false)
        .reversed
        .take(4)
        .toList()
        .reversed
        .map(
          (message) => ChatMessage(
            id: '',
            role: message.role,
            text: redactPersonalData(message.text),
            createdAt: message.createdAt,
          ),
        )
        .toList(growable: false);
  }

  static String redactPersonalData(String value) {
    return value
        .replaceAll(RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'), '[email đã ẩn]')
        .replaceAll(
          RegExp(r'(?<!\d)(?:\+?84|0)\d{8,10}(?!\d)'),
          '[số điện thoại đã ẩn]',
        )
        .replaceAll(RegExp(r'(?<!\d)\d{10,14}(?!\d)'), '[mã số đã ẩn]');
  }

  static String _clean(String value, int maxLength) {
    final singleLine = value.replaceAll(RegExp(r'[\u0000-\u001F]'), ' ').trim();
    return singleLine.length <= maxLength
        ? singleLine
        : '${singleLine.substring(0, maxLength)}…';
  }
}
