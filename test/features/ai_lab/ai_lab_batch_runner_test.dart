import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/ai_lab/application/ai_lab_batch_runner.dart';
import 'package:hoadon_insight/features/ai_lab/application/ai_lab_chat_driver.dart';
import 'package:hoadon_insight/features/ai_lab/application/ai_lab_question.dart';

class _FakeDriver implements AiLabChatDriver {
  _FakeDriver(this.handler);

  final Future<AiLabChatOutcome> Function(String question) handler;
  final asked = <String>[];
  var concurrent = 0;
  var maxConcurrent = 0;

  @override
  Future<AiLabChatOutcome> ask(String question) async {
    asked.add(question);
    concurrent++;
    if (concurrent > maxConcurrent) maxConcurrent = concurrent;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      return await handler(question);
    } finally {
      concurrent--;
    }
  }
}

AiLabQuestion _q(
  String id,
  String group,
  String text, {
  List<String> keys = const [],
}) => AiLabQuestion(
  id: id,
  group: group,
  text: text,
  expectedRouteB1: 'local',
  expectedKeys: keys,
);

AiLabBatchRunner _runner(
  AiLabChatDriver driver, {
  Map<String, String> seeds = const {},
}) => AiLabBatchRunner(
  driver: driver,
  seedExpectations: seeds,
  flagProfile: 'b1',
  pause: Duration.zero,
);

AiLabChatOutcome _outcome(
  String route, {
  int llm = 0,
  int cloud = 0,
  int ms = 10,
  String? answer,
}) => AiLabChatOutcome(
  route: route,
  llmCalls: llm,
  cloudCalls: cloud,
  durationMs: ms,
  answerText: answer,
);

