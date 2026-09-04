import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../core/utils/month_utils.dart';

/// Chọn THÁNG bằng lưới 12 ô + bộ đổi năm.
///
/// Thay `showDatePicker` — một picker chi tiết tới NGÀY để chọn một THÁNG.
/// Người dùng phải chọn một ngày cụ thể rồi app lặng lẽ chuẩn hoá nó về đầu
/// tháng: sai đơn vị, và tốn nhiều thao tác hơn hẳn.
Future<DateTime?> showMonthPickerSheet(
  BuildContext context, {
  required DateTime selected,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _MonthPickerSheet(selected: selected),
  );
}

class _MonthPickerSheet extends StatefulWidget {
  const _MonthPickerSheet({required this.selected});

  final DateTime selected;

  @override
  State<_MonthPickerSheet> createState() => _MonthPickerSheetState();
}

class _MonthPickerSheetState extends State<_MonthPickerSheet> {
  late int _year = widget.selected.year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          0,
          AppSpacing.gutter,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chọn tháng', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  tooltip: 'Năm trước',
                  onPressed: () => setState(() => _year--),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('$_year', style: theme.textTheme.titleMedium),
                IconButton(
                  tooltip: 'Năm sau',
                  onPressed: () => setState(() => _year++),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 2.1,
              children: [
                for (var month = 1; month <= 12; month++)
                  _MonthCell(
                    label: 'Th $month',
                    selected:
                        _year == widget.selected.year &&
                        month == widget.selected.month,
                    isCurrent: _year == now.year && month == now.month,
                    onTap: () => Navigator.pop(
                      context,
                      MonthUtils.normalize(DateTime(_year, month)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(
                  context,
                  MonthUtils.normalize(DateTime(now.year, now.month)),
                ),
                child: Text(
                  'Về tháng này',
                  style: TextStyle(color: scheme.primary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.label,
    required this.selected,
    required this.isCurrent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? scheme.primary : scheme.surfaceContainerHigh,
        shape: AppShapes.control,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selected ? scheme.onPrimary : scheme.onSurface,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                // Tháng hiện tại có dấu riêng, không chỉ dựa vào màu.
                if (isCurrent && !selected) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.circle, size: 6, color: scheme.primary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
