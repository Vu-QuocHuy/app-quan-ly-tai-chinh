import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/monitoring/ai_lab_store.dart';

/// Thanh chồng ngang 3 phần (đầu vào / suy luận / đầu ra) theo số token của
/// lần OCR gần nhất. Thiếu số liệu -> "—", không bao giờ lỗi.
class AiLabTokenBar extends StatelessWidget {
  const AiLabTokenBar({super.key, this.call});

  final AiLabCall? call;

  static const double _barHeight = 10;

  @override
  Widget build(BuildContext context) {
    final call = this.call;
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall;
    if (call == null || call.totalTokens == null) {
      return Text('—', style: style);
    }

    final input = call.inputTokens;
    final thinking = call.thinkingTokens;
    final output = call.outputTokens;
    final total = call.totalTokens!;

    Widget segment(String key, int? tokens, Color color, double maxWidth) {
      final width = (tokens == null || tokens <= 0 || total <= 0)
          ? 0.0
          : maxWidth * tokens / total;
      return SizedBox(
        key: ValueKey(key),
        width: width,
        height: _barHeight,
        child: ColoredBox(color: color),
      );
    }

    Widget caption(Color color, String label, int? tokens) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: AppSpacing.sm,
          child: ColoredBox(color: color),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text('$label ${tokens ?? '—'}', style: style),
      ],
    );

    final inputColor = scheme.primary;
    final thinkingColor = scheme.tertiary;
    final outputColor = scheme.secondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 200.0;
            return DecoratedBox(
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest),
              child: Row(
                children: [
                  segment('ai-lab-token-input', input, inputColor, maxWidth),
                  segment(
                    'ai-lab-token-thinking',
                    thinking,
                    thinkingColor,
                    maxWidth,
                  ),
                  segment('ai-lab-token-output', output, outputColor, maxWidth),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          children: [
            caption(inputColor, 'đầu vào', input),
            caption(thinkingColor, 'suy luận', thinking),
            caption(outputColor, 'đầu ra', output),
          ],
        ),
      ],
    );
  }
}
