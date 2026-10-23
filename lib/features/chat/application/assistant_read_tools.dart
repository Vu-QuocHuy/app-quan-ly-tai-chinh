import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../debts/data/debt_repository.dart';
import '../../debts/domain/debt_models.dart';
import '../../planning/domain/plan_models.dart';
import '../domain/chat_models.dart';

/// Only minimal user-scoped facts leave the device. Never send phone numbers,
/// auth metadata, group invitation codes or another account's records.
Future<List<ChatFact>?> readAssistantFacts(WidgetRef ref, String tool) async {
  String short(String text, int length) =>
      text.length <= length ? text : text.substring(0, length);
  switch (tool) {
    case 'get_debt_summary':
      final debts = (await ref.read(debtRepositoryProvider).loadDebts())
          .where((d) => !d.isSettled)
          .toList();
      return [
        ChatFact('debt_active_count', '${debts.length}'),
        ChatFact(
          'debt_receivable_minor_vnd',
          '${debts.where((d) => d.type == DebtType.theyOwe).fold<int>(0, (sum, d) => sum + d.remainingMinor)}',
        ),
        ChatFact(
          'debt_payable_minor_vnd',
          '${debts.where((d) => d.type == DebtType.iOwe).fold<int>(0, (sum, d) => sum + d.remainingMinor)}',
        ),
        for (final (i, debt) in debts.take(5).indexed)
          ChatFact(
            'debt_${i + 1}',
            '${debt.type == DebtType.iOwe ? 'i_owe' : 'they_owe'}: ${short(debt.personName, 40)}; remaining VND ${debt.remainingMinor}',
          ),
      ];
    case 'get_recurring_schedules':
      final plans = (await ref.read(planRepositoryProvider).getAll())
          .where((p) => p is RecurringBill || p is RecurringIncome)
          .toList();
      return [
        ChatFact('schedule_count', '${plans.length}'),
        for (final (i, plan) in plans.take(5).indexed)
          ChatFact('schedule_${i + 1}', switch (plan) {
            RecurringBill() =>
              '${short(plan.title, 40)}; bill reminder; ${plan.frequency.name}; VND ${plan.amountMinor}',
            RecurringIncome() =>
              '${short(plan.title, 40)}; income; monthly; VND ${plan.amountMinor}',
            _ => '',
          }),
      ];
    case 'get_group_summary':
      final service = ref.read(expenseGroupServiceProvider);
      if (service == null) throw StateError('Groups unavailable');
      final groups = await service.listGroups();
      return [
        ChatFact('group_count', '${groups.length}'),
        for (final (i, group) in groups.take(5).indexed)
          ChatFact('group_${i + 1}', short(group.name, 80)),
      ];
    default:
      return null;
  }
}
