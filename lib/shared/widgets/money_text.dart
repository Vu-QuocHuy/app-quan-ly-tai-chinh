import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final finance = context.finance;

    final style = switch (emphasis) {
      MoneyEmphasis.display => finance.moneyDisplay,
      MoneyEmphasis.title => finance.moneyTitle,
      MoneyEmphasis.body => finance.moneyBody,
      MoneyEmphasis.caption => finance.moneyCaption,
    };

    final color = tone?.color ?? finance.expense.color;
    final text = compact && currencyCode == 'VND'
        ? MoneyFormatter.compact(minor)
        : MoneyFormatter.format(minor, currencyCode: currencyCode);

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
