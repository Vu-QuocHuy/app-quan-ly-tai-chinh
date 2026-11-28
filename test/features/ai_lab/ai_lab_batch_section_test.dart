import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/ai_lab/application/ai_lab_batch_providers.dart';
import 'package:hoadon_insight/features/ai_lab/application/ai_lab_chat_driver.dart';
import 'package:hoadon_insight/features/ai_lab/application/ai_lab_question.dart';
import 'package:hoadon_insight/features/ai_lab/presentation/ai_lab_batch_section.dart';

class _GateDriver implements AiLabChatDriver {
  _GateDriver({this.gated = false});

  final bool gated;
  final asked = <String>[];
  Completer<void>? gate;

  @override
  Future<AiLabChatOutcome> ask(String question) async {
    asked.add(question);
    if (gated) {
      gate = Completer<void>();
      await gate!.future;
    }
    final local = question.startsWith('l');
    return AiLabChatOutcome(
      route: local ? 'local' : 'cloud',
      llmCalls: local ? 0 : 1,
      cloudCalls: local ? 0 : 1,
      durationMs: 20,
      answerText: 'trả lời',
    );
  }
}

const _questions = [
  AiLabQuestion(
    id: 'Q1',
    group: 'lookup',
    text: 'l1',
    expectedRouteB1: 'local',
  ),
  AiLabQuestion(
    id: 'Q2',
    group: 'reasoning',
    text: 'c2',
    expectedRouteB1: 'cloud',
  ),
];

Widget _app(AiLabChatDriver driver) => ProviderScope(
  overrides: [
    aiLabChatDriverProvider.overrideWithValue(driver),
    aiLabQuestionsProvider.overrideWith((ref) async => _questions),
    aiLabSeedExpectationsProvider.overrideWith((ref) async => const {}),
    aiLabBatchPauseProvider.overrideWithValue(Duration.zero),
    aiLabFlagProfileProvider.overrideWithValue('b1'),
  ],
  child: const MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: AiLabBatchSection())),
  ),
);

Finder _runButton() => find.widgetWithText(FilledButton, 'Chạy');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hiện tiêu đề, gợi ý, tiến độ 0/2 và nút sao chép tắt', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_GateDriver()));
    await tester.pumpAndSettle();

    expect(find.text('Chạy 40 câu'), findsOneWidget);
    expect(find.text('Mở màn Chat trước khi chạy'), findsOneWidget);
    expect(find.text('0/2'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNull,
    );
  });

  testWidgets('chạy xong: tiến độ đủ, tóm tắt, nút sao chép bật', (
    tester,
  ) async {
    final driver = _GateDriver();
    await tester.pumpWidget(_app(driver));
    await tester.pumpAndSettle();

    await tester.tap(_runButton());
    await tester.pumpAndSettle();

    expect(driver.asked, ['l1', 'c2']);
    expect(find.text('2/2'), findsOneWidget);
    expect(find.textContaining('2 lượt'), findsOneWidget);
    expect(find.textContaining('50,0% cục bộ'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(_runButton()).onPressed,
      isNotNull,
    );
    expect(
      tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('đang chạy: nút Chạy tắt, tiến độ tăng dần', (tester) async {
    final driver = _GateDriver(gated: true);
    await tester.pumpWidget(_app(driver));
    await tester.pumpAndSettle();

    await tester.tap(_runButton());
    await tester.pump();
    await tester.pump();

    expect(tester.widget<FilledButton>(_runButton()).onPressed, isNull);
    expect(find.text('0/2'), findsOneWidget);

    driver.gate!.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('1/2'), findsOneWidget);
    expect(tester.widget<FilledButton>(_runButton()).onPressed, isNull);

    driver.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('2/2'), findsOneWidget);
    expect(tester.widget<FilledButton>(_runButton()).onPressed, isNotNull);
  });

  testWidgets('chọn 3 lần lặp: tổng = 2×3', (tester) async {
    final driver = _GateDriver();
    await tester.pumpWidget(_app(driver));
    await tester.pumpAndSettle();

    await tester.tap(find.text('3 lần'));
    await tester.pumpAndSettle();
    expect(find.text('0/6'), findsOneWidget);

    await tester.tap(_runButton());
    await tester.pumpAndSettle();

    expect(driver.asked, hasLength(6));
    expect(find.text('6/6'), findsOneWidget);
  });

  testWidgets('Sao chép CSV đặt CSV lên clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(_app(_GateDriver()));
    await tester.pumpAndSettle();
    await tester.tap(_runButton());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();

    final lines = copied!.trim().split('\n');
    expect(
      lines.first,
      'question_id,group,flag_profile,run,route,llm_calls,cloud_calls,'
      'duration_ms,contains_expected,misrouted_write',
    );
    expect(lines, hasLength(3));
    expect(lines[1], startsWith('Q1,lookup,b1,1,local,0,0,20,'));
    expect(lines[2], startsWith('Q2,reasoning,b1,1,cloud,1,1,20,'));
  });
}
