import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/monitoring/ai_lab_store.dart';
import 'package:hoadon_insight/features/ai_lab/presentation/ai_lab_banner.dart';

Widget _host(AiLabProfileKind kind, {String clientFlagSet = 'none'}) =>
    MaterialApp(
      home: Scaffold(
        body: AiLabBanner(kind: kind, clientFlagSet: clientFlagSet),
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

  testWidgets('b0 -> chữ "B0 – GỐC" nền đỏ', (tester) async {
    await tester.pumpWidget(_host(AiLabProfileKind.b0));
    expect(find.text('B0 – GỐC'), findsOneWidget);
    expect(_bg(tester), AiLabBannerColors.red);
  });

  testWidgets('b1 -> "B1 – TỐI ƯU" nền xanh', (tester) async {
    await tester.pumpWidget(_host(AiLabProfileKind.b1, clientFlagSet: 'x'));
    expect(find.text('B1 – TỐI ƯU'), findsOneWidget);
    expect(_bg(tester), AiLabBannerColors.green);
  });

  testWidgets('custom -> "TÙY CHỈNH" nền vàng nhạt', (tester) async {
    await tester.pumpWidget(_host(AiLabProfileKind.custom));
    expect(find.text('TÙY CHỈNH'), findsOneWidget);
    expect(_bg(tester), AiLabBannerColors.custom);
  });

  testWidgets('server profile -> nhãn SERVER nền xám', (tester) async {
    await tester.pumpWidget(_host(AiLabProfileKind.server));
    expect(find.text('SERVER'), findsOneWidget);
    expect(_bg(tester), AiLabBannerColors.grey);
  });

  testWidgets('profile b1 nhưng server flagSet = none -> "LỆCH CỜ" nền vàng', (
    tester,
  ) async {
    _server('none');
    await tester.pumpWidget(
      _host(AiLabProfileKind.b1, clientFlagSet: 'ai.chat.local_router'),
    );
    expect(find.text('LỆCH CỜ'), findsOneWidget);
    expect(find.text('B1 – TỐI ƯU'), findsNothing);
    expect(_bg(tester), AiLabBannerColors.amber);
  });

  testWidgets('chưa có flagSet của server -> không cảnh báo', (tester) async {
    await tester.pumpWidget(
      _host(AiLabProfileKind.b1, clientFlagSet: 'ai.chat.local_router'),
    );
    expect(find.text('LỆCH CỜ'), findsNothing);
    expect(_bg(tester), AiLabBannerColors.green);
  });

  testWidgets('so sánh tập cờ bỏ qua thứ tự và khoảng trắng', (tester) async {
    _server('b,a');
    await tester.pumpWidget(_host(AiLabProfileKind.b1, clientFlagSet: 'a, b'));
    expect(find.text('LỆCH CỜ'), findsNothing);
    expect(find.text('B1 – TỐI ƯU'), findsOneWidget);
  });

  testWidgets('none và rỗng đều là tập rỗng', (tester) async {
    _server('none');
    await tester.pumpWidget(_host(AiLabProfileKind.b0, clientFlagSet: ''));
    expect(find.text('LỆCH CỜ'), findsNothing);
  });

  testWidgets('cảnh báo xuất hiện khi server báo flagSet sau đó', (
    tester,
  ) async {
    await tester.pumpWidget(_host(AiLabProfileKind.b1, clientFlagSet: 'a'));
    expect(find.text('LỆCH CỜ'), findsNothing);
    _server('b');
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

  group('aiLabProfileKindFrom', () {
    test('b0, b1, server, only:* -> custom', () {
      expect(aiLabProfileKindFrom('b0'), AiLabProfileKind.b0);
      expect(aiLabProfileKindFrom('b1'), AiLabProfileKind.b1);
      expect(aiLabProfileKindFrom('server'), AiLabProfileKind.server);
      expect(
        aiLabProfileKindFrom('only:ai.chat.local_router'),
        AiLabProfileKind.custom,
      );
      expect(aiLabProfileKindFrom('???'), AiLabProfileKind.server);
    });
  });
}
