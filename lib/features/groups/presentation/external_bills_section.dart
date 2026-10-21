import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/dialogs/confirm_dialog.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../../shared/widgets/app_callout.dart';
import '../data/group_service.dart';
import '../domain/external_bill.dart';

/// Mục "Bill bạn tham gia": bill mà người dùng vào qua QR nhưng không là
/// thành viên nhóm. Ẩn khi rỗng.
class ExternalBillsSection extends ConsumerWidget {
  const ExternalBillsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bills = ref.watch(externalBillsProvider);
    final items = bills.valueOrNull;
    if (items == null && bills.hasError) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: AppCallout(
          tone: CalloutTone.warning,
          message:
              'Không tải được bill bạn tham gia: ${friendlyMessage(bills.error!)}',
        ),
      );
    }
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Bill bạn tham gia',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final bill in items)
                _ExternalBillTile(
                  bill: bill,
                  onOpen: () => _showParticipants(context, bill),
                  onSettle: () => _run(
                    context,
                    ref,
                    (service) => service.settleMyShare(bill.id),
                  ),
                  onLeave: () => _leave(context, ref, bill),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _leave(
    BuildContext context,
    WidgetRef ref,
    ExternalBill bill,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Rời bill?',
      message:
          'Bạn sẽ không còn trong “${bill.description}”. '
          'Phần tiền của bạn sẽ được chia lại cho những người còn lại.',
      confirmLabel: 'Rời bill',
      icon: Icons.logout_outlined,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await _run(context, ref, (service) => service.leaveBill(bill.id));
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(ExpenseGroupService service) action,
  ) async {
    final service = ref.read(expenseGroupServiceProvider);
    if (service == null) return;
    try {
      await action(service);
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyMessage(error))));
      }
    }
    ref.invalidate(externalBillsProvider);
  }

  Future<void> _showParticipants(BuildContext context, ExternalBill bill) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text(
              bill.description,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('Tổng: ${MoneyFormatter.format(bill.totalMinor)}'),
            const SizedBox(height: 8),
            for (final participant in bill.participants)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  participant.isMe
                      ? '${participant.name} (Bạn)'
                      : participant.name,
                ),
                trailing: Text(
                  '${MoneyFormatter.format(participant.amountMinor)}'
                  '${participant.settled ? ' · Đã trả' : ''}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ExternalBillTile extends StatelessWidget {
  const _ExternalBillTile({
    required this.bill,
    required this.onOpen,
    required this.onSettle,
    required this.onLeave,
  });

  final ExternalBill bill;
  final VoidCallback onOpen;
  final Future<void> Function() onSettle;
  final Future<void> Function() onLeave;

  @override
  Widget build(BuildContext context) {
    // Bill thủ công: người mới nhận 0đ cho tới khi người trả chia lại.
    final waitingForAmount = !bill.isMineSettled && bill.myAmountMinor == 0;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                bill.description,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text('Người trả: ${bill.payerName}'),
              Text(
                'Phần của bạn: ${MoneyFormatter.format(bill.myAmountMinor)}',
              ),
              Text(
                bill.isMineSettled
                    ? 'Bạn đã thanh toán'
                    : waitingForAmount
                    ? 'Chờ người trả chia lại phần tiền'
                    : 'Chưa thanh toán',
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!bill.hasSettlement)
                    TextButton(
                      onPressed: onLeave,
                      child: const Text('Rời bill'),
                    ),
                  if (!bill.isMineSettled && !waitingForAmount)
                    FilledButton.tonal(
                      onPressed: onSettle,
                      child: const Text('Tôi đã thanh toán'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
