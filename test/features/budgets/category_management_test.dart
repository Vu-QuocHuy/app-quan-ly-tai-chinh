import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/budgets/presentation/category_management.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_repository.dart';

void main() {
  testWidgets('creates a category with an optional selected-month budget', (
    tester,
  ) async {
    final repository = _FakeInvoiceRepository();
    const existingCategory = CategoryEntity(
      id: 'food',
      name: 'Ăn uống',
      iconName: 'restaurant',
      colorValue: 0xFF2563EB,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          invoiceRepositoryProvider.overrideWithValue(repository),
          categoriesProvider.overrideWith(
            (ref) => Stream.value(const [existingCategory]),
          ),
          selectedMonthProvider.overrideWith((ref) => DateTime(2026, 8)),
        ],
        child: const MaterialApp(home: CategoryManagementScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Thêm danh mục'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('category-budget-field')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('category-name-field')),
      'Cà phê',
    );
    await tester.enterText(
      find.byKey(const ValueKey('category-budget-field')),
      '500000',
    );
    await tester.tap(find.text('Lưu danh mục'));
    await tester.pumpAndSettle();

    expect(repository.savedCategories, hasLength(1));
    expect(repository.savedCategories.single.name, 'Cà phê');
    expect(repository.savedBudgets, hasLength(1));
    expect(repository.savedBudgets.single.monthKey, '2026-08');
    expect(repository.savedBudgets.single.categoryId, startsWith('custom-'));
    expect(
      repository.savedBudgets.single.categoryId,
      repository.savedCategories.single.id,
    );
    expect(repository.savedBudgets.single.limitMinor, 500000);
  });

  testWidgets('confirms before discarding edited category data', (
    tester,
  ) async {
    const existingCategory = CategoryEntity(
      id: 'food',
      name: 'Ăn uống',
      iconName: 'restaurant',
      colorValue: 0xFF2563EB,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriesProvider.overrideWith(
            (ref) => Stream.value(const [existingCategory]),
          ),
          selectedMonthProvider.overrideWith((ref) => DateTime(2026, 8)),
        ],
        child: const MaterialApp(home: CategoryManagementScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ăn uống'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('category-name-field')),
      'Ăn uống ngoài nhà',
    );
    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(find.text('Bỏ thay đổi?'), findsOneWidget);

    await tester.tap(find.text('Tiếp tục chỉnh sửa'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('category-name-field')), findsOneWidget);

    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bỏ thay đổi'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('category-name-field')), findsNothing);
  });
}

class _FakeInvoiceRepository extends Fake implements InvoiceRepository {
  final savedCategories = <CategoryEntity>[];
  final savedBudgets = <BudgetEntity>[];

  @override
  Future<void> saveCategory(CategoryEntity category) async {
    savedCategories.add(category);
  }

  @override
  Future<void> saveBudget(BudgetEntity budget) async {
    savedBudgets.add(budget);
  }
}
