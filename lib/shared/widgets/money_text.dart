import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../app/theme/finance_colors.dart';
import '../../core/utils/money_formatter.dart';

enum MoneyEmphasis { display, title, body, caption }

/// Cách DUY NHẤT để render một số tiền.
///
/// Thay sáu cách xử lý typography khác nhau cho tiền rải khắp các màn hình,
/// trong đó có một chỗ in thô `'$value $currency'` ra thành `5000000 VND`.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.minor, {
    this.emphasis = MoneyEmphasis.body,
    this.currencyCode = 'VND',
    this.tone,
    this.compact = false,
    this.fitToWidth = false,
    this.textAlign,
    this.animate = false,
    super.key,
  });

  final int minor;
  final MoneyEmphasis emphasis;
  final String currencyCode;

  /// Lấy màu từ `AppFinanceColors`. Mặc định `expense` = MỰC, không phải màu.
  final FinanceTone? tone;

  /// Dùng `MoneyFormatter.compact` -> "12,5 tr ₫". Cho trục biểu đồ.
  final bool compact;

  /// BẮT BUỘC cho hero: "1.234.567.890 ₫" ở 36sp trong ~280dp khả dụng sẽ
  /// xuống dòng chỉ còn ký hiệu ₫ nếu không có nó.
  final bool fitToWidth;

  final TextAlign? textAlign;

  /// Đếm lên tới giá trị mới thay vì nhảy cóc.
  ///
  /// Chỉ dùng được vì các style tiền đều mang `tabularFigures`: chữ số
  /// không đổi bề ngang trong lúc đếm nên chuỗi không bị dồn qua lại.
  /// Dành cho hero Dashboard; KHÔNG dùng trong dòng danh sách.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    if (!animate || AppMotion.isReduced(context)) {
      return _render(context, minor);
    }
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: minor, end: minor),
      duration: AppMotion.slow,
      curve: AppMotion.enter,
      builder: (context, value, _) => _render(context, value),
    );
  }

  Widget _render(BuildContext context, int value) {
    final finance = context.finance;

    final style = switch (emphasis) {
      MoneyEmphasis.display => finance.moneyDisplay,
      MoneyEmphasis.title => finance.moneyTitle,
      MoneyEmphasis.body => finance.moneyBody,
      MoneyEmphasis.caption => finance.moneyCaption,
    };

    final color = tone?.color ?? finance.expense.color;
    final text = compact && currencyCode == 'VND'
        ? MoneyFormatter.compact(value)
        : MoneyFormatter.format(value, currencyCode: currencyCode);

    final label = Text(
      text,
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style.copyWith(color: color),
      // Chuỗi đã có dấu phân nhóm; đọc màn hình nên đọc nguyên văn.
      semanticsLabel: text,
    );

    if (!fitToWidth) return label;

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: textAlign == TextAlign.right
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: color),
        child: label,
      ),
    );
  }

  /// Dùng khi cần màu nền tương phản (ví dụ trên `tone.container`).
  static Color onContainerColorFor(BuildContext context, FinanceTone? tone) =>
      tone?.onContainer ?? Theme.of(context).colorScheme.onSurface;
}
