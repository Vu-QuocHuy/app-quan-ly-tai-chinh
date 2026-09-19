import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/chat_models.dart';

class ChatHistoryStore {
  const ChatHistoryStore({this.maxMessages = 100, this.scope});

  static const storageKey = 'chat.history.v1';
  final int maxMessages;
  final String? scope;

  String get _storageKey =>
      scope == null ? storageKey : '$storageKey.${scope!.trim()}';

  Future<List<ChatMessage>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => ChatMessage.fromJson(Map<String, Object?>.from(item)))
          .where((message) => message.text.trim().isNotEmpty)
          .take(maxMessages)
          .toList(growable: false);
    } on Object {
      return const [];
    }
  }

  Future<void> save(Iterable<ChatMessage> messages) async {
    final items = messages.toList(growable: false);
    final bounded = items.length <= maxMessages
        ? items
        : items.sublist(items.length - maxMessages);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(bounded.map((message) => message.toJson()).toList()),
    );
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
  }

  Future<void> clearAll({bool includeLegacy = false}) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
    if (includeLegacy && scope != null) await preferences.remove(storageKey);
  }
}
