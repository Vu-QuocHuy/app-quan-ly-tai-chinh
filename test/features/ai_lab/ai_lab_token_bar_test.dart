import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/monitoring/ai_lab_store.dart';
import 'package:hoadon_insight/features/ai_lab/presentation/ai_lab_counters.dart';
import 'package:hoadon_insight/features/ai_lab/presentation/ai_lab_token_bar.dart';

Widget _host(Widget child, {double width = 400}) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: width, child: child)),
  ),
);

double _w(WidgetTester tester, String key) =>
    tester.getSize(find.byKey(ValueKey(key))).width;

void main() {
  group('AiLabTokenBar', () {
    testWidgets('3 phần tỉ lệ theo token', (tester) async {
      await tester.pumpWidget(
        _host(
          const AiLabTokenBar(
            call: AiLabCall(
              action: 'extract',
              durationMs: 1,
              inputTokens: 200,
              thinkingTokens: 100,
              outputTokens: 100,
            ),
          ),
        ),
      );
      expect(_w(tester, 'ai-lab-token-input'), closeTo(200, 0.01));
      expect(_w(tester, 'ai-lab-token-thinking'), closeTo(100, 0.01));
      expect(_w(tester, 'ai-lab-token-output'), closeTo(100, 0.01));
      expect(find.text('đầu vào 200'), findsOneWidget);
      expect(find.text('suy luận 100'), findsOneWidget);
      expect(find.text('đầu ra 100'), findsOneWidget);
    });

    testWidgets(
      'thinkingTokens=0 -> phần suy luận rộng 0 nhưng chú thích "suy luận 0"',
      (tester) async {
        await tester.pumpWidget(
          _host(
            const AiLabTokenBar(
              call: AiLabCall(
                action: 'extract',
                durationMs: 1,
                inputTokens: 300,
                thinkingTokens: 0,
                outputTokens: 100,
              ),
            ),
          ),
        );
        expect(_w(tester, 'ai-lab-token-thinking'), 0);
        expect(_w(tester, 'ai-lab-token-input'), closeTo(300, 0.01));
        expect(find.text('suy luận 0'), findsOneWidget);
      },
    );

    testWidgets('call=null -> "—" không lỗi', (tester) async {
      await tester.pumpWidget(_host(const AiLabTokenBar()));
      expect(find.text('—'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mọi token null -> "—" không lỗi', (tester) async {
      await tester.pumpWidget(
        _host(
          const AiLabTokenBar(
            call: AiLabCall(action: 'extract_status', durationMs: 1),
          ),
        ),
      );
      expect(find.text('—'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('chỉ một phần có số -> phần thiếu hiện "—" và rộng 0', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const AiLabTokenBar(
            call: AiLabCall(action: 'extract', durationMs: 1, inputTokens: 50),
          ),
        ),
      );
      expect(_w(tester, 'ai-lab-token-input'), closeTo(400, 0.01));
      expect(_w(tester, 'ai-lab-token-output'), 0);
      expect(find.text('đầu ra —'), findsOneWidget);
    });
  });

  group('AiLabCounters', () {
    setUp(() => AiLabStore.instance.reset());
    tearDown(() => AiLabStore.instance.reset());

    testWidgets('hiện số lượt gọi, token và số lượt đã tiết kiệm', (
      tester,
    ) async {
      AiLabStore.instance
        ..recordCall(
          const AiLabCall(
            action: 'chat',
            durationMs: 1,
            llmCalls: 2,
            inputTokens: 700,
            outputTokens: 300,
          ),
        )
        ..recordTurn(
          const AiLabTurn(
            messageId: 'm1',
            route: AiLabRoute.local,
            llmCalls: 0,
            durationMs: 40,
          ),
        );
      await tester.pumpWidget(_host(const AiLabCounters()));
      expect(find.text('Lượt gọi LLM: 2'), findsOneWidget);
      expect(find.text('Token: 1.000'), findsOneWidget);
      expect(find.text('Đã tiết kiệm: 3 lượt'), findsOneWidget);
    });

    testWidgets('không có cost -> không có dòng chi phí', (tester) async {
      await tester.pumpWidget(_host(const AiLabCounters()));
      expect(find.byKey(const ValueKey('ai-lab-cost')), findsNothing);
      expect(find.textContaining('USD'), findsNothing);
    });

    testWidgets('có cost -> USD dấu phẩy, VND dấu chấm ngăn nghìn', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const AiLabCounters(
            cost: AiLabCostSummary(usd: 2.5, savedUsd: 1, vndPerUsd: 25000),
          ),
        ),
      );
      expect(find.text('Chi phí: 2,5000 USD · 62.500 ₫'), findsOneWidget);
      expect(find.text('Tiết kiệm: 1,0000 USD · 25.000 ₫'), findsOneWidget);
    });

    testWidgets('cập nhật khi store đổi', (tester) async {
      await tester.pumpWidget(_host(const AiLabCounters()));
      expect(find.text('Lượt gọi LLM: 0'), findsOneWidget);
      AiLabStore.instance.recordCall(
        const AiLabCall(action: 'chat', durationMs: 1, llmCalls: 1),
      );
      await tester.pump();
      expect(find.text('Lượt gọi LLM: 1'), findsOneWidget);
    });
  });

  group('formatVnd', () {
    test('dấu chấm ngăn nghìn', () {
      expect(formatVnd(0), '0');
      expect(formatVnd(999), '999');
      expect(formatVnd(1000), '1.000');
      expect(formatVnd(1234567), '1.234.567');
    });
  });
}
