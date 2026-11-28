import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/ai_lab/application/ai_lab_question.dart';

class _MapBundle extends CachingAssetBundle {
  _MapBundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final value = files[key];
    if (value == null) throw FlutterError('missing $key');
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(value)));
  }
}

String _normalise(String text) => text.replaceAll('\r\n', '\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loadAiLabQuestions đọc các trường của một câu hỏi', () async {
    final bundle = _MapBundle({
      'assets/ai_lab/chat_questions_40.json': jsonEncode({
        'version': 1,
        'questions': [
          {
            'id': 'Q01',
            'group': 'lookup',
            'intent': 'expenseTotal',
            'text': 'Tháng này tôi chi bao nhiêu?',
            'expected_route_b1': 'local',
            'expected_keys': ['expense_total_current'],
          },
          {
            'id': 'Q21',
            'group': 'write',
            'text': 'Hôm nay ăn trưa hết 35k',
            'expected_route_b1': 'command',
            'must_not_local': true,
          },
          {
            'id': 'Q13',
            'group': 'reasoning',
            'text': 'Tại sao?',
            'expected_route_b1': 'cloud',
            'manual_review': true,
          },
        ],
      }),
    });

    final questions = await loadAiLabQuestions(bundle);

    expect(questions.map((q) => q.id), ['Q01', 'Q21', 'Q13']);
    expect(questions[0].group, 'lookup');
    expect(questions[0].expectedRouteB1, 'local');
    expect(questions[0].expectedKeys, ['expense_total_current']);
    expect(questions[0].mustNotLocal, isFalse);
    expect(questions[1].mustNotLocal, isTrue);
    expect(questions[1].expectedKeys, isEmpty);
    expect(questions[2].manualReview, isTrue);
  });

  test('loadSeedExpectations trả map khóa -> chuỗi', () async {
    final bundle = _MapBundle({
      'assets/ai_lab/seed_expectations.json': jsonEncode({
        'a': '10.545.000',
        'b': 'MANUAL',
      }),
    });

    expect(await loadSeedExpectations(bundle), {
      'a': '10.545.000',
      'b': 'MANUAL',
    });
  });

  test('asset thật: 40 câu, mọi expected_keys có trong seed', () async {
    final questions = await loadAiLabQuestions(rootBundle);
    final seeds = await loadSeedExpectations(rootBundle);

    expect(questions, hasLength(40));
    expect(
      questions.where((q) => q.group == 'write').every((q) => q.mustNotLocal),
      isTrue,
    );
    for (final question in questions) {
      for (final key in question.expectedKeys) {
        expect(seeds.containsKey(key), isTrue, reason: '${question.id}:$key');
      }
    }
  });

  test('asset chat_questions_40.json giống hệt bản trong tool/benchmark', () {
    expect(
      _normalise(
        File('assets/ai_lab/chat_questions_40.json').readAsStringSync(),
      ),
      _normalise(
        File('tool/benchmark/chat_questions_40.json').readAsStringSync(),
      ),
    );
  });

  test('asset seed_expectations.json giống hệt bản trong tool/demo', () {
    expect(
      _normalise(
        File('assets/ai_lab/seed_expectations.json').readAsStringSync(),
      ),
      _normalise(File('tool/demo/seed_expectations.json').readAsStringSync()),
    );
  });
}
