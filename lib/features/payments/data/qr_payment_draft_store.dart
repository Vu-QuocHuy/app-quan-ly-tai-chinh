import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/qr_payment_draft.dart';

class QrPaymentDraftStore {
  QrPaymentDraftStore({String? scope}) : _scope = _normalizeScope(scope);

  final String _scope;

  String get _draftKey => 'payments.qr.pending.v2.$_scope';
  String get _lastBankAppKey => 'payments.qr.last_bank_app.v2.$_scope';

  Future<QrPaymentDraft?> readDraft() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_draftKey);
    if (value == null) return null;
    try {
      final json = jsonDecode(value);
      if (json is! Map) throw const FormatException();
      return QrPaymentDraft.fromJson(Map<String, dynamic>.from(json));
    } on Object {
      await preferences.remove(_draftKey);
      return null;
    }
  }

  Future<void> writeDraft(QrPaymentDraft draft) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_draftKey, jsonEncode(draft.toJson()));
  }

  Future<void> clearDraft() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_draftKey);
  }

  Future<String?> readLastBankAppId() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_lastBankAppKey);
  }

  Future<void> writeLastBankAppId(String appId) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_lastBankAppKey, appId);
  }

  static String _normalizeScope(String? value) {
    final scope = value?.trim().toLowerCase();
    if (scope == null ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
        ).hasMatch(scope)) {
      return 'signed_out';
    }
    return scope.replaceAll('-', '');
  }
}
