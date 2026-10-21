import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../app/theme/finance_colors.dart';
import '../../../shared/dialogs/confirm_dialog.dart';
import '../../../shared/errors/error_presenter.dart';
import '../domain/group_models.dart';
import 'fund_progress_card.dart';

class GroupFundScreen extends ConsumerStatefulWidget {
  const GroupFundScreen({required this.groupId, super.key});
  final String groupId;

  @override
  ConsumerState<GroupFundScreen> createState() => _GroupFundScreenState();
}

class _GroupFundScreenState extends ConsumerState<GroupFundScreen> {
  late Future<_FundSnapshot> _future;
  Timer? _pollTimer;
  bool _fetching = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) => _refresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<_FundSnapshot> _load() async {
    _fetching = true;
    try {
      final service = ref.read(expenseGroupServiceProvider);
      if (service == null) throw StateError('Hãy đăng nhập để dùng quỹ chung.');
      final groups = await service.listGroups();
      final group = groups
          .where((item) => item.id == widget.groupId)
          .firstOrNull;
      if (group == null) {
        throw StateError('Bạn không còn là thành viên của nhóm này.');
      }
      final details = await service.loadDetails(group);
      final entries = await service.listFundEntries(group.id);
      return _FundSnapshot(details, entries);
    } finally {
      _fetching = false;
    }
  }

  void _refresh({bool force = false}) {
    if (!mounted || _fetching || (_busy && !force)) return;
    setState(() => _future = _load());
  }

  Future<void> _add(String kind) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    String? error;
    final entry = await showDialog<({int amount, String note})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(kind == 'deposit' ? 'Thu vào quỹ' : 'Chi từ quỹ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Số tiền',
                  suffixText: '₫',
                ),
              ),
              if (kind == 'expense')
                TextField(
                  controller: noteController,
                  maxLength: 160,
                  decoration: const InputDecoration(labelText: 'Nội dung chi'),
                ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                final amount = MoneyFormatter.tryParse(amountController.text);
                if (amount == null ||
                    amount < 1 ||
                    amount > 9007199254740991 ||
                    (kind == 'expense' && noteController.text.trim().isEmpty)) {
                  setDialogState(
                    () => error = 'Nhập số tiền và nội dung hợp lệ.',
                  );
                  return;
                }
                Navigator.pop(context, (
                  amount: amount,
                  note: noteController.text.trim(),
                ));
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    amountController.dispose();
    noteController.dispose();
    if (entry == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(expenseGroupServiceProvider)!
          .addFundEntry(
            groupId: widget.groupId,
            kind: kind,
            amountMinor: entry.amount,
            note: entry.note,
          );
      if (mounted) _refresh(force: true);
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

  Future<void> _delete(GroupFundEntry entry) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Xóa giao dịch quỹ?',
      message: 'Số dư quỹ chung sẽ được tính lại cho mọi thành viên.',
      confirmLabel: 'Xóa',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(expenseGroupServiceProvider)!.deleteFundEntry(entry.id);
      if (mounted) _refresh(force: true);
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

  Future<void> _editGoal(ExpenseGroup group) async {
    final result = await showDialog<({int? goalMinor, DateTime? deadline})>(
      context: context,
      builder: (_) => _FundGoalDialog(
        initialGoalMinor: group.fundGoalMinor,
        initialDeadline: group.fundDeadline,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(expenseGroupServiceProvider)!
          .setFundGoal(
            groupId: widget.groupId,
            goalMinor: result.goalMinor,
            deadline: result.deadline,
          );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyMessage(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _refresh(force: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Quỹ chung'),
      actions: [
        IconButton(
          onPressed: _refresh,
          tooltip: 'Làm mới',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<_FundSnapshot>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done &&
            snapshot.data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Không thể tải quỹ: ${friendlyMessage(snapshot.error!)}',
              ),
            ),
          );
        }
        final data = snapshot.data!;
        final currentUserId = ref
            .read(expenseGroupServiceProvider)!
            .currentUserId;
        final names = {
          for (final member in data.details.members)
            member.userId: member.displayName,
        };
        final balance = data.entries.fold<int>(
          0,
          (sum, entry) =>
              sum +
              (entry.kind == 'deposit'
                  ? entry.amountMinor
                  : -entry.amountMinor),
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          children: [
            if (_busy) const LinearProgressIndicator(),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.details.group.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Số dư quỹ',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      MoneyFormatter.format(balance),
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Mọi thành viên có thể ghi thu và chi. Quỹ được theo dõi riêng với khoản chia tiền trong nhóm.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FundProgressCard(
              balanceMinor: balance,
              goalMinor: data.details.group.fundGoalMinor,
              deadline: data.details.group.fundDeadline,
              isOwner: data.details.group.ownerId == currentUserId,
              onEditGoal: () => _editGoal(data.details.group),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _add('deposit'),
                    icon: const Icon(Icons.add),
                    label: const Text('Thu vào quỹ'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy || balance <= 0
                        ? null
                        : () => _add('expense'),
                    icon: const Icon(Icons.remove),
                    label: const Text('Chi từ quỹ'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Lịch sử quỹ', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (data.entries.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Chưa có giao dịch quỹ.'),
                ),
              ),
            for (final entry in data.entries)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      entry.kind == 'deposit'
                          ? Icons.south_west
                          : Icons.north_east,
                    ),
                  ),
                  title: Text(
                    entry.kind == 'deposit' ? 'Thu vào quỹ' : entry.note,
                  ),
                  subtitle: Text(
                    '${names[entry.actorId] ?? (entry.actorId == null ? 'Tài khoản đã xóa' : 'Thành viên')} · ${entry.createdAt.day}/${entry.createdAt.month}/${entry.createdAt.year}',
                  ),
                  trailing: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${entry.kind == 'deposit' ? '+' : '−'}${MoneyFormatter.format(entry.amountMinor)}',
                        style: TextStyle(
                          color: entry.kind == 'deposit'
                              ? Theme.of(
                                  context,
                                ).extension<AppFinanceColors>()!.income.color
                              : Theme.of(
                                  context,
                                ).extension<AppFinanceColors>()!.expense.color,
                        ),
                      ),
                      if (entry.actorId == currentUserId ||
                          data.details.group.ownerId == currentUserId)
                        InkWell(
                          onTap: _busy ? null : () => _delete(entry),
                          child: const Text('Xóa'),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _FundSnapshot {
  const _FundSnapshot(this.details, this.entries);
  final GroupDetails details;
  final List<GroupFundEntry> entries;
}

class _FundGoalDialog extends StatefulWidget {
  const _FundGoalDialog({this.initialGoalMinor, this.initialDeadline});

  final int? initialGoalMinor;
  final DateTime? initialDeadline;

  @override
  State<_FundGoalDialog> createState() => _FundGoalDialogState();
}

class _FundGoalDialogState extends State<_FundGoalDialog> {
  late final TextEditingController _amountController = TextEditingController(
    text: widget.initialGoalMinor?.toString(),
  );
  late DateTime? _deadline = widget.initialDeadline;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = _deadline;
    final picked = await showDatePicker(
      context: context,
      initialDate: current == null || current.isBefore(today) ? today : current,
      firstDate: today,
      lastDate: DateTime(today.year + 10, 12, 31),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  void _save() {
    final amount = MoneyFormatter.tryParse(_amountController.text);
    if (amount == null || amount < 1 || amount > 9007199254740991) {
      setState(() => _error = 'Nhập số tiền mục tiêu hợp lệ.');
      return;
    }
    Navigator.pop(context, (goalMinor: amount, deadline: _deadline));
  }

  @override
  Widget build(BuildContext context) {
    final deadline = _deadline;
    return AlertDialog(
      title: const Text('Mục tiêu quỹ'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _amountController,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Số tiền mục tiêu',
              suffixText: '₫',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  deadline == null
                      ? 'Không có hạn'
                      : 'Hạn ${deadline.day}/${deadline.month}/${deadline.year}',
                ),
              ),
              TextButton(
                onPressed: _pickDeadline,
                child: Text(deadline == null ? 'Chọn hạn' : 'Đổi hạn'),
              ),
              if (deadline != null)
                IconButton(
                  tooltip: 'Bỏ hạn',
                  onPressed: () => setState(() => _deadline = null),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
      actions: [
        if (widget.initialGoalMinor != null)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, (goalMinor: null, deadline: null)),
            child: const Text('Xóa mục tiêu'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(onPressed: _save, child: const Text('Lưu')),
      ],
    );
  }
}