void main() {
  test('chạy tuần tự, đúng thứ tự, điền đủ cột', () async {
    final driver = _FakeDriver(
      (q) async => _outcome('cloud', llm: 1, cloud: 1, ms: 2100, answer: 'x'),
    );
    final rows = await _runner(driver)
        .run(questions: [_q('Q1', 'lookup', 'a'), _q('Q2', 'reasoning', 'b')])
        .toList();

    expect(driver.asked, ['a', 'b']);
    expect(driver.maxConcurrent, 1);
    expect(rows, hasLength(2));
    expect(rows[0].questionId, 'Q1');
    expect(rows[0].group, 'lookup');
    expect(rows[0].flagProfile, 'b1');
    expect(rows[0].run, 1);
    expect(rows[0].route, 'cloud');
    expect(rows[0].llmCalls, 1);
    expect(rows[0].cloudCalls, 1);
    expect(rows[0].durationMs, 2100);
    expect(rows[0].containsExpected, '');
    expect(rows[0].misroutedWrite, isFalse);
  });

  test('repeats=3 chạy 3 vòng, run đánh số 1..3', () async {
    final driver = _FakeDriver((q) async => _outcome('local'));
    final rows = await _runner(driver)
        .run(
          questions: [_q('Q1', 'lookup', 'a'), _q('Q2', 'lookup', 'b')],
          repeats: 3,
        )
        .toList();

    expect(rows, hasLength(6));
    expect(rows.map((r) => r.run).toSet(), {1, 2, 3});
    expect(driver.asked, ['a', 'b', 'a', 'b', 'a', 'b']);
  });

  test('misrouted_write chỉ true khi nhóm write đi route local', () async {
    final driver = _FakeDriver(
      (q) async => _outcome(q == 'w-local' ? 'local' : 'command'),
    );
    final rows = await _runner(driver)
        .run(
          questions: [
            _q('Q21', 'write', 'w-local'),
            _q('Q22', 'write', 'w-cmd'),
            _q('Q01', 'lookup', 'w-local'),
          ],
        )
        .toList();

    expect(rows.map((r) => r.misroutedWrite), [true, false, false]);
  });

  test(
    'contains_expected: khớp, lệch, NBSP, MANUAL và không có khóa',
    () async {
      final seeds = {
        'total': '10.545.000',
        'prev': '9.315.000',
        'manual': 'MANUAL',
      };
      final answers = <String, String>{
        'ok': 'Bạn chi 10.545.000 ₫ tháng này',
        'nbsp': 'Bạn chi 10.545.000 ₫',
        'both': '10.545.000 so với 9.315.000',
        'onlyOne': '10.545.000 thôi',
        'wrong': 'Bạn chi 1.000 ₫',
      };
      final driver = _FakeDriver(
        (q) async => _outcome('local', answer: answers[q] ?? 'bất kỳ'),
      );
      final rows = await _runner(driver, seeds: seeds)
          .run(
            questions: [
              _q('A', 'lookup', 'ok', keys: ['total']),
              _q('B', 'lookup', 'nbsp', keys: ['total']),
              _q('C', 'lookup', 'both', keys: ['total', 'prev']),
              _q('D', 'lookup', 'onlyOne', keys: ['total', 'prev']),
              _q('E', 'lookup', 'wrong', keys: ['total']),
              _q('F', 'lookup', 'ok', keys: ['manual']),
              _q('G', 'lookup', 'ok'),
            ],
          )
          .toList();

      expect(rows.map((r) => r.containsExpected), [
        'true',
        'true',
        'true',
        'false',
        'false',
        '',
        '',
      ]);
    },
  );

  test('NBSP/NNBSP trong kỳ vọng cũng được đưa về dấu cách thường', () async {
    final driver = _FakeDriver(
      (q) async => _outcome('local', answer: 'Còn 12.000.000 ₫'),
    );
    final rows = await _runner(driver, seeds: {'k': '12.000.000 ₫'})
        .run(
          questions: [
            _q('A', 'lookup', 'x', keys: ['k']),
          ],
        )
        .toList();

    expect(rows.single.containsExpected, 'true');
  });

  test('không có câu trả lời (null) -> contains_expected=false', () async {
    final driver = _FakeDriver((q) async => _outcome('timeout', ms: 60000));
    final rows = await _runner(driver, seeds: {'k': '1'})
        .run(
          questions: [
            _q('A', 'lookup', 'x', keys: ['k']),
          ],
        )
        .toList();

    expect(rows.single.route, 'timeout');
    expect(rows.single.containsExpected, 'false');
  });

  test('câu hỏi ném lỗi -> route error, batch vẫn chạy tiếp', () async {
    final driver = _FakeDriver((q) async {
      if (q == 'boom') throw StateError('x');
      return _outcome('local');
    });
    final rows = await _runner(driver)
        .run(
          questions: [_q('A', 'lookup', 'boom'), _q('B', 'lookup', 'fine')],
        )
        .toList();

    expect(rows.map((r) => r.route), ['error', 'local']);
    expect(rows.first.llmCalls, 0);
    expect(rows.first.containsExpected, '');
  });

  test('huỷ subscription dừng batch', () async {
    final driver = _FakeDriver((q) async => _outcome('local'));
    final stream = _runner(driver).run(
      questions: [for (var i = 0; i < 10; i++) _q('Q$i', 'lookup', 'q$i')],
    );
    final first = await stream.first;

    expect(first.questionId, 'Q0');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(driver.asked.length, lessThan(10));
  });

  group('aiLabBatchCsv', () {
    test('header đúng thứ tự cột của summarize_chat.py', () {
      expect(
        aiLabBatchCsv(const []).trim(),
        'question_id,group,flag_profile,run,route,llm_calls,cloud_calls,'
        'duration_ms,contains_expected,misrouted_write',
      );
      expect(aiLabBatchCsvColumns, [
        'question_id',
        'group',
        'flag_profile',
        'run',
        'route',
        'llm_calls',
        'cloud_calls',
        'duration_ms',
        'contains_expected',
        'misrouted_write',
      ]);
    });

    test('một dòng dữ liệu và escape dấu phẩy, nháy kép', () {
      final csv = aiLabBatchCsv(const [
        AiLabBatchRow(
          questionId: 'Q01',
          group: 'lookup',
          flagProfile: 'only:ai.chat.local_router,"x"',
          run: 2,
          route: 'local',
          llmCalls: 0,
          cloudCalls: 0,
          durationMs: 41,
          containsExpected: 'true',
          misroutedWrite: false,
        ),
        AiLabBatchRow(
          questionId: 'Q21',
          group: 'write',
          flagProfile: 'b1',
          run: 1,
          route: 'command',
          llmCalls: 1,
          cloudCalls: 1,
          durationMs: 900,
          containsExpected: '',
          misroutedWrite: false,
        ),
      ]);
      final lines = csv.trim().split('\n');

      expect(lines, hasLength(3));
      expect(
        lines[1],
        'Q01,lookup,"only:ai.chat.local_router,""x""",2,local,0,0,41,true,false',
      );
      expect(lines[2], 'Q21,write,b1,1,command,1,1,900,,false');
    });
  });

  group('aiLabBatchSummary', () {
    test('số lượt, TB lượt gọi LLM, tỉ lệ cục bộ', () {
      const base = AiLabBatchRow(
        questionId: 'Q',
        group: 'lookup',
        flagProfile: 'b1',
        run: 1,
        route: 'local',
        llmCalls: 0,
        cloudCalls: 0,
        durationMs: 10,
        containsExpected: '',
        misroutedWrite: false,
      );
      final summary = aiLabBatchSummary([
        base,
        base,
        base.copyWith(route: 'cloud', llmCalls: 1, cloudCalls: 1),
        base.copyWith(route: 'command', llmCalls: 2, cloudCalls: 2),
      ]);

      expect(summary.turns, 4);
      expect(summary.averageLlmCalls, 0.75);
      expect(summary.localShare, 0.5);
    });

    test('rỗng -> 0', () {
      final summary = aiLabBatchSummary(const []);
      expect(summary.turns, 0);
      expect(summary.averageLlmCalls, 0);
      expect(summary.localShare, 0);
    });
  });
}
