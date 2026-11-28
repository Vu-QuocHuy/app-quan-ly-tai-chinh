import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/config/ai_flag_profile.dart';
import '../../../core/providers/app_providers.dart';
import '../ai_lab_flag_catalog.dart';
import '../application/ai_lab_actions.dart';

/// Mục "Tính năng tối ưu": 10 công tắc bật/tắt từng kỹ thuật tối ưu của app
/// đang chạy, cộng hai nút "Tắt hết" / "Bật hết". Trạng thái lấy từ
/// [aiFlagOverridesProvider]; thao tác đi qua [AiLabActions.setFlags].
class AiLabFlagsSection extends ConsumerWidget {
  const AiLabFlagsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.watch(aiLabActionsProvider);
    final overrides = ref.watch(aiFlagOverridesProvider);
    final theme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: overrides,
      builder: (context, _) {
        final children = <Widget>[
          Text('Tính năng tối ưu', style: theme.labelLarge),
          if (overrides.kind == AiFlagProfileKind.server)
            Text('Đang theo cờ của server', style: theme.bodySmall),
          const SizedBox(height: AppSpacing.xs),
        ];
        AiLabFlagGroup? group;
        for (final info in aiLabFlagCatalog) {
          if (info.group != group) {
            group = info.group;
            children.add(
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  group.title,
                  style: theme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }
          children.add(
            SwitchListTile(
              key: ValueKey('ai-lab-flag-${info.flag.key}'),
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              title: Text(info.name),
              subtitle: Text(info.where),
              value: overrides.isOn(info.flag),
              onChanged: (on) => actions.setFlags({info.flag.key: on}),
            ),
          );
        }
        children
          ..add(const SizedBox(height: AppSpacing.xs))
          ..add(
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                OutlinedButton(
                  key: const ValueKey('ai-lab-flags-b0'),
                  onPressed: () => actions.setFlags('b0'),
                  child: const Text('Tắt hết (B0 – GỐC)'),
                ),
                FilledButton(
                  key: const ValueKey('ai-lab-flags-b1'),
                  onPressed: () => actions.setFlags('b1'),
                  child: const Text('Bật hết (B1 – TỐI ƯU)'),
                ),
              ],
            ),
          );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      },
    );
  }
}
