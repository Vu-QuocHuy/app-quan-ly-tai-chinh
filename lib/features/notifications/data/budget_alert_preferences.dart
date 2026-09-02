import 'package:shared_preferences/shared_preferences.dart';

class BudgetAlertPreferences {
  const BudgetAlertPreferences();

  static const _enabledKey = 'budget_alerts_enabled';
  static const _lastNotificationKey = 'budget_alert_last_key';

  Future<bool> isEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_enabledKey) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, enabled);
  }

  Future<bool> shouldDeliver(String deduplicationKey) async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getString(_lastNotificationKey) == deduplicationKey) {
      return false;
    }
    await preferences.setString(_lastNotificationKey, deduplicationKey);
    return true;
  }
}
