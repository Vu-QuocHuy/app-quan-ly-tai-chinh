import 'package:flutter/material.dart';

import '../../../core/monitoring/ai_lab_store.dart';

enum AiLabProfileKind { b0, b1, custom, server }

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

/// `AI_FLAG_PROFILE` -> loại banner. `only:*` là profile tùy chỉnh; giá trị lạ
/// coi như `server`.
AiLabProfileKind aiLabProfileKindFrom(String profile) {
  final value = profile.trim().toLowerCase();
  if (value == 'b0') return AiLabProfileKind.b0;
  if (value == 'b1') return AiLabProfileKind.b1;
  if (value.startsWith('only:')) return AiLabProfileKind.custom;
  return AiLabProfileKind.server;
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

/// Banner chữ lớn ở đầu màn hình: profile cờ đang chạy, hoặc cảnh báo
/// "LỆCH CỜ" khi tập cờ server trả về khác tập cờ client.
class AiLabBanner extends StatelessWidget {
  const AiLabBanner({
    super.key,
    required this.kind,
    required this.clientFlagSet,
  });

  final AiLabProfileKind kind;
  final String clientFlagSet;

  @override
  Widget build(BuildContext context) {
    final store = AiLabStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final server = store.lastServerFlagSet;
        final mismatch =
            server != null && !aiLabFlagSetsMatch(clientFlagSet, server);

        final (String label, Color color) = mismatch
            ? ('LỆCH CỜ', AiLabBannerColors.amber)
            : switch (kind) {
                AiLabProfileKind.b0 => ('B0 – GỐC', AiLabBannerColors.red),
                AiLabProfileKind.b1 => ('B1 – TỐI ƯU', AiLabBannerColors.green),
                AiLabProfileKind.custom => (
                  'TÙY CHỈNH',
                  AiLabBannerColors.custom,
                ),
                AiLabProfileKind.server => ('SERVER', AiLabBannerColors.grey),
              };
        final onColor = ThemeData.estimateBrightnessForColor(color) ==
                Brightness.dark
            ? Colors.white
            : Colors.black87;
        final theme = Theme.of(context).textTheme;
        final detail = mismatch
            ? 'client: ${clientFlagSet.isEmpty ? 'none' : clientFlagSet}'
                  ' · server: $server'
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
