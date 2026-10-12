import 'package:uuid/uuid.dart';

import '../../income/data/income_repository.dart';
import '../data/plan_repository.dart';
import '../domain/plan_models.dart';

class RecurringIncomeProcessor {
  const RecurringIncomeProcessor({
    required PlanRepository plans,
    required IncomeRepository incomes,
  }) : _plans = plans,
       _incomes = incomes;

  final PlanRepository _plans;
  final IncomeRepository _incomes;

  static const _maxOccurrencesPerRun = 120;
  static const _uuid = Uuid();

  Future<int> runDue({DateTime? now}) async {
    final timestamp = now ?? DateTime.now();
    final today = DateTime(timestamp.year, timestamp.month, timestamp.day);
    var created = 0;

    for (final item in await _plans.getAll()) {
      if (item is! RecurringIncome) continue;
      var current = item;
      var processed = 0;
      while (!_date(current.nextDueDate).isAfter(today) &&
          processed < _maxOccurrencesPerRun) {
        final due = _date(current.nextDueDate);
        final dateKey = _dateKey(due);
        final id = _uuid.v5(
          Namespace.url.value,
          'recurring-income:${item.id}:$dateKey',
        );
        if (await _incomes.saveScheduled(
          IncomeEntry(
            id: id,
            amountMinor: current.amountMinor,
            source: IncomeSource.fixed,
            categoryId: current.categoryId,
            receivedAt: due,
            updatedAt: timestamp,
          ),
        )) {
          created++;
        }
        current = current.copyWith(
          nextDueDate: current.followingDueDate,
          updatedAt: timestamp,
        );
        processed++;
      }
      if (current.nextDueDate != item.nextDueDate) {
        await _plans.save(current);
      }
    }
    return created;
  }

  static DateTime _date(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
