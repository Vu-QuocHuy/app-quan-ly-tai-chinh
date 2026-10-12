import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hoadon_insight/app/theme/app_theme.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/budgets/presentation/budget_screen.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  testWidgets('closing the budget editor does not dispose its field early', (
    tester,
  ) async {
    const category = CategoryEntity(
      id: 'transport',
      name: 'Di chuyển',
      iconName: 'directions_car',
      colorValue: 0xff16806a,
    );
    const snapshot = DashboardSnapshot(
      monthKey: '2026-10',
      totalMinor: 0,
      invoiceCount: 0,
      categoryTotals: {},
      dailyTotals: {},
      budgetLimitMinor: 0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selectedMonthProvider.overrideWith((ref) => DateTime(2026, 10)),
          categoriesProvider.overrideWith((ref) => Stream.value([category])),
          budgetsProvider.overrideWith(
            (ref) => Stream.value(const <BudgetEntity>[]),
          ),
          dashboardProvider.overrideWith((ref) => Stream.value(snapshot)),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const BudgetScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sửa ngân sách Di chuyển'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('retries loading categories after a budget screen error', (
    tester,
  ) async {
    const category = CategoryEntity(
      id: 'transport',
      name: 'Di chuyển',
      iconName: 'directions_car',
      colorValue: 0xff16806a,
    );
    const snapshot = DashboardSnapshot(
      monthKey: '2026-10',
      totalMinor: 0,
      invoiceCount: 0,
      categoryTotals: {},
      dailyTotals: {},
      budgetLimitMinor: 0,
    );
    var categoryLoads = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selectedMonthProvider.overrideWith((ref) => DateTime(2026, 10)),
          categoriesProvider.overrideWith((ref) {
            categoryLoads++;
            return categoryLoads == 1
                ? Stream.error(StateError('offline'))
                : Stream.value([category]);
          }),
          budgetsProvider.overrideWith(
            (ref) => Stream.value(const <BudgetEntity>[]),
          ),
          dashboardProvider.overrideWith((ref) => Stream.value(snapshot)),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const BudgetScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Thử lại'), findsOneWidget);
    await tester.tap(find.text('Thử lại'));
    await tester.pumpAndSettle();

    expect(find.text('Di chuyển'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
