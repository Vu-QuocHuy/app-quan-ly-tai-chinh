import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/monitoring/ai_lab_store.dart';
import '../application/ai_lab_actions.dart';
import 'ai_lab_batch_section.dart';

/// Câu hỏi mẫu cho các cảnh demo (đúng từng chữ theo runbook).
const aiLabPresetQuestions = [
  'Tháng này tôi chi bao nhiêu?',
  'Tại sao tháng này tôi chi nhiều?',
  'Hôm nay ăn trưa hết 35k',
];

const aiLabReceiptNormalAsset = 'assets/ai_lab/receipt_normal.png';
const aiLabReceiptRepeatAsset = 'assets/ai_lab/receipt_repeat.png';

const _noFault = 'none';
const _faultOptions = <(String, String?)>[
  ('Không', null),
  ('429', '429'),
  ('500', '500'),
  ('timeout', 'timeout'),
];

/// Bảng điều khiển AI Lab (chỉ debug): câu hỏi mẫu, lỗi giả lập, hóa đơn mẫu,
/// reset và bộ chạy 40 câu. Mọi thao tác đi qua [aiLabActionsProvider] nên test
/// có thể thay bằng bản giả.
class AiLabControlPanel extends ConsumerWidget {
  const AiLabControlPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.watch(aiLabActionsProvider);
    final labelStyle = Theme.of(context).textTheme.labelLarge;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Câu hỏi mẫu', style: labelStyle),
        const SizedBox(height: AppSpacing.xs),
        for (final question in aiLabPresetQuestions)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: OutlinedButton(
              onPressed: () => actions.askPreset(question),
              child: Text(question, textAlign: TextAlign.center),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        ListenableBuilder(
          listenable: AiLabStore.instance,
          builder: (context, _) {
            final store = AiLabStore.instance;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Lỗi giả lập', style: labelStyle),
                RadioGroup<String>(
                  groupValue: store.fault ?? _noFault,
                  onChanged: (value) {
                    if (value == null) return;
                    actions.setFault(value == _noFault ? null : value);
                  },
                  child: Column(
                    children: [
                      for (final (label, fault) in _faultOptions)
                        RadioListTile<String>(
                          key: ValueKey('ai-lab-fault-${fault ?? _noFault}'),
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          contentPadding: EdgeInsets.zero,
                          title: Text(label),
                          value: fault ?? _noFault,
                        ),
                    ],
                  ),
                ),
                SwitchListTile(
                  key: const ValueKey('ai-lab-tamper-switch'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Bóp méo tổng hóa đơn (lỗi mô phỏng)'),
                  value: store.tamperExtractTotal,
                  onChanged: actions.setTamperTotal,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        Text('Hóa đơn mẫu', style: labelStyle),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            OutlinedButton(
              onPressed: () => actions.importAsset(aiLabReceiptNormalAsset),
              child: const Text('Hóa đơn mẫu 1'),
            ),
            OutlinedButton(
              onPressed: () => actions.importAsset(aiLabReceiptRepeatAsset),
              child: const Text('Hóa đơn mẫu 2'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        const AiLabBatchSection(),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const ValueKey('ai-lab-reset'),
            onPressed: actions.resetLocal,
            child: const Text('Reset'),
          ),
        ),
      ],
    );
  }
}
