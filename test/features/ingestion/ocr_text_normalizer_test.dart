import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/ingestion/domain/ocr_text_normalizer.dart';

void main() {
  test('normalizes OCR whitespace and control characters', () {
    const input = '  CỬA  HÀNG\r\n\u0000  Tổng   tiền:  120.000  \n\n';

    expect(OcrTextNormalizer.normalize(input), 'CỬA HÀNG\nTổng tiền: 120.000');
  });
}
