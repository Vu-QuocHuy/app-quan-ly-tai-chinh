import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:hoadon_insight/features/notifications/domain/budget_alert_policy.dart';

void main() {
  const policy = BudgetAlertPolicy();

  test('classifies approaching and exceeded per category', () {
    expect(
      policy.evaluate(_snapshot([_budget('food', spent: 790)])).level,
      BudgetAlertLevel.none,
    );
    expect(
      policy.evaluate(_snapshot([_budget('food', spent: 800)])).level,
      BudgetAlertLevel.approaching,
    );
    final exceeded = policy.evaluate(
      _snapshot([
        _budget('food', spent: 1100),
        _budget('transport', spent: 1500),
        _budget('home', spent: 900),
      ]),
    );
    expect(exceeded.level, BudgetAlertLevel.exceeded);
    expect(exceeded.categories.map((item) => item.categoryId), [
      'transport',
      'food',
    ]);
    expect(exceeded.deduplicationKey, '2026-08:exceeded:food,transport');
  });

  test('ignores the monthly total when no category is over its limit', () {
    final decision = policy.evaluate(
      _snapshot(
        [_budget('food', spent: 500)],
        // Tổng chi lớn do danh mục không giới hạn, tổng hạn mức nhỏ.
        totalMinor: 50000,
        budgetLimitMinor: 1000,
      ),
    );
    expect(decision.level, BudgetAlertLevel.none);
  });
}

CategoryBudgetStatus _budget(String id, {required int spent}) {
  return CategoryBudgetStatus(
    categoryId: id,
    categoryName: id,
    limitMinor: 1000,
    spentMinor: spent,
  );
}

DashboardSnapshot _snapshot(
  List<CategoryBudgetStatus> budgets, {
  int totalMinor = 0,
  int budgetLimitMinor = 0,
}) {
  return DashboardSnapshot(
    monthKey: '2026-08',
    totalMinor: totalMinor,
    invoiceCount: 1,
    categoryTotals: const {},
    dailyTotals: const {},
    budgetLimitMinor: budgetLimitMinor,
    categoryBudgets: budgets,
  );
}
