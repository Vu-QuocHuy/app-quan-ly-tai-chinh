import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/errors/app_exception.dart';
import 'package:hoadon_insight/features/ingestion/data/pdf_text_service.dart';

void main() {
  test('accepts the standard PDF binary signature', () {
    final bytes = Uint8List.fromList('%PDF-1.7'.codeUnits);

    expect(PdfTextService.hasPdfSignature(bytes), isTrue);
    expect(() => PdfTextService.validateSignature(bytes), returnsNormally);
  });

  test('rejects empty, truncated and renamed non-PDF files', () {
    final invalidFiles = [
      Uint8List(0),
      Uint8List.fromList('%PDF'.codeUnits),
      Uint8List.fromList('<xml>invoice</xml>'.codeUnits),
    ];

    for (final bytes in invalidFiles) {
      expect(PdfTextService.hasPdfSignature(bytes), isFalse);
      expect(
        () => PdfTextService.validateSignature(bytes),
        throwsA(isA<ValidationException>()),
      );
    }
  });
}
