import 'dart:math' as math;

import 'group_models.dart';

class GroupSettlementTransfer {
  const GroupSettlementTransfer({
    required this.fromUserId,
    required this.toUserId,
    required this.amountMinor,
  });

  final String fromUserId;
  final String toUserId;
  final int amountMinor;
}

abstract final class GroupBalanceCalculator {
  static Map<String, int> calculate({
    required Iterable<String> memberIds,
    required Iterable<GroupExpense> expenses,
  }) {
    final result = {for (final memberId in memberIds) memberId: 0};
    for (final expense in expenses) {
      final payerId = expense.payerId;
      if (payerId != null) {
        result[payerId] = (result[payerId] ?? 0) + expense.totalMinor;
      }
      for (final split in expense.splits) {
        final userId = split.userId;
        if (userId == null) continue;
        if (split.isSettled && payerId != null && userId != payerId) {
          result[payerId] = (result[payerId] ?? 0) - split.amountMinor;
        } else {
          result[userId] = (result[userId] ?? 0) - split.amountMinor;
        }
      }
    }
    return result;
  }

  static List<GroupSettlementTransfer> calculateSettlementTransfers(
    Map<String, int> balances,
  ) {
    final debtors = [
      for (final entry in balances.entries)
        if (entry.value < 0) _SettlementParty(entry.key, -entry.value),
    ];
    final creditors = [
      for (final entry in balances.entries)
        if (entry.value > 0) _SettlementParty(entry.key, entry.value),
    ];
    final transfers = <GroupSettlementTransfer>[];
    var debtorIndex = 0;
    var creditorIndex = 0;
    while (debtorIndex < debtors.length && creditorIndex < creditors.length) {
      final debtor = debtors[debtorIndex];
      final creditor = creditors[creditorIndex];
      final amount = math.min(debtor.amount, creditor.amount);
      if (amount > 0) {
        transfers.add(
          GroupSettlementTransfer(
            fromUserId: debtor.userId,
            toUserId: creditor.userId,
            amountMinor: amount,
          ),
        );
        debtor.amount -= amount;
        creditor.amount -= amount;
      }
      if (debtor.amount == 0) debtorIndex++;
      if (creditor.amount == 0) creditorIndex++;
    }
    return List.unmodifiable(transfers);
  }
}

class _SettlementParty {
  _SettlementParty(this.userId, this.amount);

  final String userId;
  int amount;
}
