import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/router/app_router.dart';
import 'core/security/supabase_bootstrap.dart';
import 'features/notifications/data/budget_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseBootstrap.initialize();
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

void _handleNotificationTap(String? payload) {
  if (payload == '/budgets') appRouter.go('/budgets');
}
