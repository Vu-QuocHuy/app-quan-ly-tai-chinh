import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hoadon_insight/features/payments/data/vietqr_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('installed bank apps on Android', () {
    const channel = MethodChannel('hoadoninsight/bank_apps');
    late VietQrDirectory directory;

    setUp(() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({});
      directory = VietQrDirectory(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'apps': [
                {
                  'appId': 'mb',
                  'appName': 'MB',
                  'bankName': 'MB',
                  'autofill': 1,
                },
                {
                  'appId': 'vcb',
                  'appName': 'VCB',
                  'bankName': 'VCB',
                  'autofill': 0,
                },
              ],
            }),
            200,
          ),
        ),
      );
    });

    tearDown(() {
      directory.dispose();
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'only offers installed apps, including after directory is cached',
      () async {
        var installed = ['mb'];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              expect(call.method, 'installedBankAppIds');
              return installed;
            });
        expect((await directory.loadAvailableBankApps()).map((app) => app.id), [
          'mb',
        ]);
        installed = ['vcb'];
        expect((await directory.loadAvailableBankApps()).map((app) => app.id), [
          'vcb',
        ]);
        installed = [];
        expect(await directory.loadAvailableBankApps(), isEmpty);
      },
    );

    test(
      'recognizes installed apps when the online directory is unavailable',
      () async {
        directory.dispose();
        directory = VietQrDirectory(
          client: MockClient((_) async => http.Response('', 503)),
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (_) async => ['bidv']);
        final apps = await directory.loadAvailableBankApps();
        expect(apps.map((app) => app.id), ['bidv']);
        expect(apps.single.supportsAutofill, isTrue);
      },
    );

    test('does not present all apps when native detection fails', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            throw PlatformException(code: 'unavailable');
          });
      await expectLater(
        directory.loadAvailableBankApps(),
        throwsA(isA<PlatformException>()),
      );
    });
  });
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
        'url': 'hoadoninsight://payment-return/qr-payment',
      });
    });

    test('does not silently open the home screen for an unknown bank', () {
      expect(
        () => bankApp.launchUri(
          bankCode: null,
          accountNumber: '123456789',
          amountVnd: 125000,
          transferDescription: 'Transfer',
        ),
        throwsFormatException,
      );
    });

    test('does not put an invalid account number into the deep link', () {
      expect(
        () => bankApp.launchUri(
          bankCode: 'ICB',
          accountNumber: '1234/../user',
          amountVnd: 125000,
        ),
        throwsFormatException,
      );
    });
    test('includes required memo even when the QR has none', () {
      final uri = bankApp.launchUri(
        bankCode: 'MB',
        accountNumber: '123456789',
        amountVnd: 1000,
      );
      expect(uri.queryParameters['tn'], 'Chuyen khoan');
      expect(uri.queryParameters['url'], isNotEmpty);
    });
    test('uses a web return link and preserves encoded transfer details', () {
      final returnUri = Uri.parse('https://example.com/#/qr-payment');
      final uri = bankApp.launchUri(
        bankCode: 'MB',
        accountNumber: '123456789',
        amountVnd: 1000,
        transferDescription: 'Thanh toán A&B #123',
        returnUri: returnUri,
      );
      expect(uri.queryParameters['url'], returnUri.toString());
      expect(uri.queryParameters['tn'], 'Thanh toán A&B #123');
      expect(
        () => bankApp.launchUri(
          bankCode: 'MB',
          accountNumber: '123456789',
          amountVnd: 0,
        ),
        throwsFormatException,
      );
    });
  });

  test('loads autofill capabilities and prioritizes supported apps', () async {
    SharedPreferences.setMockInitialValues({});
    final directory = VietQrDirectory(
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'apps': [
              {
                'appId': 'vcb',
                'appName': 'VCB',
                'bankName': 'VCB',
                'monthlyInstall': 300000,
                'autofill': 0,
              },
              {
                'appId': 'acb',
                'appName': 'ACB',
                'bankName': 'ACB',
                'monthlyInstall': 70000,
                'autofill': 1,
              },
            ],
          }),
          200,
        ),
      ),
    );
    addTearDown(directory.dispose);
    final apps = await directory.loadBankApps();
    expect(apps.first.id, 'acb');
    expect(apps.first.supportsAutofill, isTrue);
    expect(apps.last.supportsAutofill, isFalse);
    final cached = await directory.loadBankApps();
    expect(cached.first.supportsAutofill, isTrue);
  });
}
