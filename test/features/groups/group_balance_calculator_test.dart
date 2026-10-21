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

  test('phần của người ngoài nhóm không vào số dư thành viên', () {
    for (final settled in [null, DateTime(2026, 10, 21)]) {
      final balances = GroupBalanceCalculator.calculate(
        memberIds: const ['payer', 'member'],
        expenses: [
          GroupExpense(
            id: 'expense-1',
            groupId: 'group-1',
            payerId: 'payer',
            description: 'Ăn tối',
            totalMinor: 300000,
            createdAt: DateTime(2026, 10, 21),
            splitMode: 'equal',
            splits: [
              const GroupExpenseSplit(userId: 'payer', amountMinor: 100000),
              const GroupExpenseSplit(userId: 'member', amountMinor: 100000),
              GroupExpenseSplit(
                userId: 'guest',
                amountMinor: 100000,
                settledAt: settled,
                participantName: 'Dũng',
              ),
            ],
          ),
        ],
      );

      expect(balances, {'payer': 100000, 'member': -100000});
    }
  });

  test('gợi ý tất toán chỉ giữa thành viên nhóm', () {
    final balances = GroupBalanceCalculator.calculate(
      memberIds: const ['payer', 'member'],
      expenses: [
        GroupExpense(
          id: 'expense-1',
          groupId: 'group-1',
          payerId: 'payer',
          description: 'Ăn tối',
          totalMinor: 300000,
          createdAt: DateTime(2026, 10, 21),
          splits: const [
            GroupExpenseSplit(userId: 'member', amountMinor: 100000),
            GroupExpenseSplit(userId: 'guest-1', amountMinor: 100000),
            GroupExpenseSplit(userId: 'guest-2', amountMinor: 100000),
          ],
        ),
      ],
    );
    final transfers = GroupBalanceCalculator.calculateSettlementTransfers(
      balances,
    );

    expect(
      transfers
          .map(
            (transfer) =>
                '${transfer.fromUserId}->${transfer.toUserId}:${transfer.amountMinor}',
          )
          .toList(),
      ['member->payer:100000'],
    );
  });

  test('người trả không thuộc nhóm thì bỏ qua phần được nhận', () {
    final balances = GroupBalanceCalculator.calculate(
      memberIds: const ['member'],
      expenses: [
        GroupExpense(
          id: 'expense-1',
          groupId: 'group-1',
          payerId: 'former-member',
          description: 'Taxi',
          totalMinor: 100000,
          createdAt: DateTime(2026, 10, 21),
          splits: const [
            GroupExpenseSplit(userId: 'member', amountMinor: 50000),
            GroupExpenseSplit(userId: 'former-member', amountMinor: 50000),
          ],
        ),
      ],
    );

    expect(balances, {'member': -50000});
  });
}
