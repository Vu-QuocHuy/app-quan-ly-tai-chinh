import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/app/theme/app_theme.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/budgets/presentation/budget_screen.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:hoadon_insight/shared/widgets/category_avatar.dart';

void main() {
  testWidgets('colored categories and expandable actual category overages', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriesProvider.overrideWith(
            (ref) => Stream.value(const [
              CategoryEntity(
                id: 'food',
                name: 'Ăn uống',
                iconName: 'restaurant',
                colorValue: 0xFF123D32,
              ),
            ]),
          ),
          budgetsProvider.overrideWith(
            (ref) => Stream.value(const [
              BudgetEntity(
                id: 'b',
                monthKey: '2026-09',
                categoryId: 'food',
                limitMinor: 100000,
              ),
            ]),
          ),
          dashboardProvider.overrideWith(
            (ref) => Stream.value(
              const DashboardSnapshot(
                monthKey: '2026-09',
                totalMinor: 150000,
                invoiceCount: 1,
                categoryTotals: {'food': 150000},
                dailyTotals: {1: 150000},
                budgetLimitMinor: 100000,
                categoryBudgets: [
                  CategoryBudgetStatus(
                    categoryId: 'food',
                    categoryName: 'Ăn uống',
                    limitMinor: 100000,
                    spentMinor: 150000,
                  ),
                ],
              ),
            ),
          ),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const BudgetScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CategoryAvatar), findsOneWidget);
    expect(find.text('Danh mục vượt hạn mức'), findsNothing);
    await tester.tap(find.byTooltip('Xem danh mục vượt hạn mức'));
    await tester.pumpAndSettle();
    expect(find.text('Danh mục vượt hạn mức'), findsOneWidget);
    expect(find.textContaining('Vượt 50.000'), findsWidgets);
    expect(find.byType(CategoryAvatar), findsNWidgets(2));
    await tester.tap(find.byTooltip('Ẩn danh mục vượt hạn mức'));
    await tester.pumpAndSettle();
    expect(find.text('Danh mục vượt hạn mức'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
