import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Stores user feedback for anomaly suggestions on the device.
///
/// Feedback is intentionally local: it is a personal presentation preference,
/// not financial data that needs to be synchronized between devices.
class AnomalyFeedbackStore {
  const AnomalyFeedbackStore({this.maxEntries = 200});

  static const storageKey = 'insights.anomaly_feedback.v1';

  final int maxEntries;

  Future<Set<String>> loadDismissedIds() async {
    return (await _loadOrdered()).toSet();
  }

  Future<List<String>> _loadOrdered() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(storageKey);
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>[];
      return decoded.whereType<String>().where((id) => id.isNotEmpty).toList();
    } on Object {
      return <String>[];
    }
  }

  Future<void> dismiss(String invoiceId) async {
    final ids = await _loadOrdered();
    ids
      ..remove(invoiceId)
      ..insert(0, invoiceId);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      storageKey,
      jsonEncode(ids.take(maxEntries).toList()),
    );
  }

  Future<void> restore(String invoiceId) async {
    final ids = await _loadOrdered()
      ..remove(invoiceId);
    final preferences = await SharedPreferences.getInstance();
    if (ids.isEmpty) {
      await preferences.remove(storageKey);
    } else {
      await preferences.setString(storageKey, jsonEncode(ids.toList()));
    }
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(storageKey);
  }
}
