import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/utils/money_input_formatter.dart';

void main() {
  const formatter = MoneyInputFormatter();
  TextEditingValue edit(String text, [int? caret]) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: caret ?? text.length),
  );

  test('groups typed and pasted whole dong and preserves numeric value', () {
    final result = formatter.formatEditUpdate(edit(''), edit('1234567'));
    expect(result.text, '1.234.567');
    expect(result.selection.baseOffset, 9);
    expect(
      formatter.formatEditUpdate(edit(''), edit('1.234.567 ₫')).text,
      '1.234.567',
    );
  });

  test('preserves caret when inserting in the middle', () {
    final result = formatter.formatEditUpdate(
      edit('12.345', 1),
      edit('192.345', 2),
    );
    expect(result.text, '192.345');
    expect(result.selection.baseOffset, 2);
  });

  test('backspacing a separator removes preceding digit', () {
    final result = formatter.formatEditUpdate(
      edit('12.345', 3),
      edit('12345', 2),
    );
    expect(result.text, '1.345');
    expect(result.selection.baseOffset, 1);
  });

  test('supports empty input and leaves invalid amounts for validation', () {
    expect(formatter.formatEditUpdate(edit('1'), edit('')).text, '');
    expect(formatter.formatEditUpdate(edit('12'), edit('12,5')).text, '12,5');
  });

  test('limits digits without counting grouping separators', () {
    const limited = MoneyInputFormatter(maxDigits: 12);
    final result = limited.formatEditUpdate(edit(''), edit('123456789012'));
    expect(result.text, '123.456.789.012');
    expect(limited.formatEditUpdate(result, edit('123.456.789.0123')), result);
  });

  test('preserves selection ranges and formats prefilled amounts', () {
    final result = formatter.formatEditUpdate(
      edit(''),
      const TextEditingValue(
        text: '1234567',
        selection: TextSelection(baseOffset: 1, extentOffset: 5),
      ),
    );
    expect(
      result.selection,
      const TextSelection(baseOffset: 1, extentOffset: 7),
    );
    expect(MoneyInputFormatter.format('120000'), '120.000');
    expect(MoneyInputFormatter.format(null), '');
  });

  test('does not change composing text', () {
    const value = TextEditingValue(
      text: '1234',
      composing: TextRange(start: 0, end: 4),
    );
    expect(formatter.formatEditUpdate(edit(''), value), value);
  });
}
