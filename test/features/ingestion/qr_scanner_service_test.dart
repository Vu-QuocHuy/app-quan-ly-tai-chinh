import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/ingestion/data/qr_scanner_service.dart';

void main() {
  test('classifies http(s) QR payload as a URL without opening it', () {
    final payload = QrPayloadParser.parse(
      ' https://provider.example.vn/invoice?id=123 ',
    );
    expect(payload.kind, QrPayloadKind.url);
    expect(payload.uri?.host, 'provider.example.vn');
    expect(payload.rawValue, 'https://provider.example.vn/invoice?id=123');
  });

  test('keeps non-url QR payload as text', () {
    final payload = QrPayloadParser.parse('INV|123|100000');
    expect(payload.kind, QrPayloadKind.text);
    expect(payload.uri, isNull);
  });

  test('rejects empty QR payload', () {
    expect(() => QrPayloadParser.parse('  '), throwsFormatException);
  });
}
