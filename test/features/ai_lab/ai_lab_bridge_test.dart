import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
  });
}
