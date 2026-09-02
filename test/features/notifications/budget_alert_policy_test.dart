import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:hoadon_insight/features/notifications/domain/budget_alert_policy.dart';

void main() {
  test('classifies approaching and exceeded budgets', () {
    const policy = BudgetAlertPolicy();

    expect(
      policy.evaluate(_snapshot(spent: 790, limit: 1000)).level,
      BudgetAlertLevel.none,
    );
    expect(
      policy.evaluate(_snapshot(spent: 800, limit: 1000)).level,
      BudgetAlertLevel.approaching,
    );
    final exceeded = policy.evaluate(_snapshot(spent: 1100, limit: 1000));
    expect(exceeded.level, BudgetAlertLevel.exceeded);
    expect(exceeded.deduplicationKey, '2026-08:exceeded');
  });
}

DashboardSnapshot _snapshot({required int spent, required int limit}) {
  return DashboardSnapshot(
    monthKey: '2026-08',
    totalMinor: spent,
    invoiceCount: 1,
    categoryTotals: const {},
    dailyTotals: const {},
    budgetLimitMinor: limit,
  );
}
