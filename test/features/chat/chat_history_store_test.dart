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

  test('keeps histories isolated by account scope', () async {
    final userOne = const ChatHistoryStore(scope: 'user-1');
    final userTwo = const ChatHistoryStore(scope: 'user-2');
    final message = ChatMessage(
      id: 'private',
      role: ChatMessageRole.user,
      text: 'Dữ liệu riêng tư',
      createdAt: DateTime(2026, 8, 30),
    );

    await userOne.save([message]);

    expect(await userTwo.load(), isEmpty);
    expect((await userOne.load()).single.id, 'private');
  });

  test(
    'clearAll removes scoped history without touching legacy or another account',
    () async {
      const legacy = ChatHistoryStore();
      const userOne = ChatHistoryStore(scope: 'user-1');
      const userTwo = ChatHistoryStore(scope: 'user-2');
      final message = ChatMessage(
        id: 'private',
        role: ChatMessageRole.user,
        text: 'Dữ liệu riêng tư',
        createdAt: DateTime(2026, 8, 30),
      );

      await legacy.save([message]);
      await userOne.save([message]);
      await userTwo.save([message]);
      await userOne.clearAll();

      expect((await legacy.load()).single.id, 'private');
      expect(await userOne.load(), isEmpty);
      expect((await userTwo.load()).single.id, 'private');

      await userOne.clearAll(includeLegacy: true);
      expect(await legacy.load(), isEmpty);
    },
  );
}
