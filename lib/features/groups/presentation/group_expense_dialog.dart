import 'package:flutter/material.dart';

import '../../../app/theme/finance_colors.dart';
import '../../../core/utils/money_formatter.dart';
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
    this.equalSplit = false,
  });

  final String description;
  final int totalMinor;
  final List<String> memberIds;
  final Map<String, int>? splitAmounts;

  /// `true` khi người dùng chọn "Đều"; màn nhóm gửi `splitMode: 'equal'`.
  final bool equalSplit;
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
    _customMode = _initialMode;
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

  /// Tạo mới và bill chia đều mở ở "Đều"; bill thủ công mở ở "Số tiền".
  GroupSplitMode? get _initialMode {
    final initial = widget.initialExpense;
    if (initial == null || initial.splitMode == 'equal') return null;
    return GroupSplitMode.exact;
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
            if (_customMode == GroupSplitMode.exact) {
              _syncExactAmounts();
            } else if (_customMode == GroupSplitMode.percentage) {
              _syncPercentageAmounts();
            }
          }),
        ),
        const SizedBox(height: 12),
        Text(_customMode == null ? 'Chia đều cho' : 'Phần của từng người'),
        for (final member in widget.members) _buildMemberRow(member),
        if (_customMode == GroupSplitMode.exact) ...[
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final total = _totalMinor;
              final sum = _currentExactSum;
              final theme = Theme.of(context);
              if (total <= 0) return const SizedBox.shrink();
              final isMatch = sum == total;
              final isOver = sum > total;
              final color = isMatch
                  ? (Theme.of(
                          context,
                        ).extension<AppFinanceColors>()?.income.color ??
                        Colors.green)
                  : (isOver
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary);
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isMatch
                          ? Icons.check_circle_outline
                          : (isOver
                                ? Icons.warning_amber_rounded
                                : Icons.info_outline),
                      size: 18,
                      color: color,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isMatch
                            ? 'Tổng tiền chia đã khớp hoàn toàn (${MoneyFormatter.format(total)}).'
                            : (isOver
                                  ? 'Tổng tiền chia (${MoneyFormatter.format(sum)}) đang vượt quá tổng tiền (${MoneyFormatter.format(total)}).'
                                  : 'Tổng tiền chia: ${MoneyFormatter.format(sum)} / ${MoneyFormatter.format(total)} (còn thiếu ${MoneyFormatter.format(total - sum)}).'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
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

  int get _totalMinor =>
      int.tryParse(_amountController.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
      0;

  int get _currentExactSum {
    var sum = 0;
    for (final id in _selectedIds) {
      final ctrl = _splitControllers[id];
      if (ctrl != null) {
        final val =
            int.tryParse(ctrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        sum += val;
      }
    }
    return sum;
  }

  void _syncExactAmounts() {
    final total = _totalMinor;
    if (total <= 0 || _selectedIds.isEmpty) return;
    final allEmpty = _selectedIds.every((id) {
      final ctrl = _splitControllers[id];
      return ctrl == null || ctrl.text.trim().isEmpty;
    });
    if (allEmpty) {
      final n = _selectedIds.length;
      var i = 0;
      for (final id in _selectedIds) {
        final ctrl = _splitControllers.putIfAbsent(
          id,
          TextEditingController.new,
        );
        final share = total ~/ n + (i++ < total % n ? 1 : 0);
        ctrl.text = share.toString();
      }
    } else if (_selectedIds.length == 1) {
      final singleId = _selectedIds.first;
      final ctrl = _splitControllers.putIfAbsent(
        singleId,
        TextEditingController.new,
      );
      ctrl.text = total.toString();
    }
  }

  void _syncPercentageAmounts() {
    if (_selectedIds.isEmpty) return;
    final allEmpty = _selectedIds.every((id) {
      final ctrl = _splitControllers[id];
      return ctrl == null || ctrl.text.trim().isEmpty;
    });
    if (allEmpty) {
      final n = _selectedIds.length;
      final base = (100 / n).toStringAsFixed(1);
      for (final id in _selectedIds) {
        final ctrl = _splitControllers.putIfAbsent(
          id,
          TextEditingController.new,
        );
        ctrl.text = base;
      }
    }
  }

  void _onMemberAmountChanged(String editingId, String value) {
    if (_customMode == GroupSplitMode.exact) {
      final total = _totalMinor;
      if (total > 0) {
        if (_selectedIds.length == 2) {
          final otherId = _selectedIds.firstWhere((id) => id != editingId);
          final enteredVal =
              int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          final remaining = total - enteredVal;
          if (remaining >= 0) {
            final otherCtrl = _splitControllers.putIfAbsent(
              otherId,
              TextEditingController.new,
            );
            otherCtrl.text = remaining.toString();
            otherCtrl.selection = TextSelection.collapsed(
              offset: otherCtrl.text.length,
            );
          }
        } else if (_selectedIds.length > 2) {
          final otherIds = _selectedIds.where((id) => id != editingId).toList();
          final otherWithText = otherIds
              .where(
                (id) =>
                    (_splitControllers[id]?.text.trim().isNotEmpty ?? false),
              )
              .toList();
          if (otherWithText.length == otherIds.length - 1) {
            final remainderId = otherIds.firstWhere(
              (id) => (_splitControllers[id]?.text.trim().isEmpty ?? true),
            );
            var sumOthers =
                int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
            for (final oid in otherWithText) {
              sumOthers +=
                  int.tryParse(
                    _splitControllers[oid]?.text.replaceAll(
                          RegExp(r'[^0-9]'),
                          '',
                        ) ??
                        '',
                  ) ??
                  0;
            }
            final remaining = total - sumOthers;
            if (remaining >= 0) {
              final remCtrl = _splitControllers.putIfAbsent(
                remainderId,
                TextEditingController.new,
              );
              remCtrl.text = remaining.toString();
              remCtrl.selection = TextSelection.collapsed(
                offset: remCtrl.text.length,
              );
            }
          }
        }
      }
    } else if (_customMode == GroupSplitMode.percentage) {
      if (_selectedIds.length == 2) {
        final otherId = _selectedIds.firstWhere((id) => id != editingId);
        final enteredVal = double.tryParse(value.replaceAll(',', '.')) ?? 0;
        final remaining = 100 - enteredVal;
        if (remaining >= 0) {
          final otherCtrl = _splitControllers.putIfAbsent(
            otherId,
            TextEditingController.new,
          );
          otherCtrl.text = remaining.toStringAsFixed(
            remaining.truncateToDouble() == remaining ? 0 : 1,
          );
          otherCtrl.selection = TextSelection.collapsed(
            offset: otherCtrl.text.length,
          );
        }
      }
    }
    setState(() => _error = null);
  }

  void _toggleMember(String memberId, bool isSelected) {
    setState(() {
      if (isSelected) {
        _selectedIds.add(memberId);
      } else {
        _selectedIds.remove(memberId);
      }
      _error = null;
      if (_customMode == GroupSplitMode.exact) {
        final total = _totalMinor;
        if (_selectedIds.length == 1) {
          final singleId = _selectedIds.first;
          final ctrl = _splitControllers.putIfAbsent(
            singleId,
            TextEditingController.new,
          );
          ctrl.text = total.toString();
        } else if (_selectedIds.length == 2 && total > 0) {
          final ids = _selectedIds.toList();
          final id0Val =
              int.tryParse(
                _splitControllers[ids[0]]?.text.replaceAll(
                      RegExp(r'[^0-9]'),
                      '',
                    ) ??
                    '',
              ) ??
              0;
          if (id0Val > 0 && id0Val <= total) {
            _splitControllers[ids[1]]?.text = (total - id0Val).toString();
          } else {
            _syncExactAmounts();
          }
        }
      }
    });
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
        _customMode != _initialMode ||
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
    final total = _totalMinor;
    final description = _descriptionController.text.trim();
    if (description.length < 2 || total <= 0 || _selectedIds.isEmpty) {
      setState(
        () => _error = 'Hãy nhập nội dung, tổng tiền và chọn thành viên.',
      );
      return null;
    }
    Map<String, int>? splitAmounts;
    if (_customMode != null) {
      if (_customMode == GroupSplitMode.exact) {
        final sum = _currentExactSum;
        if (sum != total) {
          setState(() {
            if (sum > total) {
              _error =
                  'Tổng các phần chia (${MoneyFormatter.format(sum)}) đang lớn hơn tổng tiền (${MoneyFormatter.format(total)}). Tổng tiền chia phải đúng bằng tổng tiền.';
            } else {
              _error =
                  'Tổng các phần chia (${MoneyFormatter.format(sum)}) chưa đủ tổng tiền (${MoneyFormatter.format(total)}). Còn thiếu ${MoneyFormatter.format(total - sum)}.';
            }
          });
          return null;
        }
      }
      splitAmounts = _parseSplits(total);
      if (splitAmounts == null) return null;
    } else if (widget.initialExpense != null) {
      // Sửa cần số tiền tường minh: chia đều, người đầu nhận phần dư.
      final n = _selectedIds.length;
      var i = 0;
      splitAmounts = {
        for (final id in _selectedIds)
          id: total ~/ n + (i++ < total % n ? 1 : 0),
      };
    }
    return GroupExpenseDraft(
      description: description,
      totalMinor: total,
      memberIds: _selectedIds.toList(growable: false),
      splitAmounts: widget.initialExpense == null
          ? splitAmounts
          : splitAmounts!,
      equalSplit: _customMode == null,
    );
  }

  Widget _buildMemberRow(GroupMember member) {
    final controller = _splitControllers.putIfAbsent(
      member.userId,
      TextEditingController.new,
    );
    final isSelected = _selectedIds.contains(member.userId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Checkbox(
            value: isSelected,
            onChanged: (value) => _toggleMember(member.userId, value == true),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: GestureDetector(
              onTap: () => _toggleMember(member.userId, !isSelected),
              child: Text(
                member.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ),
          if (_customMode != null) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 135,
              child: TextField(
                controller: controller,
                enabled: isSelected,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (text) =>
                    _onMemberAmountChanged(member.userId, text),
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  suffixText: _customMode == GroupSplitMode.percentage
                      ? '%'
                      : '₫',
                ),
              ),
            ),
          ],
        ],
      ),
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
