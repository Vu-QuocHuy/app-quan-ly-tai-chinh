import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/monitoring/ai_lab_store.dart';
import '../ai_lab_config.dart';

/// Thời lượng cho huy hiệu: `40 ms` dưới 1 giây, ngược lại `2,1 s`.
String aiLabDurationText(int durationMs) {
  if (durationMs < 1000) return '$durationMs ms';
  return '${(durationMs / 1000).toStringAsFixed(1).replaceAll('.', ',')} s';
}

/// Nhãn huy hiệu dưới bong bóng trợ lý (hàm thuần, test không cần widget).
String aiLabBadgeText(AiLabTurn turn) {
  switch (turn.route) {
    case AiLabRoute.local:
      return '⚡ TRÊN MÁY · ${turn.llmCalls} lượt · '
          '${aiLabDurationText(turn.durationMs)}';
    case AiLabRoute.cloud:
      return '☁ ĐÁM MÂY · ${turn.llmCalls} lượt · '
          '${aiLabDurationText(turn.durationMs)}';
    case AiLabRoute.fallback:
      final provider = turn.provider;
      if (provider == null || provider.isEmpty) return '↪ DỰ PHÒNG';
      final name = provider[0].toUpperCase() + provider.substring(1);
      return '↪ DỰ PHÒNG: $name';
    case AiLabRoute.degraded:
      return '⚠ CỤC BỘ (AI_DEGRADED)';
  }
}

/// Huy hiệu cho một tin nhắn trợ lý. Không vẽ gì khi AI Lab tắt hoặc chưa có
/// turn cho [messageId].
class AiLabBadge extends StatelessWidget {
  const AiLabBadge({super.key, required this.messageId, this.enabled});

  final String messageId;

  /// Mặc định theo [AiLabConfig.enabled]; test có thể ép giá trị.
  final bool? enabled;

  @override
  Widget build(BuildContext context) {
    if (!(enabled ?? AiLabConfig.enabled)) return const SizedBox.shrink();
    final store = AiLabStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final turn = store.turnFor(messageId);
        if (turn == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppShapes.xs),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Text(
                aiLabBadgeText(turn),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
