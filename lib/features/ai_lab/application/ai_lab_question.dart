import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const aiLabQuestionsAsset = 'assets/ai_lab/chat_questions_40.json';
const aiLabSeedExpectationsAsset = 'assets/ai_lab/seed_expectations.json';

/// One benchmark question from `chat_questions_40.json`.
@immutable
class AiLabQuestion {
  const AiLabQuestion({
    required this.id,
    required this.group,
    required this.text,
    required this.expectedRouteB1,
    this.intent,
    this.expectedKeys = const [],
    this.mustNotLocal = false,
    this.manualReview = false,
    this.knownRouterGap = false,
    this.expectedBehavior,
    this.note,
  });

  factory AiLabQuestion.fromJson(Map<String, Object?> json) => AiLabQuestion(
    id: json['id']! as String,
    group: json['group']! as String,
    text: json['text']! as String,
    expectedRouteB1: (json['expected_route_b1'] as String?) ?? '',
    intent: json['intent'] as String?,
    expectedKeys: [
      for (final key in (json['expected_keys'] as List?) ?? const [])
        key as String,
    ],
    mustNotLocal: json['must_not_local'] == true,
    manualReview: json['manual_review'] == true,
    knownRouterGap: json['known_router_gap'] == true,
    expectedBehavior: json['expected_behavior'] as String?,
    note: json['note'] as String?,
  );

  final String id;
  final String group;
  final String text;
  final String expectedRouteB1;
  final String? intent;

  /// Keys of `seed_expectations.json` whose strings the answer must contain.
  final List<String> expectedKeys;
  final bool mustNotLocal;
  final bool manualReview;
  final bool knownRouterGap;
  final String? expectedBehavior;
  final String? note;
}

Future<List<AiLabQuestion>> loadAiLabQuestions(
  AssetBundle bundle, {
  String path = aiLabQuestionsAsset,
}) async {
  final decoded = jsonDecode(await bundle.loadString(path));
  final raw = (decoded as Map<String, Object?>)['questions']! as List;
  return [
    for (final item in raw)
      AiLabQuestion.fromJson((item as Map).cast<String, Object?>()),
  ];
}

Future<Map<String, String>> loadSeedExpectations(
  AssetBundle bundle, {
  String path = aiLabSeedExpectationsAsset,
}) async {
  final decoded = jsonDecode(await bundle.loadString(path)) as Map;
  return {
    for (final entry in decoded.entries) '${entry.key}': '${entry.value}',
  };
}
