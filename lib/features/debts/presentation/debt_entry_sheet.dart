import '../../../core/utils/money_input_formatter.dart';
import '../../../core/utils/money_formatter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/localization/app_strings.dart';
import '../../../app/theme/finance_colors.dart';
import '../data/debt_notification_store.dart';
import '../data/debt_repository.dart';
import '../domain/debt_models.dart';

Future<void> showDebtEntrySheet(BuildContext context, {DebtRecord? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (context) => SizedBox(
      width: double.infinity,
      child: DebtEntrySheet(existing: existing),
    ),
  );
}

class DebtEntrySheet extends ConsumerStatefulWidget {
  const DebtEntrySheet({this.existing, super.key});
  final DebtRecord? existing;

  @override
  ConsumerState<DebtEntrySheet> createState() => _DebtEntrySheetState();
}

class _DebtEntrySheetState extends ConsumerState<DebtEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  late DebtType _type;
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _amountController;
  late final TextEditingController _notesController;
  DateTime? _dueDate;

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
    _type = item?.type ?? DebtType.theyOwe;
    _nameController = TextEditingController(text: item?.personName ?? '');
    _phoneController = TextEditingController(text: item?.phoneNumber ?? '');
    _amountController = TextEditingController(
      text: MoneyInputFormatter.format(item?.amountMinor.toString()),
    );
    _notesController = TextEditingController(text: item?.notes ?? '');
    _dueDate = item?.dueDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now.add(const Duration(days: 7)),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = MoneyFormatter.tryParse(_amountController.text) ?? 0;
    if (amount <= 0) return;

    final existing = widget.existing;
    final record = DebtRecord(
      id: existing?.id ?? const Uuid().v4(),
      personName: _nameController.text.trim(),
      phoneNumber:
          (_type == DebtType.theyOwe && _phoneController.text.trim().isNotEmpty)
          ? _phoneController.text.trim()
          : null,
      type: _type,
      amountMinor: amount,
      paidAmountMinor: existing?.paidAmountMinor ?? 0,
      dueDate: _dueDate,
      createdAt: existing?.createdAt ?? DateTime.now(),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      status: existing?.status ?? DebtStatus.active,
      settledAt: existing?.settledAt,
    );

    await ref.read(debtsListProvider.notifier).addOrUpdate(record);

    if (existing == null && record.phoneNumber != null && mounted) {
      final sent = await DebtNotificationStore.sendDebtNotification(
        ref: ref,
        targetPhone: record.phoneNumber!,
        senderName: 'Bạn bè',
        amountMinor: record.amountMinor,
        notes: record.notes,
        dueDate: record.dueDate,
      );
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            content: Text(
              sent
                  ? 'Đã lưu nợ & gửi thông báo trong app tới ${record.phoneNumber}'
                  : 'Đã lưu khoản nợ (SĐT ${record.phoneNumber} chưa có tài khoản Finmi)',
            ),
          ),
        );
      }
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tr = context.tr;
    final isEditing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isEditing
                    ? (tr.isEn ? 'Edit Debt' : 'Sửa khoản nợ')
                    : (tr.isEn ? 'Record New Debt' : 'Ghi nhận khoản nợ mới'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SegmentedButton<DebtType>(
                segments: [
                  ButtonSegment<DebtType>(
                    value: DebtType.theyOwe,
                    label: Text(
                      tr.isEn ? 'They owe me' : 'Người khác nợ tôi',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _type == DebtType.theyOwe
                            ? null
                            : context.finance.income.color,
                      ),
                    ),
                    icon: Icon(
                      Icons.arrow_downward_rounded,
                      color: _type == DebtType.theyOwe
                          ? null
                          : context.finance.income.color,
                    ),
                  ),
                  ButtonSegment<DebtType>(
                    value: DebtType.iOwe,
                    label: Text(
                      tr.isEn ? 'I owe them' : 'Tôi nợ người khác',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _type == DebtType.iOwe
                            ? null
                            : context.finance.expense.color,
                      ),
                    ),
                    icon: Icon(
                      Icons.arrow_upward_rounded,
                      color: _type == DebtType.iOwe
                          ? null
                          : context.finance.expense.color,
                    ),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (newSelection) {
                  setState(() => _type = newSelection.first);
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: _type == DebtType.theyOwe
                      ? (tr.isEn ? 'Debtor name *' : 'Tên người nợ *')
                      : (tr.isEn ? 'Creditor name *' : 'Tên chủ nợ *'),
                  hintText: tr.isEn
                      ? 'e.g. Alex, Sam...'
                      : 'Ví dụ: Anh Nam, Bạn Linh...',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (val) => val == null || val.trim().isEmpty
                    ? (tr.isEn ? 'Please enter a name' : 'Vui lòng nhập tên')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                inputFormatters: [const MoneyInputFormatter()],
                decoration: InputDecoration(
                  labelText: tr.isEn ? 'Debt amount (₫) *' : 'Số tiền nợ (₫) *',
                  hintText: '200000',
                  prefixIcon: const Icon(Icons.attach_money_rounded),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (val) {
                  final parsed = MoneyFormatter.tryParse(val ?? '');
                  if (parsed == null || parsed <= 0) {
                    return tr.isEn
                        ? 'Please enter a valid amount'
                        : 'Vui lòng nhập số tiền hợp lệ';
                  }
                  return null;
                },
              ),
              if (_type == DebtType.theyOwe) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: InputDecoration(
                    labelText: tr.isEn
                        ? 'Phone number (optional)'
                        : 'Số điện thoại (tùy chọn)',
                    hintText: '0912345678',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (val) {
                    final phone = val?.trim() ?? '';
                    if (phone.isEmpty) return null;
                    return RegExp(r'^0[0-9]{9}$').hasMatch(phone)
                        ? null
                        : (tr.isEn
                              ? 'Phone number must be 10 digits starting with 0.'
                              : 'Số điện thoại gồm đúng 10 số và bắt đầu bằng 0.');
                  },
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: tr.isEn
                      ? 'Debt note / reason'
                      : 'Ghi chú lý do vay/nợ',
                  hintText: tr.isEn
                      ? 'e.g. Dinner, shopping advance...'
                      : 'Ví dụ: Tiền ăn tối, ứng tiền mua đồ...',
                  prefixIcon: const Icon(Icons.notes_outlined),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDueDate,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      label: Text(
                        _dueDate == null
                            ? (tr.isEn
                                  ? 'Select due date'
                                  : 'Chọn ngày hẹn trả')
                            : '${tr.isEn ? 'Due' : 'Hạn'}: ${DateFormat('dd/MM/yyyy').format(_dueDate!)}',
                      ),
                    ),
                  ),
                  if (_dueDate != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: tr.isEn ? 'Clear due date' : 'Xóa ngày hẹn',
                      onPressed: () => setState(() => _dueDate = null),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  isEditing
                      ? (tr.isEn ? 'Save Changes' : 'Lưu thay đổi')
                      : (tr.isEn ? 'Create Debt' : 'Tạo khoản nợ'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
