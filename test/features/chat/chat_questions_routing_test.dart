import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/chat/domain/chat_routing_rules.dart';

/// Keeps `tool/benchmark/chat_questions_40.json` in step with TV2's router.
///
/// `local`   = `localIntent` answers it on device (0 LLM calls);
/// `cloud`   = read-only question, goes straight to `chat` (assistant_command
///             is skipped);
/// `command` = may change data or is unclear, takes the `assistant_command` path.
///
/// If a rule change makes one of these fail, decide whether the new route is
/// intended and then update the JSON (and re-run the benchmark for that
/// question). Q34 records a known gap: "thu nhập" contains the write marker
/// "nhập", so it never takes the local route.
String _route(String question) {
  if (ChatRoutingRules.localIntent(question) != null) return 'local';
  return ChatRoutingRules.isReadOnlyQuestion(question) ? 'cloud' : 'command';
}

void main() {
  final data =
      jsonDecode(
            File('tool/benchmark/chat_questions_40.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final questions = (data['questions'] as List).cast<Map<String, dynamic>>();

  test('the benchmark has 40 questions', () {
    expect(questions, hasLength(40));
  });

  for (final question in questions) {
    final id = question['id'] as String;
    final text = question['text'] as String;
    test('$id routes as documented: $text', () {
      expect(_route(text), question['expected_route_b1']);
      final intent = question['intent'];
      if (intent != null) {
        expect(ChatRoutingRules.localIntent(text)?.name, intent);
      }
    });
  }

  test('no write command is ever answered locally', () {
    for (final question in questions.where(
      (item) => item['must_not_local'] == true,
    )) {
      expect(
        ChatRoutingRules.localIntent(question['text'] as String),
        isNull,
        reason: '${question['id']} is a write command',
      );
    }
  });

  test('known gap Q34: "thu nhập" is treated as a write marker', () {
    final gap = questions.firstWhere((item) => item['id'] == 'Q34');
    expect(gap['known_router_gap'], isTrue);
    expect(ChatRoutingRules.localIntent(gap['text'] as String), isNull);
    // The same question without the word "nhập" is answered locally.
    expect(
      ChatRoutingRules.localIntent('Tổng thu tháng này là bao nhiêu?'),
      LocalChatIntent.incomeTotal,
    );
  });
}
