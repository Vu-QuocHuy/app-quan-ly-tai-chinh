import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/groups/domain/group_balance_calculator.dart';
import 'package:hoadon_insight/features/groups/domain/group_models.dart';

void main() {
  test('removes settled shares from outstanding balances', () {
    final balances = GroupBalanceCalculator.calculate(
      memberIds: const ['payer', 'member'],
      expenses: [
        GroupExpense(
          id: 'expense-1',
          groupId: 'group-1',
          payerId: 'payer',
          description: 'Ăn tối',
          totalMinor: 200000,
          createdAt: DateTime(2026, 9, 17),
          splits: [
            GroupExpenseSplit(userId: 'payer', amountMinor: 100000),
            GroupExpenseSplit(
              userId: 'member',
              amountMinor: 100000,
              settledAt: DateTime(2026, 9, 17),
            ),
          ],
        ),
      ],
    );

    expect(balances, {'payer': 0, 'member': 0});
  });

  test('keeps unsettled shares as receivable and payable', () {
    final balances = GroupBalanceCalculator.calculate(
      memberIds: const ['payer', 'member'],
      expenses: [
        GroupExpense(
          id: 'expense-1',
          groupId: 'group-1',
          payerId: 'payer',
          description: 'Mua đồ chung',
          totalMinor: 200000,
          createdAt: DateTime(2026, 9, 17),
          splits: const [
            GroupExpenseSplit(userId: 'payer', amountMinor: 100000),
            GroupExpenseSplit(userId: 'member', amountMinor: 100000),
          ],
        ),
      ],
    );

    expect(balances, {'payer': 100000, 'member': -100000});
  });

  test('builds minimal settlement transfers from member balances', () {
    final transfers = GroupBalanceCalculator.calculateSettlementTransfers({
      'payer': 150000,
      'member-a': -100000,
      'member-b': -50000,
    });

    expect(
      transfers
          .map(
            (transfer) =>
                '${transfer.fromUserId}->${transfer.toUserId}:${transfer.amountMinor}',
          )
          .toList(),
      ['member-a->payer:100000', 'member-b->payer:50000'],
    );
  });

  test('does not create transfers for balanced members', () {
    expect(
      GroupBalanceCalculator.calculateSettlementTransfers({
        'payer': 0,
        'member': 0,
      }),
      isEmpty,
    );
  });
}
