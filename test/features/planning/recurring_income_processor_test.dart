import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/database/app_database.dart';
import 'package:hoadon_insight/features/income/data/income_repository.dart';
import 'package:hoadon_insight/features/planning/application/recurring_income_processor.dart';
import 'package:hoadon_insight/features/planning/data/plan_repository.dart';
import 'package:hoadon_insight/features/planning/domain/plan_models.dart';

void main() {
  late AppDatabase database;
  late PlanRepository plans;
  late IncomeRepository incomes;
  late RecurringIncomeProcessor processor;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    plans = PlanRepository(database);
    incomes = IncomeRepository(database);
    processor = RecurringIncomeProcessor(plans: plans, incomes: incomes);
  });

  tearDown(() => database.close());

  test(
    'records due months once and clamps short months to the anchor day',
    () async {
      await database.customStatement('''
        INSERT INTO categories (id, name, icon_name, color_value, kind)
        VALUES ('income_salary', 'Lương', 'payments', 4280640491, 'income')
      ''');
      await plans.save(
        RecurringIncome(
          id: 'monthly-salary',
          title: 'Lương',
          amountMinor: 30000000,
          categoryId: 'income_salary',
          anchorDate: DateTime(2026, 1, 31),
          nextDueDate: DateTime(2026, 1, 31),
          updatedAt: DateTime(2026, 1, 1),
        ),
      );

      expect(await processor.runDue(now: DateTime(2026, 3, 5)), 2);

      final entries = await incomes.getAll()
        ..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
      expect(entries.map((entry) => entry.receivedAt), [
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
      ]);
      expect(entries.map((entry) => entry.source), [
        IncomeSource.fixed,
        IncomeSource.fixed,
      ]);

      final savedPlan =
          await plans.findById('monthly-salary') as RecurringIncome;
      expect(savedPlan.nextDueDate, DateTime(2026, 3, 31));

      await plans.save(
        savedPlan.copyWith(
          nextDueDate: DateTime(2026, 1, 31),
          updatedAt: DateTime(2026, 3, 5),
        ),
      );
      expect(await processor.runDue(now: DateTime(2026, 3, 5)), 0);
      expect((await incomes.getAll()).length, 2);
    },
  );

  test('recurring income survives sync payload round-trip', () {
    final income = RecurringIncome(
      id: 'monthly-salary',
      title: 'Lương',
      amountMinor: 30000000,
      categoryId: 'income_salary',
      anchorDate: DateTime(2026, 1, 31),
      nextDueDate: DateTime(2026, 2, 28),
      updatedAt: DateTime(2026, 2, 1),
    );

    final restored = PlanItem.fromPayload(
      Map<String, dynamic>.from(income.toPayload()),
    );

    expect(restored, isA<RecurringIncome>());
    expect(restored.toPayload(), income.toPayload());
  });
}
