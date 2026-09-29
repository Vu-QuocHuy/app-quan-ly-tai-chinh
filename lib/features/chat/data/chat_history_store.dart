import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/chat_models.dart';

class ChatHistoryStore {
  const ChatHistoryStore({this.maxMessages = 100, this.scope, this.client});

  static const storageKey = 'chat.history.v1';
  final int maxMessages;
  final String? scope;
  final SupabaseClient? client;

  bool get canSyncCloud =>
      client?.auth.currentSession != null && client?.auth.currentUser != null;

  String get _storageKey =>
      scope == null ? storageKey : '$storageKey.${scope!.trim()}';

  Future<List<ChatMessage>> load() async {
    if (!canSyncCloud) return loadLocal();
    final conversationId = await _ensureConversation();
    final rows = await client!
        .from('chat_messages')
        .select('id, role, content, citations, created_at')
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: false)
        .limit(maxMessages);
    final messages = rows
        .whereType<Map<String, dynamic>>()
        .map(_fromCloud)
        .where((message) => message.text.trim().isNotEmpty)
        .toList(growable: true);
    return messages.reversed.toList(growable: false);
  }

  Future<List<ChatMessage>> loadLocal() async {
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
    await _saveLocal(messages);
  }

  /// Adds only this new message to cloud. Existing device history is never
  /// bulk-uploaded when an account signs in.
  Future<bool> append(ChatMessage message) async {
    if (message.id == 'welcome' || message.text.trim().isEmpty) return true;
    final local = await loadLocal();
    final withoutDuplicate = local.where((item) => item.id != message.id);
    await _saveLocal([...withoutDuplicate, message]);
    if (!canSyncCloud) return false;
    try {
      final conversationId = await _ensureConversation();
      await client!
          .from('chat_messages')
          .upsert(
            {
              'user_id': client!.auth.currentUser!.id,
              'id': message.id,
              'conversation_id': conversationId,
              'role': message.role.name,
              'content': message.text,
              'citations': message.citations
                  .map((citation) => citation.toJson())
                  .toList(growable: false),
              'created_at': message.createdAt.toUtc().toIso8601String(),
            },
            onConflict: 'user_id,id',
            ignoreDuplicates: true,
          );
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _saveLocal(Iterable<ChatMessage> messages) async {
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
    if (!canSyncCloud) return;
    final conversationId = await _ensureConversation();
    await client!
        .from('chat_messages')
        .delete()
        .eq('conversation_id', conversationId);
  }

  Future<void> clearAll({bool includeLegacy = false}) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
    if (includeLegacy && scope != null) await preferences.remove(storageKey);
  }

  Future<String> _ensureConversation() async {
    final activeClient = client;
    final userId = activeClient?.auth.currentUser?.id;
    if (activeClient == null || userId == null) {
      throw StateError('Cloud chat requires an authenticated account.');
    }
    final row = await activeClient
        .from('chat_conversations')
        .upsert({'user_id': userId}, onConflict: 'user_id')
        .select('id')
        .single();
    return row['id'] as String;
  }

  ChatMessage _fromCloud(Map<String, dynamic> row) {
    final rawCitations = row['citations'];
    return ChatMessage(
      id: row['id'] as String? ?? '',
      role: ChatMessageRole.values.firstWhere(
        (role) => role.name == row['role'],
        orElse: () => ChatMessageRole.assistant,
      ),
      text: row['content'] as String? ?? '',
      createdAt:
          DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
      citations: rawCitations is List
          ? rawCitations
                .whereType<Map>()
                .map(
                  (item) =>
                      ChatCitation.fromJson(Map<String, Object?>.from(item)),
                )
                .toList(growable: false)
          : const [],
    );
  }
}
