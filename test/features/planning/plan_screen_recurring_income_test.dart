import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:hoadon_insight/features/planning/data/plan_repository.dart';
import 'package:hoadon_insight/features/planning/domain/plan_models.dart';
import 'package:hoadon_insight/features/planning/presentation/plan_screen.dart';

void main() {
  testWidgets(
    'editing a bill keeps its category while categories are unavailable',
    (tester) async {
      final repository = _FakePlanRepository();
      final due = DateTime(2026, 10, 20);
      final bill = RecurringBill(
        id: 'rent',
        title: 'Tiền nhà',
        amountMinor: 5000000,
        frequency: BillFrequency.monthly,
        anchorDate: due,
        nextDueDate: due,
        categoryId: 'housing',
        updatedAt: due,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            planRepositoryProvider.overrideWithValue(repository),
            plansProvider.overrideWith((ref) => Stream.value([bill])),
            categoriesProvider.overrideWith((ref) => Stream.value(const [])),
            incomeCategoriesProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
          ],
          child: const MaterialApp(home: PlanScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tiền nhà'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sửa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      expect((repository.saved as RecurringBill).categoryId, 'housing');
    },
  );

  testWidgets(
    'shows income and expense sections and creates a recurring bill',
    (tester) async {
      final repository = _FakePlanRepository();
      const expenseCategories = [
        CategoryEntity(
          id: 'housing',
          name: 'Nhà ở',
          iconName: 'home',
          colorValue: 0xFF2563EB,
        ),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            planRepositoryProvider.overrideWithValue(repository),
            plansProvider.overrideWith((ref) => Stream.value(const [])),
            categoriesProvider.overrideWith(
              (ref) => Stream.value(expenseCategories),
            ),
            incomeCategoriesProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
          ],
          child: const MaterialApp(home: PlanScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Thêm khoản chi cố định'), findsNothing);
      expect(find.text('Thêm khoản thu cố định'), findsNothing);
      expect(find.text('Thêm mục tiêu'), findsNothing);
      await tester.tap(find.byTooltip('Thêm khoản định kỳ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Khoản chi định kỳ'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Tiền nhà');
      await tester.enterText(find.byType(TextField).at(1), '5000000');
      await tester.tap(find.byKey(const ValueKey('recurring-bill-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhà ở').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      final saved = repository.saved as RecurringBill;
      expect(saved.title, 'Tiền nhà');
      expect(saved.amountMinor, 5000000);
      expect(saved.frequency, BillFrequency.monthly);
      expect(saved.categoryId, 'housing');
    },
  );

  testWidgets('creates a monthly income with a selected category', (
    tester,
  ) async {
    final repository = _FakePlanRepository();
    const categories = [
      CategoryEntity(
        id: 'income_salary',
        name: 'Lương',
        iconName: 'category',
        colorValue: 0xFF2563EB,
        kind: CategoryKind.income,
      ),
      CategoryEntity(
        id: 'income_bonus',
        name: 'Thưởng',
        iconName: 'category',
        colorValue: 0xFF0F766E,
        kind: CategoryKind.income,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          planRepositoryProvider.overrideWithValue(repository),
          plansProvider.overrideWith((ref) => Stream.value(const [])),
          categoriesProvider.overrideWith((ref) => Stream.value(const [])),
          incomeCategoriesProvider.overrideWith(
            (ref) => Stream.value(categories),
          ),
        ],
        child: const MaterialApp(home: PlanScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Thêm khoản định kỳ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Khoản thu định kỳ'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Lương tháng');
    await tester.enterText(find.byType(TextField).at(1), '30000000');
    await tester.tap(find.byKey(const ValueKey('recurring-income-category')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thưởng').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();

    final saved = repository.saved as RecurringIncome;
    expect(saved.title, 'Lương tháng');
    expect(saved.amountMinor, 30000000);
    expect(saved.categoryId, 'income_bonus');
    expect(saved.nextDueDate, saved.anchorDate);
  });
}

class _FakePlanRepository extends Fake implements PlanRepository {
  PlanItem? saved;

  @override
  Future<void> save(PlanItem item) async => saved = item;
}
