import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import '../../../core/errors/app_exception.dart';

class PdfTextService {
  const PdfTextService();

  static const int _maxPages = 100;

  static bool hasPdfSignature(Uint8List bytes) {
    const signature = [0x25, 0x50, 0x44, 0x46, 0x2D]; // %PDF-
    if (bytes.length < signature.length) return false;
    for (var index = 0; index < signature.length; index++) {
      if (bytes[index] != signature[index]) return false;
    }
    return true;
  }

  static void validateSignature(Uint8List bytes) {
    if (!hasPdfSignature(bytes)) {
      throw const ValidationException('File đã chọn không phải PDF hợp lệ.');
    }
  }

  Future<String> extractText(
    Uint8List bytes, {
    required String fileName,
  }) async {
    validateSignature(bytes);
    await pdfrxFlutterInitialize();
    PdfDocument? document;
    try {
      document = await PdfDocument.openData(bytes, sourceName: fileName);
      if (document.pages.length > _maxPages) {
        throw const ValidationException(
          'PDF vượt quá giới hạn 100 trang. Hãy tách phần hóa đơn cần nhập.',
        );
      }

      final buffer = StringBuffer();
      for (final page in document.pages) {
        final pageText = await page.loadStructuredText();
        final text = pageText.fullText.trim();
        if (text.isNotEmpty) {
          buffer
            ..writeln(text)
            ..writeln();
        }
      }

      final result = buffer.toString().trim();
      if (result.isEmpty) {
        throw const ExtractionException(
          'PDF không có lớp text. Hãy chụp trang hóa đơn để dùng OCR.',
        );
      }
      return result;
    } on AppException {
      rethrow;
    } on Object catch (error) {
      throw ExtractionException(
        'Không thể đọc nội dung PDF. File có thể bị khóa hoặc hỏng.',
        cause: error,
      );
    } finally {
      await document?.dispose();
    }
  }
}
