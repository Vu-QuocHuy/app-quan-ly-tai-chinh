import 'package:flutter/foundation.dart';

enum ChatMessageRole { user, assistant }

@immutable
class ChatCitation {
  const ChatCitation({
    required this.label,
    required this.sourceType,
    required this.sourceId,
    this.url,
    this.capturedAt,
  });

  final String label;
  final String sourceType;
  final String sourceId;
  final String? url;
  final DateTime? capturedAt;

  Map<String, Object?> toJson() => {
    'label': label,
    'sourceType': sourceType,
    'sourceId': sourceId,
    if (url != null) 'url': url,
    if (capturedAt != null) 'capturedAt': capturedAt!.toIso8601String(),
  };

  factory ChatCitation.fromJson(Map<String, Object?> json) {
    return ChatCitation(
      label: json['label'] as String? ?? 'Nguồn dữ liệu',
      sourceType: json['sourceType'] as String? ?? 'unknown',
      sourceId: json['sourceId'] as String? ?? '',
      url: json['url'] as String?,
      capturedAt: _parseDate(json['capturedAt']),
    );
  }
}

@immutable
class ChatFact {
  const ChatFact(this.key, this.value);

  final String key;
  final String value;

  Map<String, String> toJson() => {'key': key, 'value': value};
}

@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    this.citations = const [],
  });

  final String id;
  final ChatMessageRole role;
  final String text;
  final DateTime createdAt;
  final List<ChatCitation> citations;

  Map<String, Object?> toJson() => {
    'id': id,
    'role': role.name,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'citations': citations.map((citation) => citation.toJson()).toList(),
  };

  factory ChatMessage.fromJson(Map<String, Object?> json) {
    final rawCitations = json['citations'];
    return ChatMessage(
      id: json['id'] as String? ?? '',
      role: ChatMessageRole.values.firstWhere(
        (item) => item.name == json['role'],
        orElse: () => ChatMessageRole.assistant,
      ),
      text: json['text'] as String? ?? '',
      createdAt: _parseDate(json['createdAt']) ?? DateTime.now(),
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

@immutable
class ChatReply {
  const ChatReply({
    required this.text,
    this.citations = const [],
    this.facts = const [],
    this.usedExternalData = false,
  });

  final String text;
  final List<ChatCitation> citations;
  final List<ChatFact> facts;
  final bool usedExternalData;
}

DateTime? _parseDate(Object? value) {
  return value is String ? DateTime.tryParse(value) : null;
}
