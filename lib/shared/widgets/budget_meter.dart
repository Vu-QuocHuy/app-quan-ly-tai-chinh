import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../app/theme/finance_colors.dart';
import 'money_text.dart';
import 'status_pill.dart';

/// Thanh ngân sách ba tầng, có đuôi tràn và vạch nhịp.
///
/// Thay hai thanh khác nhau vẽ cùng một con số: một cái cao 10 bo 999 màu
/// tertiary trên Dashboard, một cái cao 8 bo 8 màu primary trên Ngân sách.
class BudgetMeter extends StatelessWidget {
  const BudgetMeter({
    required this.spentMinor,
    required this.limitMinor,
    this.paceRatio,
    this.showLabel = true,
    this.animate = true,
    super.key,
  });

  final int spentMinor;
  final int limitMinor;

  /// dayOfMonth / daysInMonth. Vẽ một VẠCH NHỊP rỗng ở vị trí đó.
  /// Không có nó, thanh không phân biệt được người đang tiêu đúng nhịp với
  /// người đã phá tan cả tháng.
  final double? paceRatio;

  final bool showLabel;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finance = context.finance;

    final ratio = limitMinor <= 0 ? 0.0 : spentMinor / limitMinor;
    final percent = (ratio * 100).round();

    // Ba tầng, mỗi tầng là bộ ba (màu, icon, chữ Việt). Ngưỡng 80% khớp
    // BudgetAlertPolicy.approachingThreshold — trước đây policy bắn push ở
    // ngưỡng này nhưng không màn hình nào render nó.
    final (tone, statusTone, icon, label) = switch (ratio) {
      < 0.8 => (
        finance.budgetSafe,
        StatusTone.safe,
        Icons.check_circle_outline,
        'Trong hạn mức',
      ),
      < 1.0 => (
        finance.budgetWarn,
        StatusTone.warn,
        Icons.warning_amber_rounded,
        'Sắp chạm hạn mức',
      ),
      _ => (
        finance.budgetOver,
        StatusTone.danger,
        Icons.error_outline,
        'Đã vượt hạn mức',
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLabel) ...[
          Row(
            children: [
              Expanded(
                child: StatusPill(
                  icon: icon,
                  label: label,
                  tone: statusTone,
                  semanticsLabel:
                      '$label. Đã dùng $percent phần trăm hạn mức tháng.',
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                '$percent%',
                style: theme.textTheme.labelLarge?.copyWith(color: tone.color),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        _MeterBar(
          ratio: ratio,
          tone: tone,
          safeTone: finance.budgetSafe,
          paceRatio: paceRatio,
          animate: animate,
        ),
        if (showLabel) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              MoneyText(
                spentMinor,
                emphasis: MoneyEmphasis.caption,
                tone: tone,
              ),
              Text(
                ' / ',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              MoneyText(limitMinor, emphasis: MoneyEmphasis.caption),
            ],
          ),
        ],
      ],
    );
  }
}

class _MeterBar extends StatelessWidget {
  const _MeterBar({
    required this.ratio,
    required this.tone,
    required this.safeTone,
    required this.animate,
    this.paceRatio,
  });

  final double ratio;
  final FinanceTone tone;
  final FinanceTone safeTone;
  final double? paceRatio;
  final bool animate;

  static const double _height = 10;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration = animate
        ? AppMotion.of(context, AppMotion.slow)
        : Duration.zero;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: ratio),
          duration: duration,
          curve: AppMotion.enter,
          builder: (context, value, _) {
            // Đuôi tràn: trên 100% thanh fill hết bằng budgetSafe rồi vẽ tiếp
            // một đoạn budgetOver phân biệt VÀO TRONG track. Trước đây
            // `clamp(0, 1)` làm 110% và 400% trông y hệt nhau.
            final base = value.clamp(0.0, 1.0);
            final overflow = value > 1.0
                ? ((value - 1.0) / value).clamp(0.0, 1.0)
                : 0.0;

            return SizedBox(
              height: _height,
              child: Stack(
                children: [
                  DecoratedBox(
                    decoration: ShapeDecoration(
                      color: scheme.surfaceContainerHighest,
                      shape: AppShapes.pill,
                    ),
                    child: const SizedBox(width: double.infinity),
                  ),
                  // ClipRRect ở đây là an toàn: widget cố định 10dp, KHÔNG bọc
                  // nội dung cuộn (thứ bị cấm vì buộc saveLayer mỗi frame).
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: Row(
                      children: [
                        SizedBox(
                          width: width * base * (1 - overflow),
                          child: ColoredBox(
                            color: value > 1.0 ? safeTone.color : tone.color,
                            child: const SizedBox(height: _height),
                          ),
                        ),
                        if (overflow > 0)
                          SizedBox(
                            width: width * overflow,
                            child: ColoredBox(
                              color: tone.color,
                              child: const SizedBox(height: _height),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (paceRatio != null && paceRatio! > 0 && paceRatio! < 1)
                    Positioned(
                      left: (width * paceRatio!).clamp(0.0, width - 2),
                      top: 0,
                      bottom: 0,
                      child: Container(width: 2, color: scheme.onSurface),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
