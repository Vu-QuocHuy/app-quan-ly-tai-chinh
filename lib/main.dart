import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/router/app_router.dart';
import 'core/background/background_task_scheduler.dart';
import 'core/database/local_database_scope.dart';
import 'core/monitoring/app_error_reporter.dart';
import 'core/security/supabase_bootstrap.dart';
import 'features/notifications/data/budget_notification_service.dart';

Future<void> main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppErrorReporter.instance.install();
  return runZonedGuarded(_bootstrap, (error, stackTrace) {
        unawaited(
          AppErrorReporter.instance.report(
            error,
            stackTrace,
            source: 'zone',
            fatal: true,
          ),
        );
      }) ??
      Future<void>.value();
}

Future<void> _bootstrap() async {
  await SupabaseBootstrap.initialize();
  _configureErrorMonitoring();
  await LocalDatabaseScope.initialize(
    userId: SupabaseBootstrap.clientOrNull?.auth.currentUser?.id,
  );
  await BackgroundTaskScheduler.initialize();
  authRouterRefresh.attach(SupabaseBootstrap.clientOrNull);
  final launchPayload = await BudgetNotificationService.instance.initialize(
    onTap: _handleNotificationTap,
  );
  runApp(const ProviderScope(child: HoaDonInsightApp()));
  if (launchPayload != null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleNotificationTap(launchPayload);
    });
  }
}

void _configureErrorMonitoring() {
  final client = SupabaseBootstrap.clientOrNull;
  if (client == null) return;
  AppErrorReporter.instance.configure(
    sink: (report) async {
      try {
        await client.rpc(
          'record_client_error',
          params: {
            'p_source': report.source,
            'p_error_type': report.errorType,
            'p_message': report.message,
            'p_stack_trace': report.stackTrace,
            'p_fatal': report.fatal,
          },
        );
      } on Object {
        return;
      }
    },
  );
}

void _handleNotificationTap(String? payload) {
  if (payload == '/budgets') appRouter.go('/budgets');
}
