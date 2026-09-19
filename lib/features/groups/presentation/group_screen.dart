import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/dialogs/confirm_dialog.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../../shared/widgets/app_callout.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../invoices/domain/invoice_models.dart';
import '../../sharing/domain/shared_bill_models.dart';
import '../data/group_service.dart';
import '../domain/group_balance_calculator.dart';
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
          SliverAppBar(
            pinned: true,
            title: const Text('Nhóm chi tiêu'),
            actions: [
              IconButton(
                tooltip: 'Mở trợ lý chi tiêu',
                onPressed: () => context.push('/chat'),
                icon: const Icon(Icons.chat_bubble_outline),
              ),
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
          if (service != null)
            const SliverToBoxAdapter(child: _DirectShareInbox()),
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
            onEditExpense: (expense) => _editExpense(details, expense),
            onDeleteExpense: _deleteExpense,
            onSetMemberRole: (userId, role) =>
                _setMemberRole(details.group.id, userId, role),
            onRemoveMember: (userId, displayName) =>
                _removeMember(details.group.id, userId, displayName),
            onLeaveGroup: () => _leaveGroup(details),
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

  Future<void> _editExpense(GroupDetails details, GroupExpense expense) async {
    final draft = await showDialog<_NewExpenseDraft>(
      context: context,
      builder: (context) =>
          _NewExpenseDialog(members: details.members, initialExpense: expense),
    );
    if (draft == null || !mounted) return;
    await _runGroupAction(() async {
      await ref
          .read(expenseGroupServiceProvider)!
          .updateCustomExpense(
            expenseId: expense.id,
            description: draft.description,
            totalMinor: draft.totalMinor,
            splitAmounts: draft.splitAmounts!,
          );
      _reloadDetails();
    });
  }

  Future<void> _deleteExpense(GroupExpense expense) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Xóa khoản chi?',
      message: '“${expense.description}” sẽ bị xóa khỏi nhóm.',
      confirmLabel: 'Xóa khoản chi',
      icon: Icons.delete_outline,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _runGroupAction(() async {
      await ref.read(expenseGroupServiceProvider)!.deleteExpense(expense.id);
      _reloadDetails();
    });
  }

  Future<void> _setMemberRole(
    String groupId,
    String userId,
    String role,
  ) async {
    await _runGroupAction(() async {
      await ref
          .read(expenseGroupServiceProvider)!
          .setMemberRole(groupId: groupId, userId: userId, role: role);
      _reloadDetails();
    });
  }

  Future<void> _removeMember(
    String groupId,
    String userId,
    String displayName,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Xóa thành viên?',
      message: '“$displayName” sẽ không thể thêm khoản chi mới vào nhóm này.',
      confirmLabel: 'Xóa thành viên',
      icon: Icons.person_remove_outlined,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _runGroupAction(() async {
      await ref
          .read(expenseGroupServiceProvider)!
          .removeMember(groupId: groupId, userId: userId);
      _reloadDetails();
    });
  }

  Future<void> _leaveGroup(GroupDetails details) async {
    final service = ref.read(expenseGroupServiceProvider);
    if (service == null) return;
    final isOwner = details.group.ownerId == service.currentUserId;
    final confirmed = await showConfirmDialog(
      context,
      title: isOwner ? 'Xóa nhóm?' : 'Rời nhóm?',
      message: isOwner
          ? 'Nhóm và toàn bộ khoản chia trong nhóm sẽ bị xóa vĩnh viễn.'
          : 'Bạn sẽ không còn xem hoặc thêm khoản chi vào nhóm này.',
      confirmLabel: isOwner ? 'Xóa nhóm' : 'Rời nhóm',
      icon: isOwner ? Icons.delete_outline : Icons.logout_outlined,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _runGroupAction(() async {
      await service.leaveGroup(details.group.id);
      if (!mounted) return;
      setState(() {
        _selectedGroup = null;
        _detailsFuture = null;
      });
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
    required this.onEditExpense,
    required this.onDeleteExpense,
    required this.onSetMemberRole,
    required this.onRemoveMember,
    required this.onLeaveGroup,
  });

  final GroupDetails details;
  final String currentUserId;
  final VoidCallback onCopyCode;
  final VoidCallback onAddExpense;
  final VoidCallback onAddReceipt;
  final Future<void> Function(String expenseId) onSettle;
  final Future<void> Function(GroupExpense expense) onEditExpense;
  final Future<void> Function(GroupExpense expense) onDeleteExpense;
  final Future<void> Function(String userId, String role) onSetMemberRole;
  final Future<void> Function(String userId, String displayName) onRemoveMember;
  final VoidCallback onLeaveGroup;

  @override
  Widget build(BuildContext context) {
    final names = {
      for (final member in details.members) member.userId: member.displayName,
    };
    final balances = _balances();
    final transfers = GroupBalanceCalculator.calculateSettlementTransfers(
      balances,
    );
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
                  _MemberTile(
                    member: member,
                    currentUserId: currentUserId,
                    isGroupOwner: details.group.ownerId == currentUserId,
                    balanceLabel: _balanceLabel(balances[member.userId] ?? 0),
                    onSetRole: onSetMemberRole,
                    onRemove: onRemoveMember,
                  ),
              ],
            ),
          ),
        ),
        if (transfers.isNotEmpty)
          _SettlementSuggestions(transfers: transfers, names: names),
        if (details.group.ownerId != currentUserId ||
            details.members.length == 1)
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onLeaveGroup,
              icon: Icon(
                details.group.ownerId == currentUserId
                    ? Icons.delete_outline
                    : Icons.logout_outlined,
              ),
              label: Text(
                details.group.ownerId == currentUserId
                    ? 'Xóa nhóm'
                    : 'Rời nhóm',
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
            canManage:
                expense.payerId == currentUserId ||
                details.group.ownerId == currentUserId,
            onEdit: () => onEditExpense(expense),
            onDelete: () => onDeleteExpense(expense),
          ),
        if (details.auditEvents.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Lịch sử hoạt động',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          for (final event in details.auditEvents)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.history_outlined),
              title: Text(_auditLabel(event, names)),
              subtitle: Text(_formatAuditDate(event.createdAt)),
            ),
        ],
      ],
    );
  }

  String _auditLabel(GroupAuditEvent event, Map<String, String> names) {
    final actor = names[event.actorId] ?? 'Tài khoản đã xóa';
    return switch (event.eventType) {
      'group_created' => '$actor đã tạo nhóm',
      'member_joined' =>
        '${names[event.targetUserId] ?? actor} đã tham gia nhóm',
      'member_role_changed' => '$actor đã cập nhật vai trò thành viên',
      'member_removed' => '$actor đã xóa một thành viên',
      'member_left' => '$actor đã rời nhóm',
      'expense_created' => '$actor đã thêm khoản chi',
      'expense_updated' => '$actor đã sửa khoản chi',
      'expense_deleted' => '$actor đã xóa khoản chi',
      'expense_settled' => '$actor đã xác nhận phần chia',
      _ => 'Có hoạt động mới trong nhóm',
    };
  }

  String _formatAuditDate(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} $hour:$minute';
  }

  Map<String, int> _balances() {
    return GroupBalanceCalculator.calculate(
      memberIds: details.members.map((member) => member.userId),
      expenses: details.expenses,
    );
  }

  String _balanceLabel(int amount) {
    if (amount == 0) return 'Đã cân bằng';
    return amount > 0
        ? 'được nhận ${MoneyFormatter.format(amount)}'
        : 'cần trả ${MoneyFormatter.format(-amount)}';
  }
}

