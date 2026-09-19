import 'package:shared_preferences/shared_preferences.dart';

class BudgetAlertPreferences {
  const BudgetAlertPreferences({this.scope});

  static const _enabledKey = 'budget_alerts_enabled';
  static const _lastNotificationKey = 'budget_alert_last_key';

  final String? scope;

  String _key(String baseKey) {
    final value = scope?.trim();
    if (value == null || value.isEmpty) return baseKey;
    if (value.length > 128 ||
        value.contains(RegExp(r'[\u0000-\u001F\u007F]'))) {
      return '$baseKey:anonymous';
    }
    return '$baseKey:$value';
  }

  Future<bool> isEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_key(_enabledKey)) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_key(_enabledKey), enabled);
  }

  Future<bool> canDeliver(String deduplicationKey) async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getString(_key(_lastNotificationKey)) !=
        deduplicationKey;
  }

  Future<void> markDelivered(String deduplicationKey) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key(_lastNotificationKey), deduplicationKey);
  }

  Future<void> clearAll({bool includeLegacy = false}) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key(_enabledKey));
    await preferences.remove(_key(_lastNotificationKey));
    if (includeLegacy && scope != null) {
      await preferences.remove(_enabledKey);
      await preferences.remove(_lastNotificationKey);
    }
  }
}
