import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/config/ai_flag_overrides.dart';
import 'package:hoadon_insight/core/config/ai_flag_profile.dart';
import 'package:hoadon_insight/core/config/feature_flags.dart';
import 'package:hoadon_insight/core/monitoring/ai_lab_store.dart';
import 'package:hoadon_insight/features/ai_lab/ai_lab_config.dart';
import 'package:hoadon_insight/features/ai_lab/presentation/ai_lab_banner.dart';
import 'package:hoadon_insight/features/ai_lab/presentation/ai_lab_control_panel.dart';
import 'package:hoadon_insight/features/ai_lab/presentation/ai_lab_overlay.dart';

Widget _app({required bool enabled, required VoidCallback onTap}) =>
    ProviderScope(
      child: MaterialApp(
        builder: (context, child) =>
            AiLabOverlay(enabled: enabled, child: child!),
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: onTap,
              child: const Text('Nút app'),
            ),
          ),
        ),
      ),
    );

void main() {
  setUp(() => AiLabStore.instance.reset());
  tearDown(() => AiLabStore.instance.reset());

  test('AiLabConfig.enabled mặc định tắt khi không có --dart-define=AI_LAB', () {
    expect(AiLabConfig.enabled, isFalse);
  });

  testWidgets('enabled=false -> không dựng overlay (child nguyên vẹn)', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(_app(enabled: false, onTap: () => taps++));
    expect(find.byType(AiLabBanner), findsNothing);
    expect(find.byKey(const ValueKey('ai-lab-panel-toggle')), findsNothing);
    await tester.tap(find.text('Nút app'));
    expect(taps, 1);
  });

  testWidgets('enabled=false trả nguyên child', (tester) async {
    const child = SizedBox(key: ValueKey('c'));
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: AiLabOverlay(enabled: false, child: child),
      ),
    );
    expect(find.byType(Stack), findsNothing);
    expect(find.byKey(const ValueKey('c')), findsOneWidget);
  });

  testWidgets('enabled=true -> có banner, panel thu gọn, child vẫn nhận tap', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(_app(enabled: true, onTap: () => taps++));

    expect(find.byType(AiLabBanner), findsOneWidget);
    expect(find.text('SERVER'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-lab-panel-toggle')), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-lab-panel-body')), findsNothing);

    await tester.tap(find.text('Nút app'));
    expect(taps, 1);
  });

  testWidgets('bấm nút panel mở rộng: thanh token và bộ đếm; bấm lại thu gọn', (
    tester,
  ) async {
    await tester.pumpWidget(_app(enabled: true, onTap: () {}));

    await tester.tap(find.byKey(const ValueKey('ai-lab-panel-toggle')));
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-lab-panel-body')), findsOneWidget);
    expect(find.byType(AiLabControlPanel), findsOneWidget);
    expect(find.text('Lượt gọi LLM: 0'), findsOneWidget);
    expect(find.text('—'), findsOneWidget); // chưa có OCR nào

    AiLabStore.instance.recordCall(
      const AiLabCall(
        action: 'extract',
        durationMs: 1,
        inputTokens: 10,
        thinkingTokens: 0,
        outputTokens: 5,
      ),
    );
    await tester.pump();
    expect(find.text('suy luận 0'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ai-lab-panel-toggle')));
    await tester.pump();
    expect(find.byKey(const ValueKey('ai-lab-panel-body')), findsNothing);
  });

  testWidgets('banner phản ánh clientFlagSet lệch với server', (tester) async {
    AiLabStore.instance.recordCall(
      const AiLabCall(action: 'chat', durationMs: 1, serverFlagSet: 'none'),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: (context, child) => AiLabOverlay(
            enabled: true,
            clientFlagSet: 'ai.chat.local_router',
            child: child!,
          ),
          home: const Scaffold(),
        ),
      ),
    );
    expect(find.text('LỆCH CỜ'), findsOneWidget);
  });

  testWidgets('banner theo AiFlagOverrides: đổi cờ là đổi banner', (
    tester,
  ) async {
    final overrides = AiFlagOverrides(
      profile: AiFlagProfile.parse('b0'),
      allowChanges: true,
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          builder: (context, child) => AiLabOverlay(
            enabled: true,
            overrides: overrides,
            child: child!,
          ),
          home: const Scaffold(),
        ),
      ),
    );
    expect(find.text('B0 – GỐC'), findsOneWidget);
    overrides.setAll(true);
    await tester.pump();
    expect(find.text('B1 – TỐI ƯU'), findsOneWidget);
    overrides.setAll(false);
    overrides.setFlag(AiOptimizationFlag.chatLocalRouter, true);
    await tester.pump();
    expect(find.text('TÙY CHỈNH'), findsOneWidget);
    expect(find.text('1/10 bật'), findsOneWidget);
  });
}
