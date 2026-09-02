abstract final class OcrTextNormalizer {
  static String normalize(String input) {
    final withoutControls = input.replaceAll(
      RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]'),
      ' ',
    );
    return withoutControls
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .join('\n')
        .trim();
  }
}
