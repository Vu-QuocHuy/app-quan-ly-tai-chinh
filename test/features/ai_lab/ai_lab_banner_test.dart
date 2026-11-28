import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/config/ai_flag_overrides.dart';
import 'package:hoadon_insight/core/config/ai_flag_profile.dart';
import 'package:hoadon_insight/core/config/feature_flags.dart';
import 'package:hoadon_insight/core/monitoring/ai_lab_store.dart';
import 'package:hoadon_insight/features/ai_lab/presentation/ai_lab_banner.dart';

AiFlagOverrides _overrides(String profile) => AiFlagOverrides(
  profile: AiFlagProfile.parse(profile),
  allowChanges: true,
);

Widget _host(AiFlagOverrides overrides, {String clientFlagSet = 'none'}) =>
    MaterialApp(
      home: Scaffold(
        body: AiLabBanner(overrides: overrides, clientFlagSet: clientFlagSet),
      ),
    );

Color _bg(WidgetTester tester) => tester
    .widget<ColoredBox>(find.byKey(const ValueKey('ai-lab-banner')))
    .color;

void _server(String? flagSet) => AiLabStore.instance.recordCall(
  AiLabCall(action: 'chat', durationMs: 1, serverFlagSet: flagSet),
);

void main() {
  setUp(() => AiLabStore.instance.reset());
  tearDown(() => AiLabStore.instance.reset());

  testWidgets('0/10 cờ -> chữ "B0 – GỐC" nền đỏ', (tester) async {
    await tester.pumpWidget(_host(_overrides('b0')));
    expect(find.text('B0 – GỐC'), findsOneWidget);
    expect(_bg(tester), AiLabBannerColors.red);
  });

  testWidgets('10/10 cờ -> "B1 – TỐI ƯU" nền xanh', (tester) async {
    await tester.pumpWidget(_host(_overrides('b1')));
    expect(find.text('B1 – TỐI ƯU'), findsOneWidget);
    expect(_bg(tester), AiLabBannerColors.green);
  });

  testWidgets('giữa chừng -> "TÙY CHỈNH" nền vàng nhạt kèm "n/10 bật"', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_overrides('only:ai.chat.local_router,ai.chat.merge_calls')),
    );
    expect(find.text('TÙY CHỈNH'), findsOneWidget);
    expect(find.text('2/10 bật'), findsOneWidget);
    expect(_bg(tester), AiLabBannerColors.custom);
  });

  testWidgets('chưa ghi đè -> nhãn SERVER nền xám', (tester) async {
    await tester.pumpWidget(_host(_overrides('server')));
    expect(find.text('SERVER'), findsOneWidget);
    expect(_bg(tester), AiLabBannerColors.grey);
  });

  testWidgets('banner đổi ngay khi bật/tắt cờ', (tester) async {
    final overrides = _overrides('b0');
    await tester.pumpWidget(_host(overrides));
    expect(find.text('B0 – GỐC'), findsOneWidget);

    overrides.setFlag(AiOptimizationFlag.chatMergeCalls, true);
    await tester.pump();
    expect(find.text('TÙY CHỈNH'), findsOneWidget);
    expect(find.text('1/10 bật'), findsOneWidget);

    overrides.setAll(true);
    await tester.pump();
    expect(find.text('B1 – TỐI ƯU'), findsOneWidget);
    expect(find.text('1/10 bật'), findsNothing);

    overrides.setAll(false);
    await tester.pump();
    expect(find.text('B0 – GỐC'), findsOneWidget);
  });

  testWidgets('B1 nhưng server báo flagSet = none -> "LỆCH CỜ" nền vàng', (
    tester,
  ) async {
    _server('none');
    await tester.pumpWidget(_host(_overrides('b1')));
    expect(find.text('LỆCH CỜ'), findsOneWidget);
    expect(find.text('B1 – TỐI ƯU'), findsNothing);
    expect(_bg(tester), AiLabBannerColors.amber);
  });

  testWidgets('LỆCH CỜ so với tập cờ của ghi đè, không phải clientFlagSet', (
    tester,
  ) async {
    final overrides = _overrides('b0');
    overrides.setFlag(AiOptimizationFlag.chatLocalRouter, true);
    _server('ai.chat.local_router');
    // clientFlagSet (cờ server) bị bỏ qua khi đã có ghi đè.
    await tester.pumpWidget(_host(overrides, clientFlagSet: 'x'));
    expect(find.text('LỆCH CỜ'), findsNothing);

    overrides.setFlag(AiOptimizationFlag.chatMergeCalls, true);
    await tester.pump();
    expect(find.text('LỆCH CỜ'), findsOneWidget);
    expect(
      find.text(
        'client: ai.chat.local_router,ai.chat.merge_calls'
        ' · server: ai.chat.local_router',
      ),
      findsOneWidget,
    );
  });

  testWidgets('chưa ghi đè: so sánh với clientFlagSet (cờ hiệu lực của server)', (
    tester,
  ) async {
    _server('b,a');
    await tester.pumpWidget(
      _host(_overrides('server'), clientFlagSet: 'a, b'),
    );
    expect(find.text('LỆCH CỜ'), findsNothing);
    expect(find.text('SERVER'), findsOneWidget);
  });

  testWidgets('chưa có flagSet của server -> không cảnh báo', (tester) async {
    await tester.pumpWidget(_host(_overrides('b1')));
    expect(find.text('LỆCH CỜ'), findsNothing);
    expect(_bg(tester), AiLabBannerColors.green);
  });

  testWidgets('none và rỗng đều là tập rỗng', (tester) async {
    _server('none');
    await tester.pumpWidget(_host(_overrides('b0')));
    expect(find.text('LỆCH CỜ'), findsNothing);
  });

  testWidgets('cảnh báo xuất hiện khi server báo flagSet sau đó', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_overrides('b1')));
    expect(find.text('LỆCH CỜ'), findsNothing);
    _server('ai.chat.local_router');
    await tester.pump();
    expect(find.text('LỆCH CỜ'), findsOneWidget);
  });

  group('aiLabFlagSetsMatch', () {
    test('tập bằng nhau bất kể thứ tự', () {
      expect(aiLabFlagSetsMatch('a,b', 'b,a'), isTrue);
      expect(aiLabFlagSetsMatch('none', ''), isTrue);
      expect(aiLabFlagSetsMatch('a', 'none'), isFalse);
    });
  });
}
