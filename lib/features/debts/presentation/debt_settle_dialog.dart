import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:uuid/uuid.dart';

import '../../../app/theme/finance_colors.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../features/income/data/income_repository.dart';
import '../../../features/invoices/domain/invoice_models.dart';
import '../data/debt_repository.dart';
import '../domain/debt_models.dart';

class DebtSettleResult {
  const DebtSettleResult({
    required this.amountMinor,
    required this.isFullSettlement,
    required this.recordAsTransaction,
  });

  final int amountMinor;
  final bool isFullSettlement;
  final bool recordAsTransaction;
}

Future<void> showDebtSettleDialog(
  BuildContext context,
  WidgetRef ref,
  DebtRecord debt,
) async {
  final remaining = debt.remainingMinor;
  if (remaining <= 0) return;

  final tr = context.tr;
  final isEn = tr.isEn;

  final controller = TextEditingController(
    text: MoneyFormatter.format(remaining).replaceAll(' ₫', '').replaceAll('.', ''),
  );
  bool isFull = true;
  bool recordTransaction = false;

  final result = await showDialog<DebtSettleResult>(
    context: context,
    useRootNavigator: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final theme = Theme.of(context);
        final isTheyOwe = debt.type == DebtType.theyOwe;

        return AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.verified_outlined,
                color: theme.colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(isEn ? 'Confirm Settlement' : 'Xác nhận thanh toán'),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isTheyOwe
                      ? (isEn
                          ? 'Confirm that ${debt.personName} paid debt:'
                          : 'Xác nhận ${debt.personName} đã thanh toán khoản nợ:')
                      : (isEn
                          ? 'Confirm you paid ${debt.personName}:'
                          : 'Xác nhận bạn đã thanh toán cho ${debt.personName}:'),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(isEn ? 'Total debt:' : 'Tổng số nợ:', style: theme.textTheme.bodySmall),
                          Text(
                            MoneyFormatter.format(debt.amountMinor),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (debt.paidAmountMinor > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(isEn ? 'Paid:' : 'Đã thanh toán:', style: theme.textTheme.bodySmall),
                            Text(
                              MoneyFormatter.format(debt.paidAmountMinor),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: context.finance.income.color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(isEn ? 'Remaining:' : 'Còn lại:', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          Text(
                            MoneyFormatter.format(remaining),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isTheyOwe ? context.finance.income.color : context.finance.expense.color,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                RadioListTile<bool>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(isEn
                      ? 'Pay in full (${MoneyFormatter.format(remaining)})'
                      : 'Thanh toán toàn bộ (${MoneyFormatter.format(remaining)})'),
                  value: true,
                  groupValue: isFull,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        isFull = val;
                        controller.text = remaining.toString();
                      });
                    }
                  },
                ),
                RadioListTile<bool>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(isEn ? 'Partial payment' : 'Thanh toán một phần'),
                  value: false,
                  groupValue: isFull,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => isFull = val);
                    }
                  },
                ),
                if (!isFull) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: isEn ? 'Payment amount this time (₫)' : 'Số tiền thanh toán lần này (₫)',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    isTheyOwe
                        ? (isEn
                            ? 'Record as income transaction in wallet'
                            : 'Ghi nhận thành một khoản thu vào ví')
                        : (isEn
                            ? 'Record as expense transaction'
                            : 'Ghi nhận thành một khoản chi tiêu'),
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                  ),
                  value: recordTransaction,
                  onChanged: (val) {
                    setState(() => recordTransaction = val ?? false);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr.cancel),
            ),
            FilledButton(
              onPressed: () {
                final inputAmount = int.tryParse(controller.text.trim()) ?? (isFull ? remaining : 0);
                if (inputAmount <= 0) return;
                Navigator.pop(
                  context,
                  DebtSettleResult(
                    amountMinor: inputAmount,
                    isFullSettlement: isFull || inputAmount >= remaining,
                    recordAsTransaction: recordTransaction,
                  ),
                );
              },
              child: Text(tr.confirm),
            ),
          ],
        );
      },
    ),
  );

  if (result == null || !context.mounted) return;

  final notifier = ref.read(debtsListProvider.notifier);
  if (result.isFullSettlement) {
    await notifier.settle(debt.id);
  } else {
    await notifier.recordPayment(debt.id, result.amountMinor);
  }

  // Tùy chọn tự động ghi thu/chi tương ứng nếu người dùng đã tích chọn
  if (result.recordAsTransaction) {
    final now = DateTime.now();
    try {
      if (debt.type == DebtType.theyOwe) {
        // Thu tiền người khác trả nợ -> Ghi nhận khoản thu
        final incomeRepo = ref.read(incomeRepositoryProvider);
        final noteSuffix = debt.notes?.isNotEmpty == true ? ' (${debt.notes})' : '';
        await incomeRepo.save(
          result.amountMinor,
          source: IncomeSource.manual,
          note: isEn
              ? 'Debt collection: ${debt.personName}$noteSuffix'
              : 'Thu hồi nợ: ${debt.personName}$noteSuffix',
          receivedAt: now,
        );
      } else {
        // Mình trả nợ -> Ghi nhận khoản chi
        final invoiceRepo = ref.read(invoiceRepositoryProvider);
        final invoice = InvoiceEntity(
          id: const Uuid().v4(),
          sellerName: isEn ? 'Debt repayment: ${debt.personName}' : 'Trả nợ: ${debt.personName}',
          notes: debt.notes,
          currencyCode: 'VND',
          subtotalMinor: result.amountMinor,
          taxMinor: 0,
          totalMinor: result.amountMinor,
          sourceType: InvoiceSourceType.manual,
          status: InvoiceStatus.confirmed,
          issuedAt: now,
          createdAt: now,
          updatedAt: now,
          confirmedAt: now,
        );
        await invoiceRepo.saveInvoice(invoice);
      }
    } on Object {
      // Bỏ qua nếu không thể tạo bản ghi giao dịch
    }
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.isFullSettlement
              ? (isEn
                  ? 'Settled full debt with ${debt.personName}.'
                  : 'Đã xác nhận tất toán khoản nợ của ${debt.personName}.')
              : (isEn
                  ? 'Recorded payment of ${MoneyFormatter.format(result.amountMinor)}.'
                  : 'Đã ghi nhận thanh toán ${MoneyFormatter.format(result.amountMinor)}.'),
        ),
      ),
    );
  }
}
