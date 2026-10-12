import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:hoadon_insight/features/planning/data/plan_repository.dart';
import 'package:hoadon_insight/features/planning/domain/plan_models.dart';
import 'package:hoadon_insight/features/planning/presentation/plan_screen.dart';

void main() {
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
          incomeCategoriesProvider.overrideWith(
            (ref) => Stream.value(categories),
          ),
        ],
        child: const MaterialApp(home: PlanScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thêm khoản thu cố định'));
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
