import 'package:flutter/material.dart';

import '../../../core/config/ai_flag_overrides.dart';
import '../../../core/config/ai_flag_profile.dart';
import '../../../core/config/feature_flags.dart';
import '../../../core/monitoring/ai_lab_store.dart';

/// Màu ngữ nghĩa của banner (đỏ/xanh/vàng/xám). Theme của app không có token
/// "success"/"warning" nên các màu này khai báo tại đây, chỉ dùng cho debug.
abstract final class AiLabBannerColors {
  static const red = Color(0xFFC62828);
  static const green = Color(0xFF2E7D32);

  /// Cảnh báo LỆCH CỜ.
  static const amber = Color(0xFFFF8F00);

  /// Profile tùy chỉnh: vàng nhạt, khác với cảnh báo.
  static const custom = Color(0xFFFFE082);
  static const grey = Color(0xFF616161);
}

Set<String> _flagSet(String raw) => raw
    .split(',')
    .map((flag) => flag.trim())
    .where((flag) => flag.isNotEmpty && flag != 'none')
    .toSet();

/// So sánh hai tập cờ dạng chuỗi `a,b`, bỏ qua thứ tự; `none` và rỗng là tập
/// rỗng.
bool aiLabFlagSetsMatch(String a, String b) {
  final left = _flagSet(a);
  final right = _flagSet(b);
  return left.length == right.length && left.containsAll(right);
}

/// Banner chữ lớn ở đầu màn hình: profile cờ đang chạy (theo [overrides], đổi
/// trực tiếp khi bật/tắt cờ), hoặc cảnh báo "LỆCH CỜ" khi tập cờ server trả về
/// khác tập cờ hiệu lực của client.
///
/// [clientFlagSet] là tập cờ hiệu lực khi chưa ghi đè (cờ lấy từ server); khi
/// có ghi đè thì tập cờ được tính thẳng từ [overrides].
class AiLabBanner extends StatelessWidget {
  const AiLabBanner({super.key, this.overrides, required this.clientFlagSet});

  /// Mặc định [AiFlagOverrides.instance].
  final AiFlagOverrides? overrides;
  final String clientFlagSet;

  @override
  Widget build(BuildContext context) {
    final flagOverrides = overrides ?? AiFlagOverrides.instance;
    final store = AiLabStore.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([store, flagOverrides]),
      builder: (context, _) {
        final kind = flagOverrides.kind;
        final enabled = flagOverrides.enabled;
        final effectiveSet = enabled == null
            ? clientFlagSet
            : FeatureFlags(aiOptimizations: enabled).aiFlagSet;
        final server = store.lastServerFlagSet;
        final mismatch =
            server != null && !aiLabFlagSetsMatch(effectiveSet, server);

        final (String label, Color color) = mismatch
            ? ('LỆCH CỜ', AiLabBannerColors.amber)
            : switch (kind) {
                AiFlagProfileKind.b0 => ('B0 – GỐC', AiLabBannerColors.red),
                AiFlagProfileKind.b1 => (
                  'B1 – TỐI ƯU',
                  AiLabBannerColors.green,
                ),
                AiFlagProfileKind.custom => (
                  'TÙY CHỈNH',
                  AiLabBannerColors.custom,
                ),
                AiFlagProfileKind.server => ('SERVER', AiLabBannerColors.grey),
              };
        final onColor = ThemeData.estimateBrightnessForColor(color) ==
                Brightness.dark
            ? Colors.white
            : Colors.black87;
        final theme = Theme.of(context).textTheme;
        final total = AiOptimizationFlag.values.length;
        final detail = mismatch
            ? 'client: ${effectiveSet.isEmpty ? 'none' : effectiveSet}'
                  ' · server: $server'
            : kind == AiFlagProfileKind.custom
            ? '${flagOverrides.enabledCount}/$total bật'
            : null;

        return ColoredBox(
          key: const ValueKey('ai-lab-banner'),
          color: color,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.titleMedium?.copyWith(
                    color: onColor,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                if (detail != null)
                  Text(
                    detail,
                    textAlign: TextAlign.center,
                    style: theme.labelSmall?.copyWith(color: onColor),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
