import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/config/ai_flag_overrides.dart';
import 'package:hoadon_insight/core/config/ai_flag_profile.dart';
import 'package:hoadon_insight/core/config/feature_flags.dart';
import 'package:hoadon_insight/core/monitoring/ai_telemetry.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _server = FeatureFlags(
  onlineAi: true,
  cloudSync: false,
  externalRates: false,
  aiOptimizations: {AiOptimizationFlag.chatPromptV2},
);

ProviderContainer _container(AiFlagOverrides overrides) {
  final container = ProviderContainer(
    overrides: [
      aiFlagOverridesProvider.overrideWithValue(overrides),
      serverFeatureFlagsProvider.overrideWith((ref) async => _server),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('không ghi đè: dùng nguyên cờ của server', () async {
    final container = _container(
      AiFlagOverrides(profile: AiFlagProfile.parse('server'), allowChanges: true),
    );
    final sub = container.listen(featureFlagsProvider, (_, _) {});
    addTearDown(sub.close);
    final flags = await container.read(featureFlagsProvider.future);
    expect(flags.aiOptimizations, {AiOptimizationFlag.chatPromptV2});
  });

  test('bật/tắt cờ làm featureFlagsProvider và telemetry đổi theo', () async {
    final overrides = AiFlagOverrides(
      profile: AiFlagProfile.parse('server'),
      allowChanges: true,
    );
    final container = _container(overrides);
    // Giữ provider sống để nó tự tính lại khi ghi đè đổi.
    final sub = container.listen(featureFlagsProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(featureFlagsProvider.future);

    overrides.setFlag(AiOptimizationFlag.chatLocalRouter, true);
    var flags = await container.read(featureFlagsProvider.future);
    expect(flags.aiOptimizations, {AiOptimizationFlag.chatLocalRouter});
    expect(flags.isAiEnabled(AiOptimizationFlag.chatPromptV2), isFalse);
    expect(AiTelemetry.instance.flagSet, 'ai.chat.local_router');
    // Cờ sản phẩm vẫn lấy từ server.
    expect(flags.cloudSync, isFalse);
    expect(flags.externalRates, isFalse);

    overrides.setAll(true);
    flags = await container.read(featureFlagsProvider.future);
    expect(flags.aiOptimizations, AiOptimizationFlag.values.toSet());

    overrides.setAll(false);
    flags = await container.read(featureFlagsProvider.future);
    expect(flags.aiFlagSet, 'none');
    expect(AiTelemetry.instance.flagSet, 'none');
  });

  test('trong lúc tính lại, giá trị cũ vẫn đọc được (không nháy loading)', () async {
    final overrides = AiFlagOverrides(
      profile: AiFlagProfile.parse('b0'),
      allowChanges: true,
    );
    final container = _container(overrides);
    final sub = container.listen(featureFlagsProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(featureFlagsProvider.future);

    overrides.setAll(true);
    expect(container.read(featureFlagsProvider).value, isNotNull);
  });

  test('revision provider phản ánh số đổi của ghi đè', () {
    final overrides = AiFlagOverrides(
      profile: AiFlagProfile.parse('b0'),
      allowChanges: true,
    );
    final container = _container(overrides);
    final sub = container.listen(aiFlagOverridesRevisionProvider, (_, _) {});
    addTearDown(sub.close);
    expect(container.read(aiFlagOverridesRevisionProvider), 0);
    overrides.setAll(true);
    expect(container.read(aiFlagOverridesRevisionProvider), 1);
  });
}
