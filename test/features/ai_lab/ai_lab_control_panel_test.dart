import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/config/ai_flag_overrides.dart';
import 'package:hoadon_insight/core/config/ai_flag_profile.dart';
import 'package:hoadon_insight/core/config/feature_flags.dart';
import 'package:hoadon_insight/core/monitoring/ai_lab_store.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
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
  void setFlags(Object spec) {
    calls.add('flags:$spec');
    // Like the real actions, drive the shared notifier.
    switch (spec) {
      case 'b0':
        overrides?.setAll(false);
      case 'b1':
        overrides?.setAll(true);
      case Map<String, bool>():
        overrides?.applyMap(spec);
    }
  }

  AiFlagOverrides? overrides;

  @override
  Future<void> resetLocal() async => calls.add('reset');
}

Future<_FakeActions> _pump(
  WidgetTester tester, {
  AiFlagOverrides? overrides,
}) async {
  tester.view.physicalSize = const Size(600, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final actions = _FakeActions()..overrides = overrides;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aiLabActionsProvider.overrideWithValue(actions),
        if (overrides != null) aiFlagOverridesProvider.overrideWithValue(overrides),
      ],
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
    await tester.tap(find.byKey(const ValueKey('ai-lab-tamper-switch')));
    expect(actions.calls, ['tamper:true']);
    AiLabStore.instance.tamperExtractTotal = true;
    await tester.pump();
    expect(
      tester
          .widget<SwitchListTile>(
            find.byKey(const ValueKey('ai-lab-tamper-switch')),
          )
          .value,
      isTrue,
    );
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

  group('mục "Tính năng tối ưu"', () {
    AiFlagOverrides newOverrides([String profile = 'b0']) => AiFlagOverrides(
      profile: AiFlagProfile.parse(profile),
      allowChanges: true,
    );

    bool isOn(WidgetTester tester, AiOptimizationFlag flag) => tester
        .widget<SwitchListTile>(find.byKey(ValueKey('ai-lab-flag-${flag.key}')))
        .value;

    testWidgets('có đủ 10 công tắc theo 3 nhóm, tên và nơi hiệu lực', (
      tester,
    ) async {
      await _pump(tester, overrides: newOverrides());
      expect(find.text('Tính năng tối ưu'), findsOneWidget);
      for (final group in ['Đọc hóa đơn', 'Chat', 'Nền tảng']) {
        expect(find.text(group), findsOneWidget, reason: group);
      }
      for (final name in [
        'Giảm suy luận của AI',
        'Thu nhỏ ảnh về 1600 px',
        'Chặn ảnh trùng trước khi gọi AI',
        'Hậu kiểm số học hóa đơn',
        'Trả lời câu tra cứu trên máy',
        'Gộp lượt gọi chat',
        'Prompt chat rút gọn',
        'Phân loại cửa hàng trên máy',
        'Dự phòng 9Router → Gemini',
        'Gửi telemetry lên server',
      ]) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      for (final flag in AiOptimizationFlag.values) {
        expect(
          find.byKey(ValueKey('ai-lab-flag-${flag.key}')),
          findsOneWidget,
          reason: flag.key,
        );
      }
      expect(find.text('server'), findsNWidgets(3));
      expect(find.text('máy'), findsNWidgets(7));
    });

    testWidgets('công tắc phản ánh notifier và gọi setFlags với một khóa', (
      tester,
    ) async {
      final overrides = newOverrides('only:ai.chat.merge_calls');
      final actions = await _pump(tester, overrides: overrides);
      expect(isOn(tester, AiOptimizationFlag.chatMergeCalls), isTrue);
      expect(isOn(tester, AiOptimizationFlag.chatLocalRouter), isFalse);

      await tester.tap(
        find.byKey(const ValueKey('ai-lab-flag-ai.chat.local_router')),
      );
      await tester.pump();
      expect(actions.calls, ['flags:{ai.chat.local_router: true}']);
      expect(isOn(tester, AiOptimizationFlag.chatLocalRouter), isTrue);
      expect(overrides.enabledCount, 2);

      // Đổi từ nơi khác (lệnh từ trang điều khiển) cũng cập nhật công tắc.
      overrides.setAll(false);
      await tester.pump();
      expect(isOn(tester, AiOptimizationFlag.chatMergeCalls), isFalse);
    });

    testWidgets('nút "Tắt hết" và "Bật hết" gọi setFlags b0/b1', (
      tester,
    ) async {
      final overrides = newOverrides();
      final actions = await _pump(tester, overrides: overrides);
      await tester.tap(find.text('Bật hết (B1 – TỐI ƯU)'));
      await tester.pump();
      expect(overrides.kind, AiFlagProfileKind.b1);
      for (final flag in AiOptimizationFlag.values) {
        expect(isOn(tester, flag), isTrue, reason: flag.key);
      }
      await tester.tap(find.text('Tắt hết (B0 – GỐC)'));
      await tester.pump();
      expect(overrides.kind, AiFlagProfileKind.b0);
      expect(isOn(tester, AiOptimizationFlag.chatMergeCalls), isFalse);
      expect(actions.calls, ['flags:b1', 'flags:b0']);
    });
  });
}
