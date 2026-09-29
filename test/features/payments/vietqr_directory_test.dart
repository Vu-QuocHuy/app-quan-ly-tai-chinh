import 'package:flutter_test/flutter_test.dart';

import 'package:hoadon_insight/features/payments/data/vietqr_directory.dart';

void main() {
  group('VietQrBankApp.launchUri', () {
    const bankApp = VietQrBankApp(
      id: 'mb',
      name: 'MB Bank',
      bankName: 'Ngân hàng TMCP Quân đội',
    );

    test('passes validated recipient and optional payment details', () {
      final uri = bankApp.launchUri(
        bankCode: 'ICB',
        accountNumber: '123456789',
        amountVnd: 125000,
        transferDescription: 'Thanh toan hoa don',
        recipientName: 'NGUYEN AN',
      );

      expect(uri.host, 'dl.vietqr.io');
      expect(uri.path, '/pay');
      expect(uri.queryParameters, {
        'app': 'mb',
        'ba': '123456789@icb',
        'am': '125000',
        'tn': 'Thanh toan hoa don',
        'bn': 'NGUYEN AN',
      });
    });

    test('opens only the selected app when beneficiary bank is unknown', () {
      final uri = bankApp.launchUri(
        bankCode: null,
        accountNumber: '123456789',
        amountVnd: 125000,
        transferDescription: 'Transfer',
      );

      expect(uri.queryParameters, {'app': 'mb'});
    });

    test('does not put an invalid account number into the deep link', () {
      final uri = bankApp.launchUri(
        bankCode: 'ICB',
        accountNumber: '1234/../user',
        amountVnd: 125000,
      );

      expect(uri.queryParameters, {'app': 'mb'});
    });
  });
}