class _DirectShareInbox extends ConsumerWidget {
  const _DirectShareInbox();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shares = ref.watch(directBillSharesProvider);
    return shares.when(
      loading: () => const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: LinearProgressIndicator(),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: AppCallout(
          tone: CalloutTone.warning,
          message: 'Không tải được hộp thư chia sẻ: ${friendlyMessage(error)}',
        ),
      ),
      data: (items) {
        final service = ref.read(sharedBillServiceProvider);
        if (service == null) return const SizedBox.shrink();
        final visible = items
            .where(
              (item) => item.status == 'pending' || item.status == 'accepted',
            )
            .take(5)
            .toList(growable: false);
        if (visible.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Hộp thư chia sẻ',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  for (final share in visible)
                    _DirectShareTile(
                      share: share,
                      currentUserId: service.currentUserId,
                      onView: () => _showShareDetails(context, share),
                      onSaveToPersonal: () =>
                          _saveShareToPersonalLedger(context, ref, share),
                      onRespond: (action) async {
                        try {
                          if (action == 'revoke') {
                            final confirmed = await showConfirmDialog(
                              context,
                              title: 'Thu hồi chia sẻ?',
                              message:
                                  'Người nhận sẽ không còn được xem hóa đơn này.',
                              confirmLabel: 'Thu hồi',
                              destructive: true,
                              icon: Icons.link_off_outlined,
                            );
                            if (!confirmed || !context.mounted) return;
                          }
                          await service.respondToDirectShare(
                            shareId: share.id,
                            action: action,
                          );
                          ref.invalidate(directBillSharesProvider);
                        } on Object catch (error) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(friendlyMessage(error))),
                          );
                        }
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showShareDetails(BuildContext context, DirectBillShare share) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(share.snapshot.sellerName),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (share.snapshot.invoiceNumber != null)
                  Text('Số hóa đơn: ${share.snapshot.invoiceNumber}'),
                if (share.snapshot.issuedAt != null)
                  Text('Ngày: ${_formatShareDate(share.snapshot.issuedAt!)}'),
                const SizedBox(height: 12),
                for (final line in share.snapshot.lines)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(line.description),
                    trailing: Text(MoneyFormatter.format(line.totalMinor)),
                  ),
                const Divider(),
                _shareMoneyRow('Tổng hóa đơn', share.totalMinor),
                _shareMoneyRow('Phần của bạn', share.recipientAmountMinor),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveShareToPersonalLedger(
    BuildContext context,
    WidgetRef ref,
    DirectBillShare share,
  ) async {
    final sourceHash = 'direct-share:${share.id}';
    final repository = ref.read(invoiceRepositoryProvider);
    try {
      final existing = await repository.findBySourceHash(sourceHash);
      if (existing != null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Phần chi này đã có trong chi tiêu cá nhân.'),
          ),
        );
        return;
      }
      final now = DateTime.now();
      final seller = share.snapshot.sellerName.trim();
      await repository.saveInvoice(
        InvoiceEntity(
          id: 'direct-share-${share.id}',
          sellerName: seller.length <= 180 ? seller : seller.substring(0, 180),
          sellerTaxCode: share.snapshot.sellerTaxCode,
          invoiceNumber: share.snapshot.invoiceNumber,
          issuedAt: share.snapshot.issuedAt ?? share.acceptedAt ?? now,
          currencyCode: share.snapshot.currencyCode,
          subtotalMinor: share.recipientAmountMinor,
          taxMinor: 0,
          totalMinor: share.recipientAmountMinor,
          sourceType: InvoiceSourceType.manual,
          sourceHash: sourceHash,
          status: InvoiceStatus.confirmed,
          notes: 'Khoản chi được chia sẻ trong hệ thống.',
          tags: const ['chia-se'],
          createdAt: now,
          updatedAt: now,
          confirmedAt: now,
          lines: [
            InvoiceLineEntity(
              id: 'direct-share-line-${share.id}',
              description: 'Phần chi được chia sẻ',
              totalMinor: share.recipientAmountMinor,
            ),
          ],
        ),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Đã lưu phần chi vào chi tiêu cá nhân. Sẽ đồng bộ lên cloud.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyMessage(error))));
    }
  }

  Widget _shareMoneyRow(String label, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(MoneyFormatter.format(value)),
        ],
      ),
    );
  }

  String _formatShareDate(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}

