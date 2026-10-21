import 'package:flutter/material.dart';

import '../../../shared/dialogs/confirm_dialog.dart';
import '../domain/group_models.dart';
import '../domain/group_split_calculator.dart';

/// Mô tả lần chia tiền tạo từ hóa đơn quét; giới hạn 160 ký tự như server.
String receiptExpenseDescription(String sellerName) {
  final seller = sellerName.trim();
  final text = seller.isEmpty ? 'Hóa đơn' : 'Hóa đơn $seller';
  return text.length > 160 ? text.substring(0, 160) : text;
}

class GroupExpenseDraft {
  const GroupExpenseDraft({
    required this.description,
    required this.totalMinor,
    required this.memberIds,
    this.splitAmounts,
  });

  final String description;
  final int totalMinor;
  final List<String> memberIds;
  final Map<String, int>? splitAmounts;
}

/// Biểu mẫu một lần chia tiền: nội dung, tổng tiền, thành viên, cách chia.
/// Dùng chung cho dialog sửa và hai tab của dialog "Chia tiền".
class GroupExpenseForm extends StatefulWidget {
  const GroupExpenseForm({
    required this.members,
    this.initialExpense,
    this.initialDescription,
    this.initialTotalMinor,
    this.autofocus = true,
    super.key,
  });

  final List<GroupMember> members;
  final GroupExpense? initialExpense;

  /// Giá trị điền sẵn khi tạo mới; bị bỏ qua khi có [initialExpense].
  final String? initialDescription;
  final int? initialTotalMinor;
  final bool autofocus;

  @override
  State<GroupExpenseForm> createState() => GroupExpenseFormState();
}

