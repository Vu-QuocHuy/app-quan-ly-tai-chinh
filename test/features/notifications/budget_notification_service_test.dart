import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:hoadon_insight/features/notifications/data/budget_notification_service.dart';

void main() {
  test(
    'does not invoke native notifications on unsupported platforms',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final service = BudgetNotificationService();
      const snapshot = DashboardSnapshot(
        monthKey: '2026-09',
        totalMinor: 900000,
        invoiceCount: 2,
        categoryTotals: {},
        dailyTotals: {},
        budgetLimitMinor: 1000000,
      );

      expect(
        await service.notifyIfNeeded(snapshot),
        BudgetNotificationResult.unsupported,
      );
      await service.cancelBudgetNotifications();
    },
  );
}
