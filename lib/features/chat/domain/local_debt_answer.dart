import '../../../core/utils/money_formatter.dart';
import '../../debts/domain/debt_models.dart';
import 'chat_models.dart';
import 'chat_routing_rules.dart';

/// Answers "đang nợ ai / ai nợ tôi / còn nợ bao nhiêu" from local debt
/// records (H3). Phone numbers and notes never appear in the answer.
ChatReply localDebtAnswer(String question, List<DebtRecord> debts) {
  final padded = ' ${ChatRoutingRules.normalize(question)} ';
  final active = debts.where((debt) => !debt.isSettled).toList(growable: false);
  final payable = active.where((debt) => debt.type == DebtType.iOwe).toList();
  final receivable = active
      .where((debt) => debt.type == DebtType.theyOwe)
      .toList();
  final payableTotal = payable.fold<int>(0, (sum, d) => sum + d.remainingMinor);
  final receivableTotal = receivable.fold<int>(
    0,
    (sum, d) => sum + d.remainingMinor,
  );

  // "ai nợ tôi" → only receivables; "tôi nợ ai / đang nợ" → only payables.
  final onlyReceivable = padded.contains(' ai no ');
  final onlyPayable =
      !onlyReceivable &&
      (padded.contains(' toi no ') ||
          padded.contains(' no ai ') ||
          padded.contains(' toi dang no '));

  String line(DebtRecord debt) => debt.type == DebtType.iOwe
      ? '• Bạn nợ ${_short(debt.personName)}: '
            '${MoneyFormatter.format(debt.remainingMinor)}'
      : '• ${_short(debt.personName)} nợ bạn: '
            '${MoneyFormatter.format(debt.remainingMinor)}';

  final String text;
  final visible = onlyReceivable
      ? receivable
      : onlyPayable
      ? payable
      : active;
  if (visible.isEmpty) {
    text = onlyReceivable
        ? 'Hiện không có ai đang nợ bạn khoản nào.'
        : onlyPayable
        ? 'Hiện bạn không còn nợ ai khoản nào 🎉.'
        : 'Hiện bạn không có khoản nợ nào đang mở 🎉.';
  } else {
    final sorted = [...visible]
      ..sort((a, b) => b.remainingMinor.compareTo(a.remainingMinor));
    final items = sorted.take(5).map(line).join('\n');
    final more = sorted.length > 5
        ? '\n… và ${sorted.length - 5} khoản khác.'
        : '';
    final summary = onlyReceivable
        ? 'Có ${receivable.length} khoản người khác đang nợ bạn, tổng '
              '${MoneyFormatter.format(receivableTotal)}:'
        : onlyPayable
        ? 'Bạn đang nợ ${payable.length} khoản, tổng '
              '${MoneyFormatter.format(payableTotal)}:'
        : 'Bạn đang nợ ${MoneyFormatter.format(payableTotal)} '
              '(${payable.length} khoản) và được nợ '
              '${MoneyFormatter.format(receivableTotal)} '
              '(${receivable.length} khoản):';
    text = '$summary\n$items$more';
  }
  return ChatReply(
    text: text,
    citations: const [
      ChatCitation(
        label: 'Dữ liệu khoản nợ trên thiết bị',
        sourceType: 'local',
        sourceId: 'debts',
      ),
    ],
    facts: [
      ChatFact('debt_active_count', '${active.length}'),
      ChatFact('debt_payable_minor_vnd', '$payableTotal'),
      ChatFact('debt_receivable_minor_vnd', '$receivableTotal'),
    ],
  );
}

String _short(String value) {
  final name = value.trim();
  return name.length <= 40 ? name : '${name.substring(0, 40)}…';
}
