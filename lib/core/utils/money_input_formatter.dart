import 'package:flutter/services.dart';

/// Groups whole đồng while keeping the selection next to the edited digits.
class MoneyInputFormatter extends TextInputFormatter {
  const MoneyInputFormatter({this.maxDigits});

  final int? maxDigits;

  static String format(String? input) {
    if (input == null || input.isEmpty) return '';
    final value = input.trim().replaceAll(RegExp(r'\s*₫$'), '');
    final negative = value.startsWith('-');
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return negative ? '-' : '';
    final grouped = digits.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (match) => '${match[1]}.',
    );
    return negative ? '-$grouped' : grouped;
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    if (!RegExp(r'^-?[0-9.\s]*₫?$').hasMatch(newValue.text)) {
      return newValue;
    }
    var text = newValue.text;
    var selection = newValue.selection;
    // Removing only a separator would otherwise immediately put it back.
    final caret = selection.baseOffset;
    if (selection.isCollapsed &&
        oldValue.selection.isCollapsed &&
        oldValue.text.length == text.length + 1 &&
        oldValue.selection.baseOffset == caret + 1 &&
        caret > 0 &&
        oldValue.text[caret] == '.' &&
        oldValue.text.replaceRange(caret, caret + 1, '') == text) {
      text = text.replaceRange(caret - 1, caret, '');
      selection = TextSelection.collapsed(offset: caret - 1);
    }
    if (maxDigits != null &&
        RegExp(r'[0-9]').allMatches(text).length > maxDigits!) {
      return oldValue;
    }
    final formatted = format(text);
    int offset(int original) {
      if (original < 0) return formatted.length;
      final count = RegExp(
        r'[0-9-]',
      ).allMatches(text.substring(0, original.clamp(0, text.length))).length;
      if (count == 0) return 0;
      var seen = 0;
      for (var i = 0; i < formatted.length; i++) {
        if (formatted[i] != '.') seen++;
        if (seen == count) return i + 1;
      }
      return formatted.length;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection(
        baseOffset: offset(selection.baseOffset),
        extentOffset: offset(selection.extentOffset),
        affinity: selection.affinity,
        isDirectional: selection.isDirectional,
      ),
    );
  }
}