class _DirectShareTile extends StatelessWidget {
  const _DirectShareTile({
    required this.share,
    required this.currentUserId,
    required this.onView,
    required this.onSaveToPersonal,
    required this.onRespond,
  });

  final DirectBillShare share;
  final String currentUserId;
  final VoidCallback onView;
  final Future<void> Function() onSaveToPersonal;
  final Future<void> Function(String action) onRespond;

  @override
  Widget build(BuildContext context) {
    final incoming = share.ownerId != currentUserId;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                share.snapshot.sellerName,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                incoming
                    ? 'Người gửi chia phần của bạn: ${MoneyFormatter.format(share.recipientAmountMinor)}'
                    : share.isPending
                    ? 'Đang chờ ${share.recipientEmail} chấp nhận'
                    : 'Đã chia sẻ cho ${share.recipientEmail}',
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onView,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Xem chi tiết'),
                ),
              ),
              if (incoming && share.isPending)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => onRespond('decline'),
                      child: const Text('Từ chối'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => onRespond('accept'),
                      child: const Text('Chấp nhận'),
                    ),
                  ],
                )
              else if (share.isAccepted && incoming)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Chip(
                      avatar: Icon(Icons.check, size: 16),
                      label: Text('Đã chấp nhận'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: onSaveToPersonal,
                      icon: const Icon(Icons.add_card_outlined),
                      label: const Text('Lưu vào chi tiêu'),
                    ),
                  ],
                )
              else if (!incoming && (share.isPending || share.isAccepted))
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => onRespond('revoke'),
                    icon: const Icon(Icons.link_off_outlined),
                    label: const Text('Thu hồi'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettlementSuggestions extends StatelessWidget {
  const _SettlementSuggestions({required this.transfers, required this.names});

  final List<GroupSettlementTransfer> transfers;
  final Map<String, String> names;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Gợi ý thanh toán',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final transfer in transfers)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${names[transfer.fromUserId] ?? 'Tài khoản đã xóa'} trả '
                  '${MoneyFormatter.format(transfer.amountMinor)} cho '
                  '${names[transfer.toUserId] ?? 'Tài khoản đã xóa'}',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.currentUserId,
    required this.isGroupOwner,
    required this.balanceLabel,
    required this.onSetRole,
    required this.onRemove,
  });

  final GroupMember member;
  final String currentUserId;
  final bool isGroupOwner;
  final String balanceLabel;
  final Future<void> Function(String userId, String role) onSetRole;
  final Future<void> Function(String userId, String displayName) onRemove;

  @override
  Widget build(BuildContext context) {
    final canManage = isGroupOwner && member.userId != currentUserId;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(Icons.person_outline),
      title: Text(
        member.userId == currentUserId
            ? '${member.displayName} (Bạn)'
            : member.displayName,
      ),
      subtitle: Text(member.role == 'owner' ? 'Chủ nhóm' : 'Thành viên'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(balanceLabel),
          if (canManage)
            PopupMenuButton<String>(
              tooltip: 'Quản lý thành viên',
              onSelected: (action) {
                if (action == 'remove') {
                  unawaited(onRemove(member.userId, member.displayName));
                } else {
                  unawaited(onSetRole(member.userId, action));
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: member.role == 'owner' ? 'member' : 'owner',
                  child: Text(
                    member.role == 'owner'
                        ? 'Thu hồi quyền chủ nhóm'
                        : 'Chuyển quyền chủ nhóm',
                  ),
                ),
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Xóa khỏi nhóm'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({
    required this.expense,
    required this.names,
    required this.currentUserId,
    required this.onSettle,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  final GroupExpense expense;
  final Map<String, String> names;
  final String currentUserId;
  final Future<void> Function(String expenseId) onSettle;
  final bool canManage;
  final Future<void> Function() onEdit;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final myShare = expense.splits
        .where((item) => item.userId == currentUserId)
        .firstOrNull;
    final canSettle =
        myShare != null &&
        !myShare.isSettled &&
        expense.payerId != currentUserId;
    final hasSettlement = expense.splits.any((split) => split.isSettled);
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
                if (canManage && !hasSettlement)
                  PopupMenuButton<String>(
                    tooltip: 'Quản lý khoản chi',
                    onSelected: (value) {
                      if (value == 'edit') {
                        onEdit();
                      } else {
                        onDelete();
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Sửa khoản chi'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('Xóa khoản chi'),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Người trả: ${names[expense.payerId] ?? 'Tài khoản đã xóa'}'),
            if (expense.isSharedInvoice)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(Icons.share_outlined, size: 16),
                    SizedBox(width: 6),
                    Text('Hóa đơn được chia sẻ từ hóa đơn cá nhân'),
                  ],
                ),
              ),
            if (hasSettlement)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Đã có thanh toán: không thể sửa hoặc xóa. Hãy tạo khoản điều chỉnh mới nếu cần.',
                ),
              ),
            for (final split in expense.splits)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  split.userId == null
                      ? 'Tài khoản đã xóa'
                      : names[split.userId!] ?? 'Thành viên',
                ),
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
    if (lines.isEmpty && widget.invoice.totalMinor > 0) {
      lines.add(
        _InvoiceAllocationLine(
          description: 'Tổng hóa đơn',
          amount: widget.invoice.totalMinor,
        ),
      );
      return lines;
    }
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
  const _NewExpenseDialog({required this.members, this.initialExpense});

  final List<GroupMember> members;
  final GroupExpense? initialExpense;

  @override
  State<_NewExpenseDialog> createState() => _NewExpenseDialogState();
}

class _NewExpenseDialogState extends State<_NewExpenseDialog> {
  late final TextEditingController _descriptionController;
  late final TextEditingController _amountController;
  final Map<String, TextEditingController> _splitControllers = {};
  late final Set<String> _selectedIds;
  late GroupSplitMode? _customMode;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialExpense;
    _descriptionController = TextEditingController(text: initial?.description);
    _amountController = TextEditingController(
      text: initial?.totalMinor.toString(),
    );
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
    return AlertDialog(
      title: Text(
        widget.initialExpense == null ? 'Thêm khoản chi' : 'Sửa khoản chi',
      ),
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
        FilledButton(
          onPressed: _submit,
          child: Text(
            widget.initialExpense == null ? 'Tạo bản ghi' : 'Lưu thay đổi',
          ),
        ),
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
        splitAmounts: widget.initialExpense == null
            ? splitAmounts
            : splitAmounts!,
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
