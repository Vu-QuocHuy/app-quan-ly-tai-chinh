import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class VietQrBankApp {
  const VietQrBankApp({
    required this.id,
    required this.name,
    required this.bankName,
    this.monthlyInstalls = 0,
  });

  final String id;
  final String name;
  final String bankName;
  final int monthlyInstalls;

  Uri launchUri({
    required String? bankCode,
    required String accountNumber,
    int? amountVnd,
    String? transferDescription,
    String? recipientName,
  }) {
    final normalizedBankCode = bankCode?.trim().toLowerCase();
    final canPrefillRecipient =
        normalizedBankCode != null &&
        RegExp(r'^[a-z0-9_-]{1,32}$').hasMatch(normalizedBankCode) &&
        RegExp(r'^[A-Za-z0-9]{1,34}$').hasMatch(accountNumber.trim());
    return Uri.https('dl.vietqr.io', '/pay', {
      'app': id,
      if (canPrefillRecipient)
        'ba': '${accountNumber.trim()}@$normalizedBankCode',
      if (canPrefillRecipient && amountVnd != null && amountVnd > 0)
        'am': '$amountVnd',
      if (canPrefillRecipient && transferDescription?.trim().isNotEmpty == true)
        'tn': transferDescription!.trim(),
      if (canPrefillRecipient && recipientName?.trim().isNotEmpty == true)
        'bn': recipientName!.trim(),
    });
  }
}

@immutable
class VietQrBank {
  const VietQrBank({
    required this.bin,
    required this.code,
    required this.name,
    required this.shortName,
  });

  final String bin;
  final String code;
  final String name;
  final String shortName;
}

class VietQrDirectory {
  VietQrDirectory({http.Client? client}) : _client = client ?? http.Client();

  static const _cacheTtl = Duration(hours: 24);
  static const _androidAppsCacheKey = 'payments.qr.bank_apps.android.v1';
  static const _iosAppsCacheKey = 'payments.qr.bank_apps.ios.v1';
  static const _banksCacheKey = 'payments.qr.banks.v1';
  final http.Client _client;

  String get _appsCacheKey => defaultTargetPlatform == TargetPlatform.iOS
      ? _iosAppsCacheKey
      : _androidAppsCacheKey;

  Uri get _appsUri => Uri.https(
    'api.vietqr.io',
    defaultTargetPlatform == TargetPlatform.iOS
        ? '/v2/ios-app-deeplinks'
        : '/v2/android-app-deeplinks',
  );

  void dispose() => _client.close();