class GroupExpenseFormState extends State<GroupExpenseForm> {
  late final TextEditingController _descriptionController;
  late final TextEditingController _amountController;
  final Map<String, TextEditingController> _splitControllers = {};
  late final Set<String> _selectedIds;
  late GroupSplitMode? _customMode;
  late final String _startDescription;
  late final String _startAmount;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialExpense;
    final prefillTotal = widget.initialTotalMinor;
    _descriptionController = TextEditingController(
      text: initial?.description ?? widget.initialDescription,
    );
    _amountController = TextEditingController(
      text:
          initial?.totalMinor.toString() ??
          (prefillTotal != null && prefillTotal > 0
              ? prefillTotal.toString()
              : null),
    );
    _startDescription = _descriptionController.text;
    _startAmount = _amountController.text;
    _selectedIds = initial == null
        ? widget.members.map((item) => item.userId).toSet()
        : initial.splits
              .map((split) => split.userId)
              .whereType<String>()
              .toSet();
    _customMode = initial == null ? null : GroupSplitMode.exact;
    if (initial != null) {
      for (final split in initial.splits) {
        final userId = split.userId;
        if (userId != null) {
          _splitControllers[userId] = TextEditingController(
            text: split.amountMinor.toString(),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    for (final controller in _splitControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _descriptionController,
          autofocus: widget.autofocus,
          decoration: const InputDecoration(labelText: 'Nội dung'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Tổng tiền',
            suffixText: '₫',
          ),
        ),
        const SizedBox(height: 16),
        SegmentedButton<GroupSplitMode?>(
          segments: const [
            ButtonSegment(value: null, label: Text('Đều')),
            ButtonSegment(value: GroupSplitMode.exact, label: Text('Số tiền')),
            ButtonSegment(value: GroupSplitMode.percentage, label: Text('%')),
          ],
          selected: {_customMode},
          onSelectionChanged: (value) => setState(() {
            _customMode = value.first;
            _error = null;
          }),
        ),
        const SizedBox(height: 12),
        Text(_customMode == null ? 'Chia đều cho' : 'Phần của từng người'),
        for (final member in widget.members) _buildMemberRow(member),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  bool get hasChanges {
    final initial = widget.initialExpense;
    final initialMemberIds = initial == null
        ? widget.members.map((item) => item.userId).toSet()
        : initial.splits
              .map((split) => split.userId)
              .whereType<String>()
              .toSet();
    if (_descriptionController.text != _startDescription ||
        _amountController.text != _startAmount ||
        _customMode != (initial == null ? null : GroupSplitMode.exact) ||
        _selectedIds.length != initialMemberIds.length ||
        !_selectedIds.containsAll(initialMemberIds)) {
      return true;
    }

    final initialSplitAmounts = {
      if (initial != null)
        for (final split in initial.splits)
          if (split.userId != null) split.userId!: split.amountMinor,
    };
    return _splitControllers.entries.any(
      (entry) =>
          entry.value.text !=
          (initialSplitAmounts[entry.key]?.toString() ?? ''),
    );
  }

  /// Kiểm tra dữ liệu; hợp lệ thì trả bản nháp, sai thì hiện lỗi và trả `null`.
  GroupExpenseDraft? submit() {
    final total = int.tryParse(
      _amountController.text.replaceAll(RegExp(r'[^0-9]'), ''),
    );
    final description = _descriptionController.text.trim();
    if (description.length < 2 ||
        total == null ||
        total <= 0 ||
        _selectedIds.isEmpty) {
      setState(
        () => _error = 'Hãy nhập nội dung, tổng tiền và chọn thành viên.',
      );
      return null;
    }
    Map<String, int>? splitAmounts;
    if (_customMode != null) {
      splitAmounts = _parseSplits(total);
      if (splitAmounts == null) return null;
    }
    return GroupExpenseDraft(
      description: description,
      totalMinor: total,
      memberIds: _selectedIds.toList(growable: false),
      splitAmounts: widget.initialExpense == null
          ? splitAmounts
          : splitAmounts!,
    );
  }

  Widget _buildMemberRow(GroupMember member) {
    final controller = _splitControllers.putIfAbsent(
      member.userId,
      TextEditingController.new,
    );
    return Row(
      children: [
        Expanded(
          child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _selectedIds.contains(member.userId),
            title: Text(member.displayName),
            onChanged: (value) => setState(() {
              if (value == true) {
                _selectedIds.add(member.userId);
              } else {
                _selectedIds.remove(member.userId);
              }
              _error = null;
            }),
          ),
        ),
        if (_customMode != null)
          SizedBox(
            width: 92,
            child: TextField(
              controller: controller,
              enabled: _selectedIds.contains(member.userId),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                suffixText: _customMode == GroupSplitMode.percentage
                    ? '%'
                    : '₫',
              ),
            ),
          ),
      ],
    );
  }

  Map<String, int>? _parseSplits(int total) {
    final values = <String, double>{};
    for (final id in _selectedIds) {
      final value = double.tryParse(
        _splitControllers[id]!.text.trim().replaceAll(',', '.'),
      );
      if (value == null || value < 0) {
        setState(() => _error = 'Hãy nhập phần chia hợp lệ cho mọi người.');
        return null;
      }
      values[id] = value;
    }
    final amounts = GroupSplitCalculator.calculate(
      totalMinor: total,
      memberIds: _selectedIds,
      values: values,
      mode: _customMode!,
    );
    if (amounts == null) {
      setState(
        () => _error = _customMode == GroupSplitMode.percentage
            ? 'Tổng tỷ lệ phải bằng 100%.'
            : 'Tổng các phần tiền phải bằng tổng tiền.',
      );
      return null;
    }
    return amounts;
  }
}

/// Dialog một biểu mẫu — dùng khi sửa một lần chia tiền (tạo mới dùng
/// `GroupSplitDialog` hai tab ở Task 7).
class GroupExpenseDialog extends StatefulWidget {
  const GroupExpenseDialog({
    required this.members,
    this.initialExpense,
    this.initialDescription,
    this.initialTotalMinor,
    super.key,
  });

  final List<GroupMember> members;
  final GroupExpense? initialExpense;
  final String? initialDescription;
  final int? initialTotalMinor;

  @override
  State<GroupExpenseDialog> createState() => _GroupExpenseDialogState();
}

class _GroupExpenseDialogState extends State<GroupExpenseDialog> {
  final _formKey = GlobalKey<GroupExpenseFormState>();

  @override
  Widget build(BuildContext context) {
    final editing = widget.initialExpense != null;
    return AlertDialog(
      title: Text(editing ? 'Sửa lần chia tiền' : 'Chia tiền'),
      content: SingleChildScrollView(
        child: GroupExpenseForm(
          key: _formKey,
          members: widget.members,
          initialExpense: widget.initialExpense,
          initialDescription: widget.initialDescription,
          initialTotalMinor: widget.initialTotalMinor,
        ),
      ),
      actions: [
        TextButton(onPressed: _cancel, child: const Text('Hủy')),
        FilledButton(
          onPressed: _submit,
          child: Text(editing ? 'Lưu thay đổi' : 'Chia tiền'),
        ),
      ],
    );
  }

  Future<void> _cancel() async {
    if (_formKey.currentState?.hasChanges ?? false) {
      final discard = await showDiscardChangesDialog(context);
      if (!discard || !mounted) return;
    }
    Navigator.pop(context);
  }

  void _submit() {
    final draft = _formKey.currentState?.submit();
    if (draft != null) Navigator.pop(context, draft);
  }
}
