import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/app/theme/app_theme.dart';
import 'package:hoadon_insight/app/theme/finance_colors.dart';
import 'package:hoadon_insight/features/dashboard/presentation/monthly_transaction_calendar.dart';
import 'package:hoadon_insight/features/income/data/income_repository.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  testWidgets('shows one signed net amount per day with semantic colors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final month = DateTime(2026, 9);
    final incomes = [
      IncomeEntry(
        id: 'income',
        amountMinor: 100000,
        source: IncomeSource.manual,
        categoryId: 'salary',
        receivedAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      ),
    ];
    DateTime? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: MonthlyTransactionCalendar(
              month: month,
              snapshot: const DashboardSnapshot(
                monthKey: '2026-09',
                totalMinor: 160000,
                invoiceCount: 2,
                categoryTotals: {},
                dailyTotals: {1: 40000, 2: 120000},
                budgetLimitMinor: 0,
              ),
              incomes: incomes,
              onSelectDay: (day) => selected = day,
            ),
          ),
        ),
      ),
    );

    final positive = tester.widget<Text>(find.text('+60K'));
    final negative = tester.widget<Text>(find.text('−120K'));
    expect(positive.style?.color, AppFinanceColors.light.income.color);
    expect(negative.style?.color, AppTheme.light().colorScheme.error);
    expect(find.bySemanticsLabel(RegExp(r'Ngày 1, dư')), findsOneWidget);
    await tester.tap(find.text('−120K'));
    expect(selected, DateTime(2026, 9, 2));
  });
}