  Future<List<VietQrBankApp>> loadBankApps() async {
    final cached = await _readCache(_appsCacheKey, _parseApps);
    if (cached != null && cached.isFresh) {
      return cached.value;
    }
    try {
      final response = await _client
          .get(_appsUri)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw const FormatException();
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['apps'] is! List) {
        throw const FormatException();
      }
      final apps =
          (decoded['apps'] as List)
              .map(_parseApp)
              .whereType<VietQrBankApp>()
              .toList(growable: false)
            ..sort(
              (left, right) =>
                  right.monthlyInstalls.compareTo(left.monthlyInstalls),
            );
      if (apps.isEmpty) throw const FormatException();
      await _writeCache(_appsCacheKey, response.body);
      return apps;
    } on Object {
      return cached?.value ?? _fallbackApps;
    }
  }

  Future<List<VietQrBank>> loadBanks() async {
    final cached = await _readCache(_banksCacheKey, _parseBanks);
    if (cached != null && cached.isFresh) {
      return cached.value;
    }
    try {
      final response = await _client
          .get(Uri.https('api.vietqr.io', '/v2/banks'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw const FormatException();
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['data'] is! List) {
        throw const FormatException();
      }
      final banks = (decoded['data'] as List)
          .map(_parseBank)
          .whereType<VietQrBank>()
          .toList(growable: false);
      if (banks.isEmpty) throw const FormatException();
      await _writeCache(_banksCacheKey, response.body);
      return banks;
    } on Object {
      return cached?.value ?? _fallbackBanks;
    }
  }

  Future<_Cache<List<T>>?> _readCache<T>(
    String key,
    List<T> Function(Object?) parse,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final body = preferences.getString(key);
    if (body == null) return null;
    try {
      final decoded = jsonDecode(body);
      final items = parse(decoded);
      final fetchedAt = preferences.getInt('$key.fetched_at') ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - fetchedAt;
      return _Cache(items, isFresh: age >= 0 && age < _cacheTtl.inMilliseconds);
    } on Object {
      await preferences.remove(key);
      await preferences.remove('$key.fetched_at');
      return null;
    }
  }

  Future<void> _writeCache(String key, String body) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, body);
    await preferences.setInt(
      '$key.fetched_at',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static List<VietQrBankApp> _parseApps(Object? decoded) {
    if (decoded is! Map || decoded['apps'] is! List) {
      throw const FormatException();
    }
    return (decoded['apps'] as List)
        .map(_parseApp)
        .whereType<VietQrBankApp>()
        .toList(growable: false);
  }

  static VietQrBankApp? _parseApp(Object? value) {
    if (value is! Map) return null;
    final id = value['appId'];
    final name = value['appName'];
    final bankName = value['bankName'];
    if (id is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,40}$').hasMatch(id) ||
        name is! String ||
        name.trim().isEmpty ||
        bankName is! String) {
      return null;
    }
    final installs = value['monthlyInstall'];
    return VietQrBankApp(
      id: id,
      name: name.trim(),
      bankName: bankName.trim(),
      monthlyInstalls: installs is num && installs.isFinite
          ? installs.toInt().clamp(0, 1 << 31).toInt()
          : 0,
    );
  }

  static List<VietQrBank> _parseBanks(Object? decoded) {
    if (decoded is! Map || decoded['data'] is! List) {
      throw const FormatException();
    }
    return (decoded['data'] as List)
        .map(_parseBank)
        .whereType<VietQrBank>()
        .toList(growable: false);
  }

  static VietQrBank? _parseBank(Object? value) {
    if (value is! Map) return null;
    final bin = value['bin'];
    final code = value['code'];
    final name = value['name'];
    final shortName = value['shortName'] ?? value['short_name'];
    if (bin is! String ||
        !RegExp(r'^\d{6}$').hasMatch(bin) ||
        code is! String ||
        name is! String ||
        shortName is! String ||
        shortName.trim().isEmpty) {
      return null;
    }
    return VietQrBank(
      bin: bin,
      code: code,
      name: name,
      shortName: shortName.trim(),
    );
  }

  static const _fallbackApps = [
    VietQrBankApp(
      id: 'vcb',
      name: 'Vietcombank',
      bankName: 'Ngân hàng TMCP Ngoại thương Việt Nam',
    ),
    VietQrBankApp(
      id: 'mb',
      name: 'MB Bank',
      bankName: 'Ngân hàng TMCP Quân đội',
    ),
  ];

  static const _fallbackBanks = [
    VietQrBank(
      bin: '970405',
      code: 'VBA',
      name: 'Ngân hàng Nông nghiệp và Phát triển Nông thôn Việt Nam',
      shortName: 'Agribank',
    ),
    VietQrBank(
      bin: '970416',
      code: 'ACB',
      name: 'Ngân hàng TMCP Á Châu',
      shortName: 'ACB',
    ),
    VietQrBank(
      bin: '970418',
      code: 'BIDV',
      name: 'Ngân hàng TMCP Đầu tư và Phát triển Việt Nam',
      shortName: 'BIDV',
    ),
    VietQrBank(
      bin: '970422',
      code: 'MB',
      name: 'Ngân hàng TMCP Quân đội',
      shortName: 'MB Bank',
    ),
    VietQrBank(
      bin: '970415',
      code: 'ICB',
      name: 'Ngân hàng TMCP Công thương Việt Nam',
      shortName: 'VietinBank',
    ),
    VietQrBank(
      bin: '970436',
      code: 'VCB',
      name: 'Ngân hàng TMCP Ngoại thương Việt Nam',
      shortName: 'Vietcombank',
    ),
  ];
}

class _Cache<T> {
  const _Cache(this.value, {required this.isFresh});

  final T value;
  final bool isFresh;
}
