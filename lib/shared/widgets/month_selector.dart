import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/app_providers.dart';
import '../../core/utils/month_utils.dart';
import 'month_picker_sheet.dart';

class MonthSelector extends ConsumerWidget {
  const MonthSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final label = MonthUtils.label(month);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
                child: TextButton.icon(
                  onPressed: () => _pickMonth(context, ref, month),
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(label),
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
