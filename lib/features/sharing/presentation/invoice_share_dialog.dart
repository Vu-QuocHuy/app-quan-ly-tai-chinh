import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../groups/domain/group_models.dart';
import '../../groups/domain/group_split_calculator.dart';
import '../../invoices/domain/invoice_models.dart';

Future<bool?> showInvoiceShareDialog(
  BuildContext context,
  InvoiceEntity invoice,
) {
  return showDialog<bool>(
    context: context,
    builder: (context) => InvoiceShareDialog(invoice: invoice),
  );
}

enum _ShareTarget { group, user }

class InvoiceShareDialog extends ConsumerStatefulWidget {
  const InvoiceShareDialog({required this.invoice, super.key});

  final InvoiceEntity invoice;

  @override
  ConsumerState<InvoiceShareDialog> createState() => _InvoiceShareDialogState();
}

class _InvoiceShareDialogState extends ConsumerState<InvoiceShareDialog> {
  final _emailController = TextEditingController();
  late final TextEditingController _recipientAmountController =
      TextEditingController(
        text: ((widget.invoice.totalMinor + 1) ~/ 2).toString(),
      );
  _ShareTarget _target = _ShareTarget.group;
  String? _groupId;
  Set<String> _selectedMemberIds = {};
  Future<GroupDetails>? _groupDetailsFuture;
  GroupSplitMode? _groupSplitMode;
  final Map<String, TextEditingController> _groupSplitControllers = {};
  String? _error;
  String? _emailError;
  String? _amountError;
  bool _busy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _recipientAmountController.dispose();
    for (final controller in _groupSplitControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(expenseGroupsProvider);
    return AlertDialog(
      title: const Text('Chia sẻ hóa đơn'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.invoice.sellerName} · ${MoneyFormatter.format(widget.invoice.totalMinor)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              const Text(
                'Chỉ snapshot tối thiểu của hóa đơn được đưa lên cloud; hóa đơn gốc vẫn riêng tư.',
              ),
              const SizedBox(height: 16),
              SegmentedButton<_ShareTarget>(
                segments: const [
                  ButtonSegment(
                    value: _ShareTarget.group,
                    icon: Icon(Icons.groups_outlined),
                    label: Text('Vào team'),
                  ),
                  ButtonSegment(
                    value: _ShareTarget.user,
                    icon: Icon(Icons.person_add_alt_outlined),
                    label: Text('Người dùng'),
                  ),
                ],
                selected: {_target},
                onSelectionChanged: (value) {
                  setState(() {
                    _target = value.first;
                    _error = null;
                  });
                },
              ),
              const SizedBox(height: 16),
              if (_target == _ShareTarget.group)
                _buildGroupTarget(groups)
              else
                _buildUserTarget(),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_outlined),
          label: const Text('Chia sẻ'),
        ),
      ],
    );
  }

  Widget _buildGroupTarget(AsyncValue<List<ExpenseGroup>> groups) {
    return switch (groups) {
      AsyncLoading() => const Center(child: CircularProgressIndicator()),
      AsyncError(:final error) => Text(
        'Không tải được danh sách team: ${friendlyMessage(error)}',
      ),
      AsyncData(value: final items) when items.isEmpty => const Text(
        'Bạn chưa tham gia team nào. Hãy tạo hoặc tham gia team trước.',
      ),
      AsyncData(value: final items) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _groupId,
            decoration: const InputDecoration(
              labelText: 'Team nhận hóa đơn',
              prefixIcon: Icon(Icons.groups_outlined),
            ),
            items: items
                .map(
                  (group) => DropdownMenuItem(
                    value: group.id,
                    child: Text(group.name),
                  ),
                )
                .toList(growable: false),
            onChanged: _busy ? null : (value) => _selectGroup(value, items),
          ),
          if (_groupDetailsFuture != null) ...[
            const SizedBox(height: 12),
            FutureBuilder<GroupDetails>(
              future: _groupDetailsFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    'Không tải được thành viên: ${friendlyMessage(snapshot.error!)}',
                  );
                }
                final details = snapshot.data;
                if (details == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _buildMembers(details.members);
              },
            ),
          ],
        ],
      ),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _buildMembers(List<GroupMember> members) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Chọn thành viên và cách chia',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        SegmentedButton<GroupSplitMode?>(
          segments: const [
            ButtonSegment(value: null, label: Text('Đều')),
            ButtonSegment(value: GroupSplitMode.exact, label: Text('Số tiền')),
            ButtonSegment(value: GroupSplitMode.percentage, label: Text('%')),
          ],
          selected: {_groupSplitMode},
          onSelectionChanged: _busy
              ? null
              : (value) => setState(() => _groupSplitMode = value.first),
        ),
        const SizedBox(height: 8),
        for (final member in members) _memberSplitField(member),
      ],
    );
  }

  Widget _memberSplitField(GroupMember member) {
    final selected = _selectedMemberIds.contains(member.userId);
    final controller = _groupSplitControllers.putIfAbsent(
      member.userId,
      TextEditingController.new,
    );
    return Row(
      children: [
        Checkbox(
          value: selected,
          onChanged: _busy
              ? null
              : (value) => setState(() {
                  value == true
                      ? _selectedMemberIds.add(member.userId)
                      : _selectedMemberIds.remove(member.userId);
                  _error = null;
                }),
        ),
        Expanded(child: Text(member.displayName)),
        if (_groupSplitMode != null)
          SizedBox(
            width: 120,
            child: TextField(
              controller: controller,
              enabled: selected && !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: InputDecoration(
                isDense: true,
                labelText: _groupSplitMode == GroupSplitMode.exact ? '₫' : '%',
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildUserTarget() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: InputDecoration(
            labelText: 'Email người nhận',
            hintText: 'nguoi.nhan@example.com',
            prefixIcon: Icon(Icons.alternate_email),
            errorText: _emailError,
          ),
          onChanged: (_) => setState(() => _emailError = null),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _recipientAmountController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: 'Phần tiền người nhận',
            suffixText: '₫',
            prefixIcon: Icon(Icons.payments_outlined),
            errorText: _amountError,
          ),
          onChanged: (_) => setState(() => _amountError = null),
        ),
        const SizedBox(height: 6),
        const Text('Người nhận cần chấp nhận thì chia sẻ mới có hiệu lực.'),
      ],
    );
  }

  void _selectGroup(String? value, List<ExpenseGroup> groups) {
    if (value == null) return;
    final group = groups.where((item) => item.id == value).firstOrNull;
    final service = ref.read(expenseGroupServiceProvider);
    if (group == null || service == null) return;
    setState(() {
      _groupId = value;
      _selectedMemberIds = {};
      _groupDetailsFuture = service.loadDetails(group);
      _error = null;
    });
    _groupDetailsFuture!.then((details) {
      if (!mounted || _groupId != value) return;
      setState(() {
        _selectedMemberIds = details.members.map((item) => item.userId).toSet();
      });
    });
  }

  Future<void> _submit() async {
    if (_target == _ShareTarget.user && !_validateDirectFields()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final service = ref.read(sharedBillServiceProvider);
      if (service == null) throw StateError('Cloud sync chưa được cấu hình.');
      if (_target == _ShareTarget.group) {
        final groupId = _groupId;
        if (groupId == null || _selectedMemberIds.isEmpty) {
          throw const FormatException(
            'Hãy chọn team và ít nhất một thành viên.',
          );
        }
        await service.shareInvoiceToGroup(
          invoice: widget.invoice,
          groupId: groupId,
          memberIds: _selectedMemberIds.toList(growable: false),
          splitAmounts: _groupSplitAmounts(),
        );
      } else {
        final amount = int.tryParse(_recipientAmountController.text.trim());
        await service.shareInvoiceToUser(
          invoice: widget.invoice,
          recipientEmail: _emailController.text,
          recipientAmountMinor: amount!,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyMessage(error);
        });
      }
    }
  }

  Map<String, int>? _groupSplitAmounts() {
    final mode = _groupSplitMode;
    if (mode == null) return null;
    final values = <String, double>{
      for (final id in _selectedMemberIds)
        id:
            double.tryParse(_groupSplitControllers[id]?.text.trim() ?? '') ??
            -1,
    };
    final result = GroupSplitCalculator.calculate(
      totalMinor: widget.invoice.totalMinor,
      memberIds: _selectedMemberIds,
      values: values,
      mode: mode,
    );
    if (result == null) {
      throw FormatException(
        mode == GroupSplitMode.exact
            ? 'Tổng số tiền phải bằng tổng hóa đơn.'
            : 'Tổng phần trăm phải bằng 100%.',
      );
    }
    return result;
  }

  bool _validateDirectFields() {
    final email = _emailController.text.trim();
    final amount = int.tryParse(_recipientAmountController.text.trim());
    final emailValid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    final amountValid =
        amount != null && amount >= 0 && amount <= widget.invoice.totalMinor;
    setState(() {
      _emailError = emailValid ? null : 'Nhập email hợp lệ của tài khoản nhận.';
      _amountError = amountValid ? null : 'Nhập số tiền từ 0 đến tổng hóa đơn.';
      _error = null;
    });
    return emailValid && amountValid;
  }
}
