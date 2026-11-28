import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/monitoring/ai_lab_store.dart';

/// Chi phí đã quy đổi, do nơi gọi cung cấp khi đã có bảng giá thật. Overlay
/// không tự bịa giá: không truyền thì không hiện dòng chi phí.
@immutable
final class AiLabCostSummary {
  const AiLabCostSummary({
    required this.usd,
    required this.savedUsd,
    required this.vndPerUsd,
  });

  final double usd;
  final double savedUsd;
  final double vndPerUsd;
}

/// `1234567` -> `1.234.567`.
String formatVnd(num value) {
  final digits = value.round().abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return value.round() < 0 ? '-$buffer' : buffer.toString();
}

/// `2.5` -> `2,5000`.
String formatUsd(double value) => value.toStringAsFixed(4).replaceAll('.', ',');

/// Bộ đếm cộng dồn: số lượt gọi LLM, token, số lượt đã tiết kiệm so với B0.
class AiLabCounters extends StatelessWidget {
  const AiLabCounters({super.key, this.cost});

  final AiLabCostSummary? cost;

  @override
  Widget build(BuildContext context) {
    final store = AiLabStore.instance;
    final style = Theme.of(context).textTheme.labelMedium;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final totals = store.totals;
        final cost = this.cost;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Lượt gọi LLM: ${totals.llmCalls}', style: style),
            Text('Token: ${formatVnd(totals.tokens)}', style: style),
            Text('Đã tiết kiệm: ${totals.savedLlmCalls} lượt', style: style),
            if (cost != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Column(
                key: const ValueKey('ai-lab-cost'),
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Chi phí: ${formatUsd(cost.usd)} USD · '
                    '${formatVnd(cost.usd * cost.vndPerUsd)} ₫',
                    style: style,
                  ),
                  Text(
                    'Tiết kiệm: ${formatUsd(cost.savedUsd)} USD · '
                    '${formatVnd(cost.savedUsd * cost.vndPerUsd)} ₫',
                    style: style,
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
