import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/config/ai_flag_overrides.dart';
import 'package:hoadon_insight/core/config/ai_flag_profile.dart';
import 'package:hoadon_insight/core/config/feature_flags.dart';

AiFlagOverrides _make({String profile = 'server', bool allow = true}) =>
    AiFlagOverrides(
      profile: AiFlagProfile.parse(profile),
      allowChanges: allow,
    );

void main() {
  group('trạng thái ban đầu', () {
    test('server: không ghi đè', () {
      final o = _make();
      expect(o.enabled, isNull);
      expect(o.kind, AiFlagProfileKind.server);
      expect(o.headerValue, isNull);
      expect(o.enabledCount, 0);
      expect(o.revision, 0);
      expect(o.isOn(AiOptimizationFlag.chatLocalRouter), isFalse);
    });

    test('b0, b1 và only:* lấy từ AiFlagProfile', () {
      expect(_make(profile: 'b0').kind, AiFlagProfileKind.b0);
      expect(_make(profile: 'b0').enabled, isEmpty);
      final b1 = _make(profile: 'b1');
      expect(b1.kind, AiFlagProfileKind.b1);
      expect(b1.enabledCount, 10);
      final custom = _make(profile: 'only:ai.chat.local_router');
      expect(custom.kind, AiFlagProfileKind.custom);
      expect(custom.enabled, {AiOptimizationFlag.chatLocalRouter});
    });
  });

  group('setFlag', () {
    test('từ server: bắt đầu từ "tắt hết" rồi bật một cờ', () {
      final o = _make();
      o.setFlag(AiOptimizationFlag.chatMergeCalls, true);
      expect(o.enabled, {AiOptimizationFlag.chatMergeCalls});
      expect(o.kind, AiFlagProfileKind.custom);
      expect(o.enabledCount, 1);
    });

    test('tắt cờ cuối cùng -> b0; bật đủ 10 -> b1', () {
      final o = _make();
      o.setFlag(AiOptimizationFlag.chatMergeCalls, true);
      o.setFlag(AiOptimizationFlag.chatMergeCalls, false);
      expect(o.kind, AiFlagProfileKind.b0);
      for (final flag in AiOptimizationFlag.values) {
        o.setFlag(flag, true);
      }
      expect(o.kind, AiFlagProfileKind.b1);
      expect(o.enabledCount, 10);
    });

    test('tắt một cờ khi từ server -> b0 (không phải server)', () {
      final o = _make();
      o.setFlag(AiOptimizationFlag.chatMergeCalls, false);
      expect(o.kind, AiFlagProfileKind.b0);
      expect(o.enabled, isEmpty);
    });

    test('giá trị không đổi thì không thông báo và không tăng revision', () {
      final o = _make(profile: 'b0');
      var notified = 0;
      o.addListener(() => notified++);
      o.setFlag(AiOptimizationFlag.chatMergeCalls, false);
      expect(notified, 0);
      expect(o.revision, 0);
      o.setFlag(AiOptimizationFlag.chatMergeCalls, true);
      expect(notified, 1);
      expect(o.revision, 1);
    });

    test('tập trả về không sửa được từ bên ngoài', () {
      final o = _make(profile: 'b0');
      expect(
        () => o.enabled!.add(AiOptimizationFlag.chatMergeCalls),
        throwsUnsupportedError,
      );
    });
  });

  group('setAll', () {
    test('true -> b1, false -> b0, đều có header đủ 10 cờ', () {
      final o = _make();
      o.setAll(true);
      expect(o.kind, AiFlagProfileKind.b1);
      expect(o.headerValue!.split(','), hasLength(10));
      expect(o.headerValue, isNot(contains('=0')));
      o.setAll(false);
      expect(o.kind, AiFlagProfileKind.b0);
      expect(o.headerValue, isNot(contains('=1')));
      expect(o.revision, 2);
    });

    test('setAll(false) khi đang server -> b0 (đổi trạng thái)', () {
      final o = _make();
      o.setAll(false);
      expect(o.enabled, isEmpty);
      expect(o.revision, 1);
    });
  });

  group('applyMap', () {
    test('bỏ qua khóa lạ, giữ nguyên khóa vắng mặt', () {
      final o = _make(profile: 'only:ai.chat.local_router');
      o.applyMap({
        'ai.chat.merge_calls': true,
        'ai.nope': true,
        'ai.chat.local_router': true,
      });
      expect(o.enabled, {
        AiOptimizationFlag.chatLocalRouter,
        AiOptimizationFlag.chatMergeCalls,
      });
      o.applyMap({'ai.chat.local_router': false});
      expect(o.enabled, {AiOptimizationFlag.chatMergeCalls});
    });

    test('từ server: nền "tắt hết"', () {
      final o = _make();
      o.applyMap({'ai.extract.validator': true});
      expect(o.enabled, {AiOptimizationFlag.extractValidator});
    });

    test('không có khóa hợp lệ nào -> không đổi gì (vẫn server)', () {
      final o = _make();
      o.applyMap({'ai.nope': true});
      o.applyMap({});
      expect(o.enabled, isNull);
      expect(o.revision, 0);
    });
  });

  group('headerValue', () {
    test('đủ 10 khóa theo thứ tự enum, key=1|0', () {
      final o = _make();
      o.setFlag(AiOptimizationFlag.extractImage1600, true);
      final parts = o.headerValue!.split(',');
      expect(parts, hasLength(10));
      expect(parts.first, 'ai.extract.thinking_low=0');
      expect(parts[1], 'ai.extract.image_1600=1');
      expect(parts.where((p) => p.endsWith('=1')), hasLength(1));
    });
  });

  group('khi không cho đổi (release / không bật AI Lab)', () {
    test('mọi setter là no-op, hành vi y hệt AiFlagProfile tĩnh', () {
      final o = _make(allow: false);
      var notified = 0;
      o.addListener(() => notified++);
      o.setFlag(AiOptimizationFlag.chatMergeCalls, true);
      o.setAll(true);
      o.applyMap({'ai.chat.merge_calls': true});
      expect(o.enabled, isNull);
      expect(o.kind, AiFlagProfileKind.server);
      expect(o.headerValue, isNull);
      expect(o.revision, 0);
      expect(notified, 0);
      expect(o.canChange, isFalse);
    });

    test('profile b1 tĩnh vẫn được giữ nguyên', () {
      final o = _make(profile: 'b1', allow: false);
      o.setAll(false);
      expect(o.kind, AiFlagProfileKind.b1);
      expect(o.enabledCount, 10);
    });

    test('mặc định canChange = false khi test (không có AI_LAB)', () {
      expect(AiFlagOverrides.instance.canChange, isFalse);
    });
  });

  group('apply', () {
    const server = FeatureFlags(
      onlineAi: false,
      cloudSync: false,
      externalRates: true,
      aiOptimizations: {AiOptimizationFlag.chatPromptV2},
    );

    test('server: trả nguyên cờ của server', () {
      expect(_make().apply(server), same(server));
    });

    test('ghi đè AI, giữ cờ sản phẩm từ server', () {
      final o = _make();
      o.setFlag(AiOptimizationFlag.chatMergeCalls, true);
      final flags = o.apply(server);
      expect(flags.aiOptimizations, {AiOptimizationFlag.chatMergeCalls});
      expect(flags.aiFlagSet, 'ai.chat.merge_calls');
      expect(flags.onlineAi, isFalse);
      expect(flags.cloudSync, isFalse);
      expect(flags.externalRates, isTrue);
    });
  });
}
