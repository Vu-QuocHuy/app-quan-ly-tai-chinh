import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/config/feature_flags.dart';
import '../../core/database/app_database.dart';
import '../../core/database/local_database_scope.dart';
import '../../core/security/supabase_bootstrap.dart';
import '../../core/utils/month_utils.dart';
import '../../features/export/data/supabase_backup_provider.dart';
import '../../features/invoices/data/drift_invoice_repository.dart';
import '../../features/invoices/domain/invoice_models.dart';
import '../../features/notifications/data/budget_alert_preferences.dart';
import '../../features/notifications/data/budget_notification_service.dart';
import '../../features/sync/application/sync_coordinator.dart';
import '../../features/sync/application/sync_engine.dart';
import '../../features/sync/application/sync_pull_coordinator.dart';
import '../../features/sync/data/drift_sync_cursor_store.dart';
import '../../features/sync/data/drift_sync_outbox_store.dart';
import '../../features/sync/data/supabase_sync_gateway.dart';

const _taskName = 'finance_background_maintenance';
const _uniqueTaskName = 'finance_background_maintenance_periodic';
const _maxTaskDuration = Duration(seconds: 25);

class BackgroundTaskScheduler {
  static Future<void>? _initialization;

  static Future<void> initialize() {
    if (!_isSupported) return Future<void>.value();
    final initialization = _initialization;
    if (initialization != null) return initialization;
    final operation = _initialize();
    _initialization = operation;
    return operation;
  }

  static Future<void> _initialize() async {
    try {
      await Workmanager().initialize(backgroundTaskDispatcher);
      await Workmanager().registerPeriodicTask(
        _uniqueTaskName,
        _taskName,
        // Android accepts 15 minutes as the shortest periodic interval.
        // iOS may still defer execution according to its background policy.
        frequency: const Duration(minutes: 15),
        initialDelay: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresStorageNotLow: true,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 15),
        tag: _taskName,
      );
    } on Object {
      _initialization = null;
    }
  }

  static bool get _isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
}

@pragma('vm:entry-point')
void backgroundTaskDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != _taskName && task != Workmanager.iOSBackgroundTask) {
      return true;
    }
    return _runBackgroundMaintenance().timeout(
      _maxTaskDuration,
      onTimeout: () => false,
    );
  });
}

Future<bool> _runBackgroundMaintenance() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  AppDatabase? database;
  String? userId;
  try {
    final supabaseInitialized = await SupabaseBootstrap.initialize();
    final client = SupabaseBootstrap.clientOrNull;
    userId = client?.auth.currentUser?.id;
    await LocalDatabaseScope.initialize(userId: userId);
    final cloudConfigured = supabaseInitialized && client != null;
    if (cloudConfigured && userId == null) return true;
    database = AppDatabase(
      null,
      LocalDatabaseScope.databaseName(
        userId: userId,
        cloudConfigured: cloudConfigured,
      ),
    );
    final repository = DriftInvoiceRepository(database);
    var maintenanceSucceeded = true;

    if (cloudConfigured && userId != null) {
      final flags = await RemoteConfigService(client).load(userId: userId);
      if (flags.cloudSync) {
        try {
          final outbox = DriftSyncOutboxStore(database);
          final cursors = DriftSyncCursorStore(database);
          final gateway = SupabaseSyncGateway(client);
          final identity = SupabaseSyncIdentityProvider(client);
          final syncPull = SyncPullCoordinator(
            repository: repository,
            cursors: cursors,
            gateway: gateway,
          );
          final referencePulls = [
            for (final aggregateType in const [
              'category',
              'budget',
              'merchant_rule',
            ])
              SyncPullCoordinator(
                repository: repository,
                cursors: cursors,
                gateway: gateway,
                aggregateType: aggregateType,
              ),
          ];
          final sync = SyncCoordinator(
            upload: SyncEngine(
              store: outbox,
              identity: identity,
              gateway: gateway,
            ),
            identity: identity,
            download: syncPull,
            referenceDownloads: referencePulls,
          );
          final summary = await sync.runOnce();
          if (summary.upload.failed > 0) maintenanceSucceeded = false;
        } on Object {
          maintenanceSucceeded = false;
        }
      }
      await _tryPruneBackups(client);
    }

    final snapshot = await repository
        .watchDashboard(MonthUtils.key(DateTime.now()))
        .first;
    await _tryDeliverNotification(snapshot, userId: userId);
    return maintenanceSucceeded;
  } on Object {
    return false;
  } finally {
    await _closeDatabase(database);
  }
}

Future<void> _tryPruneBackups(SupabaseClient client) async {
  try {
    await SupabaseBackupProvider(client).prune();
  } on Object {
    return;
  }
}

Future<void> _tryDeliverNotification(
  DashboardSnapshot snapshot, {
  String? userId,
}) async {
  try {
    final notifications = BudgetNotificationService(
      preferences: BudgetAlertPreferences(scope: userId),
    );
    await notifications.initialize();
    await notifications.notifyIfNeeded(snapshot);
  } on Object {
    return;
  }
}

Future<void> _closeDatabase(AppDatabase? database) async {
  if (database == null) return;
  try {
    await database.close();
  } on Object {
    return;
  }
}
