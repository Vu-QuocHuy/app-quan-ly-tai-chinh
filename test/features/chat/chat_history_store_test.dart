import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/chat/data/chat_history_store.dart';
import 'package:hoadon_insight/features/chat/domain/chat_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists bounded chat history and citations', () async {
    final store = const ChatHistoryStore(maxMessages: 2);
    final first = ChatMessage(
      id: '1',
      role: ChatMessageRole.user,
      text: 'Tổng chi?',
      createdAt: DateTime(2026, 8, 30),
    );
    final second = ChatMessage(
      id: '2',
      role: ChatMessageRole.assistant,
      text: '100.000 ₫',
      createdAt: DateTime(2026, 8, 30),
      citations: const [
        ChatCitation(label: 'Local', sourceType: 'local', sourceId: '2026-08'),
      ],
    );
    final third = ChatMessage(
      id: '3',
      role: ChatMessageRole.user,
      text: 'Ngân sách?',
      createdAt: DateTime(2026, 8, 30),
    );

    await store.save([first, second, third]);
    final loaded = await store.load();

    expect(loaded.map((message) => message.id), ['2', '3']);
    expect(loaded.first.citations.single.sourceId, '2026-08');
  });
}
