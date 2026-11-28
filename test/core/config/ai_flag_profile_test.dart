import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/config/ai_flag_profile.dart';
import 'package:hoadon_insight/core/config/feature_flags.dart';

void main() {
  const serverFlags = FeatureFlags(
    onlineAi: true,
    cloudSync: false,
    externalRates: true,
    aiOptimizations: {AiOptimizationFlag.chatPromptV2},
  );

  group('parse', () {
    test('b0 turns every AI optimisation off and keeps the other flags', () {
      final flags = AiFlagProfile.parse('b0').apply(serverFlags);

      expect(flags.aiOptimizations, isEmpty);
      expect(flags.aiFlagSet, 'none');
      expect(flags.cloudSync, isFalse, reason: 'non-AI flags come from server');
      expect(flags.onlineAi, isTrue);
    });

    test('b1 turns on all 10 AI optimisation flags', () {
      final flags = AiFlagProfile.parse('b1').apply(FeatureFlags.defaults);

      expect(flags.aiOptimizations, AiOptimizationFlag.values.toSet());
      expect(AiOptimizationFlag.values, hasLength(10));
    });

    test('only: enables just the listed flags', () {
      final profile = AiFlagProfile.parse(
        'only:ai.chat.local_router, ai.chat.merge_calls',
      );

      expect(profile.apply(FeatureFlags.defaults).aiOptimizations, {
        AiOptimizationFlag.chatLocalRouter,
        AiOptimizationFlag.chatMergeCalls,
      });
      expect(profile.kind, AiFlagProfileKind.custom);
    });

    test('only: with an unknown flag is rejected', () {
      expect(
        () => AiFlagProfile.parse('only:ai.chat.local_router,ai.nope'),
        throwsFormatException,
      );
    });

    test('only: with nothing after the colon is rejected', () {
      expect(() => AiFlagProfile.parse('only:'), throwsFormatException);
    });

    test('an unknown profile name is rejected', () {
      expect(() => AiFlagProfile.parse('b2'), throwsFormatException);
    });

    test('server leaves the flags untouched and sends no header', () {
      final profile = AiFlagProfile.parse('server');

      expect(identical(profile.apply(serverFlags), serverFlags), isTrue);
      expect(profile.headerValue, isNull);
      expect(profile.kind, AiFlagProfileKind.server);
    });
  });

  group('headerValue', () {
    test('b1 lists all 10 flags as =1 in catalogue order', () {
      final header = AiFlagProfile.parse('b1').headerValue!;
      final parts = header.split(',');

      expect(parts, hasLength(10));
      expect(parts.every((part) => part.endsWith('=1')), isTrue);
      expect(parts.first, 'ai.extract.thinking_low=1');
    });

    test('b0 lists all 10 flags as =0', () {
      final parts = AiFlagProfile.parse('b0').headerValue!.split(',');

      expect(parts, hasLength(10));
      expect(parts.every((part) => part.endsWith('=0')), isTrue);
    });

    test('only: marks the listed flag =1 and the rest =0', () {
      final header = AiFlagProfile.parse(
        'only:ai.chat.prompt_v2',
      ).headerValue!;

      expect(header, contains('ai.chat.prompt_v2=1'));
      expect(header, contains('ai.chat.local_router=0'));
      expect('=1'.allMatches(header), hasLength(1));
    });
  });

  group('label', () {
    test('uses the demo banner wording', () {
      expect(AiFlagProfile.parse('b0').label, 'B0 – GỐC');
      expect(AiFlagProfile.parse('b1').label, 'B1 – TỐI ƯU');
      expect(AiFlagProfile.parse('server').label, 'SERVER');
      expect(AiFlagProfile.parse('only:ai.chat.prompt_v2').label, 'TÙY CHỈNH');
    });
  });

  group('fromEnvironment', () {
    test('is ignored outside debug builds', () {
      final profile = AiFlagProfile.fromEnvironment(debug: false, raw: 'b1');

      expect(profile.kind, AiFlagProfileKind.server);
      expect(profile.headerValue, isNull);
      expect(identical(profile.apply(serverFlags), serverFlags), isTrue);
    });

    test('is used in debug builds', () {
      final profile = AiFlagProfile.fromEnvironment(debug: true, raw: 'b0');
      expect(profile.kind, AiFlagProfileKind.b0);
    });

    test('an invalid value falls back to server instead of crashing the app',
        () {
      final profile = AiFlagProfile.fromEnvironment(debug: true, raw: 'nonsense');
      expect(profile.kind, AiFlagProfileKind.server);
    });
  });
}
