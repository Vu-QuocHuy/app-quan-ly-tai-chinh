import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../invoices/domain/invoice_models.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../../shared/widgets/app_callout.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../data/group_service.dart';
import '../domain/group_models.dart';
import '../domain/group_split_calculator.dart';

class GroupScreen extends ConsumerStatefulWidget {
  const GroupScreen({super.key});

  @override
  ConsumerState<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends ConsumerState<GroupScreen> {
  ExpenseGroup? _selectedGroup;
  Future<GroupDetails>? _detailsFuture;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(expenseGroupServiceProvider);
    final groups = ref.watch(expenseGroupsProvider);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            pinned: true,
            title: const Text('Nhóm chi tiêu'),
            actions: [
              IconButton(
                tooltip: 'Làm mới nhóm',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _buildActions(context, service),
            ),
          ),
          if (service == null)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: AppEmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Nhóm cần kết nối tài khoản',
                message: 'Đăng nhập Supabase để tạo hoặc tham gia nhóm.',
              ),
            )
          else
            ...switch (groups) {
              AsyncData(value: final items) when items.isEmpty => [
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppEmptyState(
                    icon: Icons.groups_outlined,
                    title: 'Chưa có nhóm chi tiêu',
                    message:
                        'Tạo nhóm cho chuyến đi, bữa ăn hoặc mua sắm chung.',
                  ),
                ),
              ],
              AsyncData(value: final items) => [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _buildGroupCard(items[index]),
                  ),
                ),
                if (_selectedGroup != null)
                  SliverToBoxAdapter(child: _buildDetailsSection(context)),
              ],
              AsyncError(error: final error) => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'Không thể tải nhóm: ${friendlyMessage(error)}',
                    ),
                  ),
                ),
              ],
              _ => [
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
            },
          const SliverToBoxAdapter(child: SizedBox(height: 112)),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, ExpenseGroupService? service) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: service == null || _busy ? null : _createGroup,
            icon: const Icon(Icons.add),
            label: const Text('Tạo nhóm'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: service == null || _busy ? null : _joinGroup,
            icon: const Icon(Icons.login_outlined),
            label: const Text('Tham gia'),
          ),
        ),
      ],
    );
  }

  Widget _buildGroupCard(ExpenseGroup group) {
    final selected = _selectedGroup?.id == group.id;
    return Card(
      color: selected ? Theme.of(context).colorScheme.secondaryContainer : null,
      child: ListTile(
        selected: selected,
        leading: const CircleAvatar(child: Icon(Icons.groups_outlined)),
        title: Text(group.name),
        subtitle: Text('Mã mời: ${group.inviteCode}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _selectGroup(group),
      ),
    );
  }

  Widget _buildDetailsSection(BuildContext context) {
    final future = _detailsFuture;
    if (future == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: FutureBuilder<GroupDetails>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return AppCallout(
              tone: CalloutTone.danger,
              message:
                  'Không thể tải chi tiết nhóm: ${friendlyMessage(snapshot.error!)}',
            );
          }
          final details = snapshot.data;
          if (details == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return _GroupDetails(
            details: details,
            currentUserId: ref.read(expenseGroupServiceProvider)!.currentUserId,
            onCopyCode: () => _copyInviteCode(details.group.inviteCode),
            onAddExpense: () => _addExpense(details),
            onAddReceipt: () => _addReceipt(details),
            onSettle: _settleShare,
          );
        },
      ),
    );
  }

  void _selectGroup(ExpenseGroup group) {
    final service = ref.read(expenseGroupServiceProvider);
    if (service == null) return;
    setState(() {
      _selectedGroup = group;
      _detailsFuture = service.loadDetails(group);
    });
  }

  Future<void> _createGroup() async {
    final name = await _askText(
      title: 'Tạo nhóm chi tiêu',
      label: 'Tên nhóm',
      hint: 'Ví dụ: Team đi ăn tối',
      confirmLabel: 'Tạo nhóm',
    );
    if (name == null) return;
    await _runGroupAction(() async {
      final group = await ref
          .read(expenseGroupServiceProvider)!
          .createGroup(name);
      _selectGroup(group);
    });
  }

  Future<void> _joinGroup() async {
    final code = await _askText(
      title: 'Tham gia nhóm',
      label: 'Mã mời',
      hint: 'Nhập mã 8 ký tự',
      confirmLabel: 'Tham gia',
    );
    if (code == null) return;
    await _runGroupAction(() async {
      final group = await ref
          .read(expenseGroupServiceProvider)!
          .joinGroup(code);
      _selectGroup(group);
    });
  }

  Future<String?> _askText({
    required String title,
    required String label,
    required String hint,
    required String confirmLabel,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: Text(confirmLabel),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _addExpense(GroupDetails details) async {
    final draft = await showDialog<_NewExpenseDraft>(
      context: context,
      builder: (context) => _NewExpenseDialog(members: details.members),
    );
    if (draft == null) return;
    await _runGroupAction(() async {
      final service = ref.read(expenseGroupServiceProvider)!;
      if (draft.splitAmounts == null) {
        await service.addEqualExpense(
          groupId: details.group.id,
          description: draft.description,
          totalMinor: draft.totalMinor,
          memberIds: draft.memberIds,
        );
      } else {
        await service.addCustomExpense(
          groupId: details.group.id,
          description: draft.description,
          totalMinor: draft.totalMinor,
          splitAmounts: draft.splitAmounts!,
        );
      }
      _reloadDetails();
    });
  }

  Future<void> _settleShare(String expenseId) async {
    await _runGroupAction(() async {
      await ref.read(expenseGroupServiceProvider)!.settleMyShare(expenseId);
      _reloadDetails();
    });
  }

  Future<void> _addReceipt(GroupDetails details) async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
      maxWidth: 2400,
    );
    if (image == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final bytes = await image.readAsBytes();
      final outcome = await ref
          .read(importCoordinatorProvider)
          .importImage(
            bytes: bytes,
            fileName: image.name,
            imagePath: image.path,
          );
      if (!mounted) return;
      final allocation = await showDialog<_InvoiceAllocationDraft>(
        context: context,
        builder: (context) => _InvoiceAllocationDialog(
          invoice: outcome.result.invoice,
          members: details.members,
        ),
      );
      if (allocation == null) return;
      await ref
          .read(expenseGroupServiceProvider)!
          .addCustomExpense(
            groupId: details.group.id,
            description: 'Hóa đơn ${outcome.result.invoice.sellerName}',
            totalMinor: outcome.result.invoice.totalMinor,
            splitAmounts: allocation.splitAmounts,
          );
      _reloadDetails();
      ref.invalidate(expenseGroupsProvider);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể xử lý hóa đơn: ${friendlyMessage(error)}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runGroupAction(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(expenseGroupsProvider);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reloadDetails() {
    final service = ref.read(expenseGroupServiceProvider);
    final group = _selectedGroup;
    if (service == null || group == null) return;
    setState(() => _detailsFuture = service.loadDetails(group));
  }

  void _refresh() {
    ref.invalidate(expenseGroupsProvider);
    _reloadDetails();
  }

  Future<void> _copyInviteCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đã sao chép mã mời nhóm.')));
  }
}

class _GroupDetails extends StatelessWidget {
  const _GroupDetails({
    required this.details,
    required this.currentUserId,
    required this.onCopyCode,
    required this.onAddExpense,
    required this.onAddReceipt,
    required this.onSettle,
  });

  final GroupDetails details;
  final String currentUserId;
  final VoidCallback onCopyCode;
  final VoidCallback onAddExpense;
  final VoidCallback onAddReceipt;
  final Future<void> Function(String expenseId) onSettle;

  @override
  Widget build(BuildContext context) {
    final names = {
      for (final member in details.members) member.userId: member.displayName,
    };
    final balances = _balances();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  details.group.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text('Mã mời: ${details.group.inviteCode}'),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onCopyCode,
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Sao chép mã mời'),
                  ),
                ),
                const Divider(),
                Text(
                  'Thành viên (${details.members.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final member in details.members)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.person_outline),
                    title: Text(
                      member.userId == currentUserId
                          ? '${member.displayName} (Bạn)'
                          : member.displayName,
                    ),
                    trailing: Text(_balanceLabel(balances[member.userId] ?? 0)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onAddExpense,
                icon: const Icon(Icons.add_card_outlined),
                label: const Text('Thêm khoản chi'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onAddReceipt,
                icon: const Icon(Icons.document_scanner_outlined),
                label: const Text('Từ hóa đơn'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Khoản chi', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (details.expenses.isEmpty)
          const Text('Chưa có khoản chi nào trong nhóm.'),
        for (final expense in details.expenses)
          _ExpenseCard(
            expense: expense,
            names: names,
            currentUserId: currentUserId,
            onSettle: onSettle,
          ),
      ],
    );
  }

  Map<String, int> _balances() {
    final result = {for (final member in details.members) member.userId: 0};
    for (final expense in details.expenses) {
      result[expense.payerId] =
          (result[expense.payerId] ?? 0) + expense.totalMinor;
      for (final split in expense.splits) {
        result[split.userId] = (result[split.userId] ?? 0) - split.amountMinor;
      }
    }
    return result;
  }

  String _balanceLabel(int amount) {
    if (amount == 0) return 'Đã cân bằng';
    return amount > 0
        ? 'được nhận ${MoneyFormatter.format(amount)}'
        : 'cần trả ${MoneyFormatter.format(-amount)}';
  }
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({
    required this.expense,
    required this.names,
    required this.currentUserId,
    required this.onSettle,
  });

  final GroupExpense expense;
  final Map<String, String> names;
  final String currentUserId;
  final Future<void> Function(String expenseId) onSettle;

  @override
  Widget build(BuildContext context) {
    final myShare = expense.splits
        .where((item) => item.userId == currentUserId)
        .firstOrNull;
    final canSettle =
        myShare != null &&
        !myShare.isSettled &&
        expense.payerId != currentUserId;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    expense.description,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  MoneyFormatter.format(expense.totalMinor),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Người trả: ${names[expense.payerId] ?? 'Thành viên'}'),
            for (final split in expense.splits)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(names[split.userId] ?? 'Thành viên'),
                trailing: Text(
                  '${MoneyFormatter.format(split.amountMinor)}${split.isSettled ? ' · Đã trả' : ''}',
                ),
              ),
            if (canSettle)
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => onSettle(expense.id),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Tôi đã thanh toán'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NewExpenseDraft {
  const _NewExpenseDraft({
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

class _InvoiceAllocationDraft {
  const _InvoiceAllocationDraft(this.splitAmounts);

  final Map<String, int> splitAmounts;
}

class _InvoiceAllocationLine {
  const _InvoiceAllocationLine({
    required this.description,
    required this.amount,
  });

  final String description;
  final int amount;
}

class _InvoiceAllocationDialog extends StatefulWidget {
  const _InvoiceAllocationDialog({
    required this.invoice,
    required this.members,
  });

  final InvoiceEntity invoice;
  final List<GroupMember> members;

  @override
  State<_InvoiceAllocationDialog> createState() =>
      _InvoiceAllocationDialogState();
}

class _InvoiceAllocationDialogState extends State<_InvoiceAllocationDialog> {
  late final List<_InvoiceAllocationLine> _lines = _buildLines();
  late final List<String> _assignees = List.filled(
    _lines.length,
    widget.members.first.userId,
  );
  String? _error;

  List<_InvoiceAllocationLine> _buildLines() {
    final lines = widget.invoice.lines
        .where((line) => line.totalMinor > 0)
        .map(
          (line) => _InvoiceAllocationLine(
            description: line.description,
            amount: line.totalMinor,
          ),
        )
        .toList(growable: true);
    final lineTotal = lines.fold<int>(0, (sum, line) => sum + line.amount);
    final remainder = widget.invoice.totalMinor - lineTotal;
    if (remainder > 0) {
      lines.add(
        _InvoiceAllocationLine(
          description: 'Thuế, phí hoặc khoản khác',
          amount: remainder,
        ),
      );
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Phân chia hóa đơn'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.invoice.sellerName} · ${MoneyFormatter.format(widget.invoice.totalMinor)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text('Kiểm tra dòng OCR và chọn người chịu từng dòng.'),
              const SizedBox(height: 12),
              for (var index = 0; index < _lines.length; index++)
                _buildLine(index),
              if (_lines.isEmpty)
                const Text('Không nhận diện được dòng hàng để phân chia.'),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Xác nhận chia')),
      ],
    );
  }

  Widget _buildLine(int index) {
    final line = _lines[index];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${line.description}\n${MoneyFormatter.format(line.amount)}',
              ),
            ),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String>(
                initialValue: _assignees[index],
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Người chịu'),
                items: widget.members
                    .map(
                      (member) => DropdownMenuItem(
                        value: member.userId,
                        child: Text(
                          member.displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) setState(() => _assignees[index] = value);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    if (_lines.isEmpty) {
      setState(() => _error = 'Không có dòng hợp lệ để phân chia.');
      return;
    }
    final splitAmounts = <String, int>{};
    for (var index = 0; index < _lines.length; index++) {
      final userId = _assignees[index];
      splitAmounts[userId] = (splitAmounts[userId] ?? 0) + _lines[index].amount;
    }
    final total = splitAmounts.values.fold<int>(
      0,
      (sum, amount) => sum + amount,
    );
    if (total != widget.invoice.totalMinor) {
      setState(() => _error = 'Các dòng chưa khớp tổng hóa đơn.');
      return;
    }
    Navigator.pop(context, _InvoiceAllocationDraft(splitAmounts));
  }
}

class _NewExpenseDialog extends StatefulWidget {
  const _NewExpenseDialog({required this.members});

  final List<GroupMember> members;

  @override
  State<_NewExpenseDialog> createState() => _NewExpenseDialogState();
}

class _NewExpenseDialogState extends State<_NewExpenseDialog> {
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final Map<String, TextEditingController> _splitControllers = {};
  late final Set<String> _selectedIds = widget.members
      .map((item) => item.userId)
      .toSet();
  GroupSplitMode? _customMode;
  String? _error;

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
    return AlertDialog(
      title: const Text('Thêm khoản chi'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _descriptionController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nội dung chi'),
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
                ButtonSegment(
                  value: GroupSplitMode.exact,
                  label: Text('Số tiền'),
                ),
                ButtonSegment(
                  value: GroupSplitMode.percentage,
                  label: Text('%'),
                ),
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
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Tạo bản ghi')),
      ],
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

  void _submit() {
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
      return;
    }
    Map<String, int>? splitAmounts;
    if (_customMode != null) {
      splitAmounts = _parseSplits(total);
      if (splitAmounts == null) return;
    }
    Navigator.pop(
      context,
      _NewExpenseDraft(
        description: description,
        totalMinor: total,
        memberIds: _selectedIds.toList(growable: false),
        splitAmounts: splitAmounts,
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
            : 'Tổng các phần tiền phải bằng tổng khoản chi.',
      );
      return null;
    }
    return amounts;
  }
}
