import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_tokens.dart';
import '../../core/providers/app_providers.dart';
import '../../core/utils/month_utils.dart';
import 'month_picker_sheet.dart';

class MonthSelector extends ConsumerWidget {
  const MonthSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final label = MonthUtils.label(month);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Tháng trước',
              onPressed: () => _setMonth(ref, MonthUtils.shift(month, -1)),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Semantics(
                button: true,
                label: 'Chọn $label',
                child: TextButton(
                  onPressed: () => _pickMonth(context, ref, month),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    alignment: Alignment.center,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.calendar_month_outlined,
                        size: AppIconSizes.md,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(color: scheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Tháng sau',
              onPressed: () => _setMonth(ref, MonthUtils.shift(month, 1)),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }

  static void _setMonth(WidgetRef ref, DateTime month) {
    ref.read(selectedMonthProvider.notifier).state = MonthUtils.normalize(
      month,
    );
  }

  static Future<void> _pickMonth(
    BuildContext context,
    WidgetRef ref,
    DateTime month,
  ) async {
    // Lưới 12 tháng thay cho showDatePicker chi tiết tới NGÀY — sai đơn vị và
    // tốn nhiều thao tác hơn để chọn đúng một tháng.
    final result = await showMonthPickerSheet(context, selected: month);
    if (result != null) _setMonth(ref, result);
  }
}
