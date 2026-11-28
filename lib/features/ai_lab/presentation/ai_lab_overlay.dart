import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/monitoring/ai_lab_store.dart';
import '../ai_lab_config.dart';
import 'ai_lab_banner.dart';
import 'ai_lab_counters.dart';
import 'ai_lab_token_bar.dart';

/// Lớp phủ AI Lab (chỉ debug). Khi tắt trả nguyên [child]. Khi bật là một
/// [Stack] phủ lên [child]: banner (không nhận tap) và một panel thu gọn ở góc
/// dưới; chỉ nút/panel mới bắt tap, phần còn lại của app thao tác bình thường.
class AiLabOverlay extends StatelessWidget {
  const AiLabOverlay({
    super.key,
    required this.child,
    this.enabled,
    this.clientFlagSet = 'none',
  });

  final Widget child;

  /// Mặc định theo [AiLabConfig.enabled]; test có thể ép giá trị.
  final bool? enabled;

  /// Tập cờ phía client (`a,b` hoặc `none`) để đối chiếu với server.
  final String clientFlagSet;

  @override
  Widget build(BuildContext context) {
    if (!(enabled ?? AiLabConfig.enabled)) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Material(
              type: MaterialType.transparency,
              child: AiLabBanner(
                kind: aiLabProfileKindFrom(AiLabConfig.flagProfile),
                clientFlagSet: clientFlagSet,
              ),
            ),
          ),
        ),
        const Positioned(
          right: AppSpacing.sm,
          bottom: AppSpacing.sm,
          child: Material(
            type: MaterialType.transparency,
            child: _AiLabPanel(),
          ),
        ),
      ],
    );
  }
}

class _AiLabPanel extends StatefulWidget {
  const _AiLabPanel();

  @override
  State<_AiLabPanel> createState() => _AiLabPanelState();
}

class _AiLabPanelState extends State<_AiLabPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_expanded)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Card(
              key: const ValueKey('ai-lab-panel-body'),
              margin: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: ListenableBuilder(
                  listenable: AiLabStore.instance,
                  builder: (context, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'OCR gần nhất',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      AiLabTokenBar(call: AiLabStore.instance.lastExtract),
                      const SizedBox(height: AppSpacing.md),
                      const AiLabCounters(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        FilledButton.tonal(
          key: const ValueKey('ai-lab-panel-toggle'),
          style: FilledButton.styleFrom(
            backgroundColor: scheme.secondaryContainer,
            foregroundColor: scheme.onSecondaryContainer,
            visualDensity: VisualDensity.compact,
          ),
          onPressed: () => setState(() => _expanded = !_expanded),
          child: Text(_expanded ? 'AI Lab ▾' : 'AI Lab ▴'),
        ),
      ],
    );
  }
}
