import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/monitoring/ai_lab_store.dart';
import 'package:hoadon_insight/features/ai_lab/application/ai_lab_actions.dart';
import 'package:hoadon_insight/features/ai_lab/presentation/ai_lab_batch_section.dart';
import 'package:hoadon_insight/features/ai_lab/presentation/ai_lab_control_panel.dart';

class _FakeActions implements AiLabActions {
  final calls = <String>[];

  @override
  Future<void> askPreset(String text) async => calls.add('ask:$text');

  @override
  Future<void> importAsset(String assetPath) async =>
      calls.add('import:$assetPath');

  @override
  void setFault(String? fault) => calls.add('fault:$fault');

  @override
  void setTamperTotal(bool on) => calls.add('tamper:$on');

  @override
  Future<void> resetLocal() async => calls.add('reset');
}

Future<_FakeActions> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(600, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final actions = _FakeActions();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [aiLabActionsProvider.overrideWithValue(actions)],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: AiLabControlPanel())),
      ),
    ),
  );
  return actions;
}

void main() {
  setUp(() => AiLabStore.instance.reset());
  tearDown(() => AiLabStore.instance.reset());

  testWidgets('3 nút câu hỏi mẫu gọi askPreset đúng chữ', (tester) async {
    final actions = await _pump(tester);
    for (final question in const [
      'Tháng này tôi chi bao nhiêu?',
      'Tại sao tháng này tôi chi nhiều?',
      'Hôm nay ăn trưa hết 35k',
    ]) {
      await tester.tap(find.text(question));
    }
    expect(actions.calls, [
      'ask:Tháng này tôi chi bao nhiêu?',
      'ask:Tại sao tháng này tôi chi nhiều?',
      'ask:Hôm nay ăn trưa hết 35k',
    ]);
  });

  testWidgets('nhóm "Lỗi giả lập" gọi setFault(null|429|500|timeout)', (
    tester,
  ) async {
    final actions = await _pump(tester);
    expect(find.text('Lỗi giả lập'), findsOneWidget);
    // Bắt đầu ở "Không": chọn lần lượt các lựa chọn khác rồi "Không" không phát
    // sinh vì giá trị store (chưa đổi, do actions giả) vẫn là "Không".
    await tester.tap(find.text('429'));
    await tester.tap(find.text('500'));
    await tester.tap(find.text('timeout'));
    AiLabStore.instance.fault = 'timeout';
    await tester.pump();
    await tester.tap(find.text('Không'));
    expect(actions.calls, [
      'fault:429',
      'fault:500',
      'fault:timeout',
      'fault:null',
    ]);
  });

  testWidgets('radio phản ánh AiLabStore.instance.fault', (tester) async {
    await _pump(tester);
    RadioListTile<String> tile(String fault) => tester.widget(
      find.byKey(ValueKey('ai-lab-fault-$fault')),
    );
    RadioGroup<String> group() => tester.widget(find.byType(RadioGroup<String>));
    expect(group().groupValue, 'none');
    AiLabStore.instance.fault = '500';
    await tester.pump();
    expect(group().groupValue, '500');
    expect(tile('500').value, '500');
  });

  testWidgets('công tắc bóp méo tổng gọi setTamperTotal và phản ánh store', (
    tester,
  ) async {
    final actions = await _pump(tester);
    expect(find.text('Bóp méo tổng hóa đơn (lỗi mô phỏng)'), findsOneWidget);
    await tester.tap(find.byType(Switch));
    expect(actions.calls, ['tamper:true']);
    AiLabStore.instance.tamperExtractTotal = true;
    await tester.pump();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('hóa đơn mẫu gọi importAsset đúng asset', (tester) async {
    final actions = await _pump(tester);
    await tester.tap(find.text('Hóa đơn mẫu 1'));
    await tester.tap(find.text('Hóa đơn mẫu 2'));
    expect(actions.calls, [
      'import:assets/ai_lab/receipt_normal.png',
      'import:assets/ai_lab/receipt_repeat.png',
    ]);
  });

  testWidgets('nút Reset gọi resetLocal và có mục chạy 40 câu', (tester) async {
    final actions = await _pump(tester);
    expect(find.byType(AiLabBatchSection), findsOneWidget);
    await tester.tap(find.text('Reset'));
    expect(actions.calls, ['reset']);
  });
}
