import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/chat/domain/chat_models.dart';
import 'package:hoadon_insight/features/chat/domain/chat_privacy_policy.dart';

void main() {
  test('only sends aggregate facts and drops invoice-level data', () {
    final facts = ChatPrivacyPolicy.factsForExternal([
      const ChatFact('total_minor_vnd', '125000'),
      const ChatFact('period', 'Tháng 8/2026'),
      const ChatFact('search_results', 'invoice-1|Cửa hàng A|125000'),
      const ChatFact('category_totals', 'Ăn uống: 125000'),
    ]);

    expect(facts.map((fact) => fact.key), ['total_minor_vnd', 'period']);
  });

  test('redacts personal identifiers from external chat context', () {
    final redacted = ChatPrivacyPolicy.redactPersonalData(
      'Liên hệ test123@gmail.com hoặc 0912345678, mã 012345678901.',
    );

    expect(redacted, isNot(contains('test123@gmail.com')));
    expect(redacted, isNot(contains('0912345678')));
    expect(redacted, isNot(contains('012345678901')));
    expect(redacted, contains('[email đã ẩn]'));
    expect(redacted, contains('[số điện thoại đã ẩn]'));
    expect(redacted, contains('[mã số đã ẩn]'));
  });

  test('keeps only recent user history and removes assistant messages', () {
    final history = [
      for (var index = 0; index < 6; index++)
        ChatMessage(
          id: '$index',
          role: index.isEven ? ChatMessageRole.user : ChatMessageRole.assistant,
          text: 'Tin nhắn $index',
          createdAt: DateTime(2026, 1, index + 1),
        ),
    ];

    final result = ChatPrivacyPolicy.historyForExternal(history);

    expect(result, hasLength(3));
    expect(
      result.every((message) => message.role == ChatMessageRole.user),
      isTrue,
    );
    expect(result.map((message) => message.text), [
      'Tin nhắn 0',
      'Tin nhắn 2',
      'Tin nhắn 4',
    ]);
  });
}
