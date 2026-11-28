import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/config/ai_flag_overrides.dart';
import 'package:hoadon_insight/core/config/ai_flag_profile.dart';
import 'package:hoadon_insight/core/config/feature_flags.dart';
import 'package:hoadon_insight/core/monitoring/ai_lab_store.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/ai_lab/ai_lab_config.dart';
import 'package:hoadon_insight/features/ai_lab/application/ai_lab_actions.dart';
import 'package:hoadon_insight/features/ai_lab/data/ai_lab_bridge.dart';
import 'package:hoadon_insight/features/ai_lab/data/ai_lab_bridge_host.dart';

const _origin = 'http://localhost:8090';

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
  void setFlags(Object spec) => calls.add('flags:$spec');

  @override
  Future<void> resetLocal() async => calls.add('reset');
}

Map<Object?, Object?> _msg(Object? cmd, [Object? value, Object? v = 1]) => {
  'ailab': v,
  'cmd': cmd,
  'value': ?value,
};

void main() {
  group('parseAiLabMessage - hợp lệ', () {
    test('ask', () {
      expect(
        parseAiLabMessage(_msg('ask', 'Tháng này tôi chi bao nhiêu?'), _origin),
        const AiLabAsk('Tháng này tôi chi bao nhiêu?'),
      );
    });

    test('ask đúng 500 ký tự được chấp nhận', () {
      expect(
        parseAiLabMessage(_msg('ask', 'a' * 500), _origin),
        AiLabAsk('a' * 500),
      );
    });

    test('fault: 429, 500, timeout và null', () {
      for (final f in ['429', '500', 'timeout']) {
        expect(parseAiLabMessage(_msg('fault', f), _origin), AiLabFault(f));
      }
      expect(
        parseAiLabMessage({'ailab': 1, 'cmd': 'fault', 'value': null}, _origin),
        const AiLabFault(null),
      );
      expect(
        parseAiLabMessage({'ailab': 1, 'cmd': 'fault'}, _origin),
        const AiLabFault(null),
      );
    });

    test('importAsset', () {
      expect(
        parseAiLabMessage(
          _msg('importAsset', 'assets/ai_lab/receipt_normal.png'),
          _origin,
        ),
        const AiLabImportAsset('assets/ai_lab/receipt_normal.png'),
      );
    });

    test('tamper true/false', () {
      expect(
        parseAiLabMessage(_msg('tamper', true), _origin),
        const AiLabTamper(true),
      );
      expect(
        parseAiLabMessage({
          'ailab': 1,
          'cmd': 'tamper',
          'value': false,
        }, _origin),
        const AiLabTamper(false),
      );
    });

    test('reset, kể cả khi có value thừa', () {
      expect(parseAiLabMessage(_msg('reset'), _origin), const AiLabReset());
      expect(
        parseAiLabMessage(_msg('reset', 'x'), _origin),
        const AiLabReset(),
      );
    });

    test('origin 127.0.0.1:8090 và Map<dynamic,dynamic> (từ JS) được chấp nhận', () {
      final data = <dynamic, dynamic>{'ailab': 1.0, 'cmd': 'reset'};
      expect(
        parseAiLabMessage(data, 'http://127.0.0.1:8090'),
        const AiLabReset(),
      );
    });
  });

  group('parseAiLabMessage - bị từ chối', () {
    test('origin lạ bị bỏ qua', () {
      for (final o in [
        '',
        'http://localhost:8080',
        'http://localhost:8081',
        'http://evil.example',
        'https://localhost:8090',
        'http://localhost:8090.evil.com',
        'http://localhost:80900',
        'null',
      ]) {
        expect(parseAiLabMessage(_msg('reset'), o), isNull, reason: o);
      }
    });

    test('sai phiên bản', () {
      for (final v in [0, 2, '1', null, true, 1.5]) {
        expect(parseAiLabMessage(_msg('reset', null, v), _origin), isNull);
      }
      expect(parseAiLabMessage({'cmd': 'reset'}, _origin), isNull);
    });

    test('lệnh lạ hoặc thiếu', () {
      expect(parseAiLabMessage(_msg('rm -rf'), _origin), isNull);
      expect(parseAiLabMessage(_msg(null), _origin), isNull);
      expect(parseAiLabMessage(_msg(5), _origin), isNull);
      expect(parseAiLabMessage(_msg('ASK', 'x'), _origin), isNull);
    });

    test('dữ liệu không phải Map không làm crash', () {
      for (final d in <Object?>[
        null,
        1,
        2.5,
        'ailab',
        '{"ailab":1,"cmd":"reset"}',
        true,
        [1, 2, 3],
        {1, 2},
        () {},
        Object(),
      ]) {
        expect(parseAiLabMessage(d, _origin), isNull);
      }
    });

    test('Map rác lồng nhau không làm crash', () {
      expect(
        parseAiLabMessage({
          'ailab': {'a': 1},
          'cmd': ['ask'],
        }, _origin),
        isNull,
      );
      expect(
        parseAiLabMessage({
          1: 2,
          null: 3,
          'ailab': 1,
          'cmd': 'ask',
          'value': {'x': []},
        }, _origin),
        isNull,
      );
      expect(parseAiLabMessage(<dynamic, dynamic>{}, _origin), isNull);
    });

    test('ask: sai kiểu, rỗng, quá dài', () {
      expect(parseAiLabMessage(_msg('ask', 5), _origin), isNull);
      expect(parseAiLabMessage(_msg('ask', ['a']), _origin), isNull);
      expect(parseAiLabMessage(_msg('ask', ''), _origin), isNull);
      expect(parseAiLabMessage(_msg('ask', '   '), _origin), isNull);
      expect(parseAiLabMessage({'ailab': 1, 'cmd': 'ask'}, _origin), isNull);
      expect(parseAiLabMessage(_msg('ask', 'a' * 501), _origin), isNull);
    });

    test('fault: giá trị không thuộc danh sách', () {
      for (final f in <Object>['404', '', 'TIMEOUT', 500, true, ['429']]) {
        expect(
          parseAiLabMessage(_msg('fault', f), _origin),
          isNull,
          reason: '$f',
        );
      }
    });

    test('importAsset: path traversal và đường dẫn ngoài assets/ai_lab/', () {
      for (final p in <Object>[
        'assets/ai_lab/../../secret.png',
        'assets/ai_lab/..',
        'assets/ai_lab/a..b.png',
        r'assets/ai_lab/..\x.png',
        r'assets/ai_lab\x.png',
        'assets/ai_lab/',
        'assets/other/receipt.png',
        '/assets/ai_lab/receipt.png',
        'ASSETS/ai_lab/receipt.png',
        'https://evil.example/assets/ai_lab/x.png',
        '',
        42,
        ['assets/ai_lab/x.png'],
      ]) {
        expect(
          parseAiLabMessage(_msg('importAsset', p), _origin),
          isNull,
          reason: '$p',
        );
      }
      expect(
        parseAiLabMessage({'ailab': 1, 'cmd': 'importAsset'}, _origin),
        isNull,
      );
    });

    test('tamper: chỉ nhận bool', () {
      for (final v in <Object?>['true', 1, 0, null, 'on']) {
        expect(
          parseAiLabMessage({'ailab': 1, 'cmd': 'tamper', 'value': v}, _origin),
          isNull,
          reason: '$v',
        );
      }
    });
  });

  group('runAiLabCommand', () {
    test('mỗi lệnh gọi đúng AiLabActions', () async {
      final actions = _FakeActions();
      await runAiLabCommand(actions, const AiLabAsk('xin chào'));
      await runAiLabCommand(actions, const AiLabFault('429'));
      await runAiLabCommand(actions, const AiLabFault(null));
      await runAiLabCommand(
        actions,
        const AiLabImportAsset('assets/ai_lab/receipt_normal.png'),
      );
      await runAiLabCommand(actions, const AiLabTamper(true));
      await runAiLabCommand(actions, const AiLabReset());
      expect(actions.calls, [
        'ask:xin chào',
        'fault:429',
        'fault:null',
        'import:assets/ai_lab/receipt_normal.png',
        'tamper:true',
        'reset',
      ]);
    });

    test('parse rồi chạy: tin hợp lệ → action tương ứng', () async {
      final actions = _FakeActions();
      final cmd = parseAiLabMessage(_msg('tamper', true), _origin)!;
      await runAiLabCommand(actions, cmd);
      expect(actions.calls, ['tamper:true']);
    });
  });

  group('lệnh flags', () {
    test('"b0" và "b1"', () {
      expect(
        parseAiLabMessage(_msg('flags', 'b0'), _origin),
        const AiLabFlags('b0'),
      );
      expect(
        parseAiLabMessage(_msg('flags', 'b1'), _origin),
        const AiLabFlags('b1'),
      );
    });

    test('object khóa cờ -> bool, kể cả Map<dynamic,dynamic> từ JS', () {
      final cmd = parseAiLabMessage(
        _msg('flags', <dynamic, dynamic>{
          'ai.chat.local_router': true,
          'ai.extract.validator': false,
        }),
        _origin,
      );
      expect(
        cmd,
        const AiLabFlags({
          'ai.chat.local_router': true,
          'ai.extract.validator': false,
        }),
      );
      final spec = (cmd! as AiLabFlags).spec as Map;
      expect(() => spec['x'] = true, throwsUnsupportedError);
    });

    test('mọi khóa của AiOptimizationFlag đều hợp lệ', () {
      final all = {for (final f in AiOptimizationFlag.values) f.key: true};
      expect(parseAiLabMessage(_msg('flags', all), _origin), AiLabFlags(all));
    });

    test('bị từ chối: giá trị lạ, khóa lạ, giá trị không phải bool, rỗng', () {
      for (final v in <Object?>[
        'b2',
        'B0',
        '',
        null,
        1,
        true,
        ['b0'],
        <String, Object?>{},
        {'ai.nope': true},
        {'ai.chat.local_router': true, 'ai.nope': false},
        {'ai.chat.local_router': 'true'},
        {'ai.chat.local_router': 1},
        {'ai.chat.local_router': null},
        {1: true},
        {null: true},
      ]) {
        expect(
          parseAiLabMessage(_msg('flags', v), _origin),
          isNull,
          reason: '$v',
        );
      }
      expect(parseAiLabMessage({'ailab': 1, 'cmd': 'flags'}, _origin), isNull);
      expect(
        parseAiLabMessage(_msg('flags', 'b1'), 'http://evil.example'),
        isNull,
      );
    });

    test('runAiLabCommand gọi setFlags với đúng spec', () async {
      final actions = _FakeActions();
      await runAiLabCommand(actions, const AiLabFlags('b1'));
      await runAiLabCommand(
        actions,
        const AiLabFlags({'ai.chat.local_router': false}),
      );
      expect(actions.calls, [
        'flags:b1',
        'flags:{ai.chat.local_router: false}',
      ]);
    });

    test('AiLabFlags: so sánh theo giá trị', () {
      expect(const AiLabFlags('b0'), isNot(const AiLabFlags('b1')));
      expect(
        const AiLabFlags({'ai.chat.merge_calls': true}),
        const AiLabFlags({'ai.chat.merge_calls': true}),
      );
      expect(
        const AiLabFlags({'ai.chat.merge_calls': true}),
        isNot(const AiLabFlags({'ai.chat.merge_calls': false})),
      );
    });
  });

  group('lệnh hello', () {
    test('parse được, bỏ qua value, vẫn kiểm tra origin và phiên bản', () {
      expect(parseAiLabMessage(_msg('hello'), _origin), const AiLabHello());
      expect(
        parseAiLabMessage(_msg('hello', 'x'), _origin),
        const AiLabHello(),
      );
      expect(parseAiLabMessage(_msg('hello'), 'http://evil.example'), isNull);
      expect(parseAiLabMessage(_msg('hello', null, 2), _origin), isNull);
    });

    test('runAiLabCommand không gọi action nào và hoàn tất', () async {
      final actions = _FakeActions();
      await runAiLabCommand(actions, const AiLabHello());
      expect(actions.calls, isEmpty);
    });
  });

  group('AiLabBridgeHost', () {
    testWidgets('trả nguyên child và không crash (AI Lab tắt trong test)', (
      tester,
    ) async {
      expect(AiLabConfig.enabled, isFalse);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [aiLabActionsProvider.overrideWithValue(_FakeActions())],
          child: const Directionality(
            textDirection: TextDirection.ltr,
            child: AiLabBridgeHost(child: Text('nội dung')),
          ),
        ),
      );
      expect(find.text('nội dung'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    group('khi bật AI Lab', () {
      late _FakeActions actions;
      late AiFlagOverrides overrides;
      late List<Map<String, Object?>> posted;
      late void Function(Object? data, String origin) deliver;
      late int stopCalls;
      late DateTime clock;

      setUp(() {
        AiLabStore.instance.reset();
        actions = _FakeActions();
        overrides = AiFlagOverrides(
          profile: AiFlagProfile.parse('b0'),
          allowChanges: true,
        );
        posted = [];
        stopCalls = 0;
        clock = DateTime.fromMillisecondsSinceEpoch(1000000);
      });
      tearDown(() => AiLabStore.instance.reset());

      Future<void> pumpHost(WidgetTester tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              aiLabActionsProvider.overrideWithValue(actions),
              aiFlagOverridesProvider.overrideWithValue(overrides),
              featureFlagsProvider.overrideWith(
                (ref) async => FeatureFlags.defaults,
              ),
            ],
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: AiLabBridgeHost(
                enabled: true,
                now: () => clock,
                postEvent: posted.add,
                startBridge: (onMessage) {
                  deliver = onMessage;
                  return () => stopCalls++;
                },
                child: const Text('nội dung'),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      testWidgets('gửi metrics ngay khi khởi động', (tester) async {
        await pumpHost(tester);
        expect(find.text('nội dung'), findsOneWidget);
        expect(posted, hasLength(1));
        expect(posted.single['event'], 'metrics');
        expect(posted.single['profile'], 'b0');
        expect(posted.single['ts'], 1000000);
      });

      testWidgets('hello được trả lời ngay, kể cả trong khoảng giới hạn', (
        tester,
      ) async {
        await pumpHost(tester);
        deliver({'ailab': 1, 'cmd': 'hello'}, _origin);
        expect(posted, hasLength(2));
        deliver({'ailab': 1, 'cmd': 'hello'}, 'http://evil.example');
        expect(posted, hasLength(2));
      });

      testWidgets('đổi cờ và đổi AiLabStore -> phát metrics có throttle', (
        tester,
      ) async {
        await pumpHost(tester);
        // Cờ của server tải xong ngay sau khi khởi động nên có thêm một lần
        // phát ở cuối khoảng 250 ms; đợi nó rồi đếm lại từ đầu.
        clock = clock.add(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        posted.clear();

        clock = clock.add(const Duration(milliseconds: 300));
        overrides.setAll(true);
        expect(posted, hasLength(1));
        expect(posted.last['profile'], 'b1');
        expect(posted.last['enabledCount'], 10);

        // Hai thay đổi liền nhau chỉ phát ra một lần ở cuối khoảng 250 ms.
        clock = clock.add(const Duration(milliseconds: 10));
        AiLabStore.instance.recordCall(
          const AiLabCall(action: 'chat', durationMs: 5, llmCalls: 1),
        );
        AiLabStore.instance.recordCall(
          const AiLabCall(action: 'chat', durationMs: 6, llmCalls: 1),
        );
        expect(posted, hasLength(1));
        clock = clock.add(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 250));
        expect(posted, hasLength(2));
        expect((posted.last['totals']! as Map)['llmCalls'], 2);
        expect(posted.last['calls'], hasLength(2));
      });

      testWidgets('lệnh khác hello vẫn đi qua AiLabActions', (tester) async {
        await pumpHost(tester);
        deliver({'ailab': 1, 'cmd': 'flags', 'value': 'b1'}, _origin);
        deliver({'ailab': 1, 'cmd': 'reset'}, _origin);
        deliver({'ailab': 1, 'cmd': 'flags', 'value': 'b9'}, _origin);
        await tester.pump();
        expect(actions.calls, ['flags:b1', 'reset']);
      });

      testWidgets('dispose dừng listener và không phát thêm', (tester) async {
        await pumpHost(tester);
        await tester.pumpWidget(const SizedBox());
        expect(stopCalls, 1);
        clock = clock.add(const Duration(seconds: 1));
        overrides.setAll(true);
        AiLabStore.instance.recordCall(
          const AiLabCall(action: 'chat', durationMs: 1),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(posted, hasLength(1));
      });

      testWidgets('postEvent ném lỗi không làm hỏng app', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              aiFlagOverridesProvider.overrideWithValue(overrides),
              featureFlagsProvider.overrideWith(
                (ref) async => FeatureFlags.defaults,
              ),
            ],
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: AiLabBridgeHost(
                enabled: true,
                startBridge: (_) => () {},
                postEvent: (_) => throw StateError('boom'),
                child: const Text('ok'),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('ok'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('enabled=false: không khởi động bridge, không phát gì', (
        tester,
      ) async {
        var started = false;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [aiFlagOverridesProvider.overrideWithValue(overrides)],
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: AiLabBridgeHost(
                enabled: false,
                startBridge: (_) {
                  started = true;
                  return () {};
                },
                postEvent: posted.add,
                child: const Text('x'),
              ),
            ),
          ),
        );
        await tester.pump();
        overrides.setAll(true);
        await tester.pump(const Duration(seconds: 1));
        expect(started, isFalse);
        expect(posted, isEmpty);
      });
    });
  });
}
