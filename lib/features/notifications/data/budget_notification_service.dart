import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/utils/money_formatter.dart';
import '../../../core/utils/month_utils.dart';
import '../../invoices/domain/invoice_models.dart';
import '../domain/budget_alert_policy.dart';
import 'budget_alert_preferences.dart';

typedef NotificationTapHandler = void Function(String? payload);

enum BudgetNotificationResult {
  shown,
  disabled,
  notNeeded,
  duplicate,
  unsupported,
}

class BudgetNotificationService {
  BudgetNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    BudgetAlertPreferences? preferences,
    BudgetAlertPolicy? policy,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _preferences = preferences ?? const BudgetAlertPreferences(),
       _policy = policy ?? const BudgetAlertPolicy();

  static final instance = BudgetNotificationService();

  static const _channelId = 'budget_alerts';
  static const _channelName = 'Cảnh báo ngân sách';
  static const _channelDescription =
      'Thông báo khi chi tiêu chạm hoặc vượt ngân sách tháng.';
  static const _payload = '/budgets';

  final FlutterLocalNotificationsPlugin _plugin;
  final BudgetAlertPreferences _preferences;
  final BudgetAlertPolicy _policy;
  bool _initialized = false;
  NotificationTapHandler? _onTap;
  Future<String?>? _initialization;
  Future<void> _notificationLock = Future<void>.value();

  Future<String?> initialize({NotificationTapHandler? onTap}) {
    if (!_isSupportedPlatform) return Future<String?>.value();
    if (onTap != null) _onTap = onTap;
    if (_initialized) return Future<String?>.value();
    final initialization = _initialization;
    if (initialization != null) return initialization;

    final operation = _initialize();
    _initialization = operation;
    return operation.whenComplete(() {
      if (identical(_initialization, operation)) _initialization = null;
    });
  }

  Future<String?> _initialize() async {
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      final darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      final initialized = await _plugin.initialize(
        settings: InitializationSettings(android: android, iOS: darwin),
        onDidReceiveNotificationResponse: (response) {
          _onTap?.call(response.payload);
        },
      );
      if (initialized == false) {
        throw StateError('Không thể khởi tạo thông báo trên thiết bị.');
      }
      _initialized = true;

      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp != true) return null;
      return launchDetails?.notificationResponse?.payload;
    } on Object {
      _initialized = false;
      rethrow;
    }
  }

  Future<bool> requestPermission() async {
    if (!_isSupportedPlatform) return true;
    if (!_initialized) await initialize();

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    return true;
  }

  Future<void> cancelBudgetNotifications() async {
    if (!_isSupportedPlatform) return;
    if (!_initialized) await initialize();
    await _plugin.cancelAll();
  }

  Future<BudgetNotificationResult> notifyIfNeeded(DashboardSnapshot snapshot) {
    final operation = _notificationLock.then((_) => _notifyIfNeeded(snapshot));
    _notificationLock = operation.then<void>((_) {}, onError: (_, _) {});
    return operation;
  }

  Future<BudgetNotificationResult> _notifyIfNeeded(
    DashboardSnapshot snapshot,
  ) async {
    if (!_isSupportedPlatform) return BudgetNotificationResult.unsupported;
    final decision = _policy.evaluate(snapshot);
    if (!decision.shouldNotify) return BudgetNotificationResult.notNeeded;
    if (!await _preferences.isEnabled()) {
      return BudgetNotificationResult.disabled;
    }
    if (!_initialized) await initialize();
    if (!await _preferences.canDeliver(decision.deduplicationKey)) {
      return BudgetNotificationResult.duplicate;
    }

    final exceeded = decision.level == BudgetAlertLevel.exceeded;
    final title = exceeded
        ? 'Đã vượt ngân sách tháng'
        : 'Ngân sách sắp chạm hạn mức';
    final body = exceeded
        ? '${MonthUtils.label(_monthFromKey(decision.monthKey))}: đã vượt '
              '${MoneyFormatter.format(decision.spentMinor - decision.limitMinor)}. '
              '${MoneyFormatter.format(decision.spentMinor)} / '
              '${MoneyFormatter.format(decision.limitMinor)}.'
        : '${MonthUtils.label(_monthFromKey(decision.monthKey))}: đã dùng '
              '${(decision.spentMinor / decision.limitMinor * 100).round()}% '
              '(${MoneyFormatter.format(decision.spentMinor)} / '
              '${MoneyFormatter.format(decision.limitMinor)}).';

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        threadIdentifier: _channelId,
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
    await _plugin.show(
      id: _notificationId(decision),
      title: title,
      body: body,
      notificationDetails: notificationDetails,
      payload: _payload,
    );
    await _preferences.markDelivered(decision.deduplicationKey);
    return BudgetNotificationResult.shown;
  }

  int _notificationId(BudgetAlertDecision decision) {
    final scope = _preferences.scope?.trim() ?? 'anonymous';
    final value = _stableHash(
      '$scope:${decision.monthKey}:${decision.level.name}',
    );
    return value == 0 ? 1 : value;
  }

  int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  bool get _isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  DateTime _monthFromKey(String monthKey) {
    final parts = monthKey.split('-');
    if (parts.length != 2) return DateTime.now();
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null || month < 1 || month > 12) {
      return DateTime.now();
    }
    return DateTime(year, month);
  }
}
