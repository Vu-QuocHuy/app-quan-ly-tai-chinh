import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/monitoring/ai_lab_store.dart';
import 'package:hoadon_insight/features/ai_lab/presentation/ai_lab_badge.dart';

AiLabTurn _turn(
  AiLabRoute route, {
  int llmCalls = 0,
  int durationMs = 40,
  String? provider,
}) => AiLabTurn(
  messageId: 'm1',
  route: route,
  llmCalls: llmCalls,
  durationMs: durationMs,
  provider: provider,
);

void main() {
  group('aiLabBadgeText', () {
    test('local 0 lượt 40 ms', () {
      expect(
        aiLabBadgeText(_turn(AiLabRoute.local)),
        '⚡ TRÊN MÁY · 0 lượt · 40 ms',
      );
    });

    test('cloud 1 lượt 2100 ms -> "2,1 s"', () {
      expect(
        aiLabBadgeText(_turn(AiLabRoute.cloud, llmCalls: 1, durationMs: 2100)),
        '☁ ĐÁM MÂY · 1 lượt · 2,1 s',
      );
    });

    test('dưới 1000 ms giữ đơn vị ms, từ 1000 ms đổi sang giây', () {
      expect(
        aiLabBadgeText(_turn(AiLabRoute.local, durationMs: 999)),
        endsWith('999 ms'),
      );
      expect(
        aiLabBadgeText(_turn(AiLabRoute.local, durationMs: 1000)),
        endsWith('1,0 s'),
      );
    });

    test('failover provider gemini -> "↪ DỰ PHÒNG: Gemini"', () {
      expect(
        aiLabBadgeText(_turn(AiLabRoute.fallback, provider: 'gemini')),
        '↪ DỰ PHÒNG: Gemini',
      );
    });

    test('failover không rõ provider -> "↪ DỰ PHÒNG"', () {
      expect(aiLabBadgeText(_turn(AiLabRoute.fallback)), '↪ DỰ PHÒNG');
    });

    test('degraded -> "⚠ CỤC BỘ (AI_DEGRADED)"', () {
      expect(
        aiLabBadgeText(_turn(AiLabRoute.degraded)),
        '⚠ CỤC BỘ (AI_DEGRADED)',
      );
    });
  });

  group('AiLabBadge', () {
    setUp(() => AiLabStore.instance.reset());
    tearDown(() => AiLabStore.instance.reset());

    Widget host({required bool enabled}) => MaterialApp(
      home: Scaffold(body: AiLabBadge(messageId: 'm1', enabled: enabled)),
    );

    testWidgets('AiLab bật và có turn -> hiện huy hiệu', (tester) async {
      AiLabStore.instance.recordTurn(_turn(AiLabRoute.local));
      await tester.pumpWidget(host(enabled: true));
      expect(find.text('⚡ TRÊN MÁY · 0 lượt · 40 ms'), findsOneWidget);
    });

    testWidgets('AiLab tắt -> widget không vẽ gì', (tester) async {
      AiLabStore.instance.recordTurn(_turn(AiLabRoute.local));
      await tester.pumpWidget(host(enabled: false));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('chưa có turn -> không vẽ gì, có turn sau đó -> cập nhật', (
      tester,
    ) async {
      await tester.pumpWidget(host(enabled: true));
      expect(find.byType(Text), findsNothing);

      AiLabStore.instance.recordTurn(_turn(AiLabRoute.degraded));
      await tester.pump();
      expect(find.text('⚠ CỤC BỘ (AI_DEGRADED)'), findsOneWidget);
    });
  });
}
