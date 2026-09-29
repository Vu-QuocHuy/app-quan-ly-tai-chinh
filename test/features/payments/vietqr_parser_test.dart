import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:hoadon_insight/features/payments/data/vietqr_parser.dart';

void main() {
  group('VietQrParser', () {
    test(
      'parses a VietQR account transfer and its optional payment fields',
      () {
        final payload = VietQrParser.parse(_validPayload());

        expect(payload.bankBin, '970436');
        expect(payload.accountNumber, '123456789');
        expect(payload.recipientName, 'NGUYEN AN');
        expect(payload.memo, 'CA PHE');
        expect(payload.amountVnd, 125000);
      },
    );

    test('rejects a payload with a tampered value and invalid CRC', () {
      final payload = _validPayload().replaceFirst('125000', '125001');

      expect(() => VietQrParser.parse(payload), throwsFormatException);
    });

    test('rejects generic links instead of treating them as payment QR', () {
      expect(
        () => VietQrParser.parse('https://example.com/pay'),
        throwsFormatException,
      );
    });
  });
}

String _validPayload() {
  final merchant =
      _field('00', 'A000000727') +
      _field('01', _field('00', '970436') + _field('01', '123456789')) +
      _field('02', 'QRIBFTTA');
  final additional = _field('08', 'CA PHE');
  final body = [
    _field('00', '01'),
    _field('01', '11'),
    _field('26', merchant),
    _field('52', '0000'),
    _field('53', '704'),
    _field('54', '125000'),
    _field('58', 'VN'),
    _field('59', 'NGUYEN AN'),
    _field('60', 'HANOI'),
    _field('62', additional),
    '6304',
  ].join();
  final checksum = _crc16(utf8.encode(body));
  return '$body${checksum.toRadixString(16).padLeft(4, '0').toUpperCase()}';
}

String _field(String tag, String value) {
  final length = utf8.encode(value).length.toString().padLeft(2, '0');
  return '$tag$length$value';
}

int _crc16(List<int> bytes) {
  var crc = 0xFFFF;
  for (final byte in bytes) {
    crc ^= byte << 8;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1;
      crc &= 0xFFFF;
    }
  }
  return crc;
}
