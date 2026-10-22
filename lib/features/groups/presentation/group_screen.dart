import '../../../shared/widgets/finmi_page_header.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/localization/app_strings.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/dialogs/confirm_dialog.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../../shared/widgets/app_callout.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/qr_scan_screen.dart';
import '../../../shared/widgets/app_refresh.dart';
import '../../invoices/domain/invoice_models.dart';
import '../../sharing/domain/shared_bill_models.dart';
import '../data/group_service.dart';
import '../domain/group_balance_calculator.dart';
import '../domain/group_models.dart';
import '../domain/invite_link.dart';
import 'bill_invite_qr_sheet.dart';
import 'external_bills_section.dart';
import 'group_expense_dialog.dart';
import 'group_invite_qr_sheet.dart';
import 'group_split_dialog.dart';

class GroupScreen extends ConsumerStatefulWidget {
  const GroupScreen({super.key});

  @override
  ConsumerState<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends ConsumerState<GroupScreen> {
  final _externalBillsKey = GlobalKey();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(expenseGroupServiceProvider);
    final groups = ref.watch(expenseGroupsProvider);
    return Scaffold(
      body: AppRefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            FinmiSliverHeader(
              title: context.tr.navGroups,
              actions: [
                FinmiHeaderAction(
                  tooltip: context.tr.refreshGroups,
                  onPressed: _refresh,
                  icon: Icons.refresh,
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: _buildActions(context, service),
              ),
            ),
            if (service != null)
              const SliverToBoxAdapter(child: _DirectShareInbox()),
            if (service != null)
              SliverToBoxAdapter(
                child: ExternalBillsSection(key: _externalBillsKey),
              ),
            if (service == null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: AppEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: context.tr.isEn
                      ? 'Account connection needed'
                      : 'Nhóm cần kết nối tài khoản',
                  message: context.tr.groupNeedsAuth,
                ),
              )
            else
              ...switch (groups) {
                AsyncData(value: final items) when items.isEmpty => [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: AppEmptyState(
                      icon: Icons.groups_outlined,
                      title: context.tr.noGroupsYet,
                      message: context.tr.noGroupsDesc,
                    ),
                  ),
                ],
                AsyncData(value: final items) => [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Text(
                        context.tr.myGroups,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) =>
                          _buildGroupCard(items[index]),
                    ),
                  ),
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
            label: Text(context.tr.createGroup),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: service == null || _busy ? null : _joinGroup,
            icon: const Icon(Icons.login_outlined),
            label: Text(context.tr.joinGroup),
          ),
        ),
      ],
    );
  }

  Widget _buildGroupCard(ExpenseGroup group) {
    return Card(
      child: ListTile(
        leading: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            Icons.groups_outlined,
            size: 20,
            color: Theme.of(context).colorScheme.onPrimary,
          ),
        ),
        title: Text(group.name),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/groups/${group.id}'),
      ),
    );
  }

  Future<void> _createGroup() async {
    final tr = context.tr;
    final name = await _askText(
      title: tr.createGroup,
      label: tr.groupNameLabel,
      hint: tr.groupNameHint,
      confirmLabel: tr.createGroup,
    );
    if (name == null) return;
    ExpenseGroup? createdGroup;
    await _runGroupAction(() async {
      createdGroup = await ref
          .read(expenseGroupServiceProvider)!
          .createGroup(name);
    });
    final group = createdGroup;
    if (!mounted || group == null) return;
    await context.push('/groups/${group.id}');
  }

  Future<void> _joinGroup() async {
    final tr = context.tr;
    final method = await showModalBottomSheet<_JoinMethod>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: Text(tr.scanQrCode),
              onTap: () => Navigator.pop(context, _JoinMethod.scan),
            ),
            ListTile(
              leading: const Icon(Icons.keyboard_outlined),
              title: Text(tr.enterInviteCode),
              onTap: () => Navigator.pop(context, _JoinMethod.type),
            ),
          ],
        ),
      ),
    );
    if (method == null || !mounted) return;
    final InviteLink? link;
    switch (method) {
      case _JoinMethod.scan:
        final raw = await Navigator.of(context).push<String>(
          MaterialPageRoute(
            builder: (_) => QrScanScreen(
              title: tr.scanInviteQr,
              validate: (raw) =>
                  InviteLink.parse(raw) == null ? tr.invalidQrInvite : null,
            ),
          ),
        );
        link = raw == null ? null : InviteLink.parse(raw);
      case _JoinMethod.type:
        final text = await _askText(
          title: tr.joinGroupOrBill,
          label: tr.inviteCodeLabel,
          hint: tr.inviteCodeHint,
          confirmLabel: tr.joinGroup,
        );
        if (text == null) return;
        link = InviteLink.parse(text);
        if (link == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Mã mời phải có 8 ký tự (nhóm) hoặc 10 ký tự (bill), '
                'gồm 0-9 và A-F.',
              ),
            ),
          );
        }
    }
    switch (link) {
      case GroupInviteLink(:final code):
        await _joinGroupByCode(code);
      case BillInviteLink(:final code):
        await _joinBill(code);
      case null:
        return;
    }
  }

  Future<void> _joinGroupByCode(String inviteCode) async {
    ExpenseGroup? joinedGroup;
    await _runGroupAction(() async {
      joinedGroup = await ref
          .read(expenseGroupServiceProvider)!
          .joinGroup(inviteCode);
    });
    final group = joinedGroup;
    if (!mounted || group == null) return;
    await context.push('/groups/${group.id}');
  }

  /// Vào bill: thành viên nhóm thì mở màn nhóm, người ngoài thì cuộn tới
  /// mục "Bill bạn tham gia".
  Future<void> _joinBill(String code) async {
    var joined = false;
    String? groupId;
    await _runGroupAction(() async {
      final service = ref.read(expenseGroupServiceProvider)!;
      final expenseId = await service.joinBill(code);
      groupId = await service.expenseGroupIdOf(expenseId);
      joined = true;
    });
    if (!joined || !mounted) return;
    ref.invalidate(externalBillsProvider);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đã vào bill')));
    final id = groupId;
    if (id != null) {
      await context.push('/groups/$id');
      return;
    }
    try {
      await ref.read(externalBillsProvider.future);
    } on Object catch (_) {
      // Lỗi tải đã hiện ngay trong mục "Bill bạn tham gia".
    }
    final section = _externalBillsKey.currentContext;
    if (section == null || !section.mounted) return;
    await Scrollable.ensureVisible(
      section,
      duration: const Duration(milliseconds: 300),
    );
  }

  Future<String?> _askText({
    required String title,
    required String label,
    required String hint,
    required String confirmLabel,
  }) {
    // Không dispose khi dialog trả kết quả: TextField còn dùng controller
    // trong animation đóng dialog. Controller không còn ai giữ sẽ được GC thu.
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
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                final discard = await showDiscardChangesDialog(context);
                if (!discard || !context.mounted) return;
              }
              Navigator.pop(context);
            },
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
    );
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

  Future<void> _refresh() async {
    ref.invalidate(directBillSharesProvider);
    ref.invalidate(externalBillsProvider);
    ref.invalidate(expenseGroupsProvider);
    try {
      await Future.wait([
        ref.read(expenseGroupsProvider.future),
        ref.read(externalBillsProvider.future),
      ]);
    } on Object {
      // Lỗi đã được hiển thị qua trạng thái lỗi của danh sách nhóm và mục
      // "Bill bạn tham gia".
    }
  }
}

class GroupDetailScreen extends ConsumerStatefulWidget {
  const GroupDetailScreen({required this.groupId, super.key});

  final String groupId;

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> {
  bool _busy = false;
  bool _showAllMembers = false;
  bool _showAllExpenses = false;

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(expenseGroupDetailsProvider(widget.groupId));
    final service = ref.watch(expenseGroupServiceProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr.isEn
              ? 'Back to groups'
              : 'Quay lại danh sách nhóm',
          onPressed: _goBack,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(
          details.asData?.value.group.name ??
              (context.tr.isEn ? 'Group details' : 'Chi tiết nhóm'),
        ),
        actions: [
          IconButton(
            tooltip: context.tr.isEn
                ? 'Refresh group'
                : 'Làm mới chi tiết nhóm',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
          if (details.asData?.value case final groupDetails?)
            if (groupDetails.group.ownerId == service?.currentUserId ||
                groupDetails.members.length == 1)
              PopupMenuButton<String>(
                tooltip: context.tr.isEn ? 'Group options' : 'Tùy chọn nhóm',
                onSelected: (_) => _leaveGroup(groupDetails),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'leave',
                    child: Text(
                      groupDetails.group.ownerId == service?.currentUserId
                          ? (context.tr.isEn ? 'Delete group' : 'Xóa nhóm')
                          : (context.tr.isEn ? 'Leave group' : 'Rời nhóm'),
                    ),
                  ),
                ],
              ),
        ],
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: details.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.groups_outlined, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        'Không thể tải chi tiết nhóm: ${friendlyMessage(error)}',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: Text(context.tr.retry),
                      ),
                    ],
                  ),
                ),
              ),
              data: (groupDetails) {
                final currentUserId = service?.currentUserId;
                if (currentUserId == null) {
                  return AppEmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: context.tr.isEn
                        ? 'Account connection needed'
                        : 'Nhóm cần kết nối tài khoản',
                    message: context.tr.groupNeedsAuth,
                  );
                }
                return AppRefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                    children: [
                      _GroupDetails(
                        details: groupDetails,
                        currentUserId: currentUserId,
                        busy: _busy,
                        onShowInviteQr: () => showGroupInviteQrSheet(
                          context,
                          groupName: groupDetails.group.name,
                          inviteCode: groupDetails.group.inviteCode,
                        ),
                        onSplitMoney: () => _splitMoney(groupDetails),
                        onSettle: _settleShare,
                        onShowBillQr: _showBillQr,
                        onEditExpense: (expense) =>
                            _editExpense(groupDetails, expense),
                        onDeleteExpense: _deleteExpense,
                        onSetMemberRole: (userId, role) =>
                            _setMemberRole(groupDetails.group.id, userId, role),
                        onRemoveMember: (userId, displayName) => _removeMember(
                          groupDetails.group.id,
                          userId,
                          displayName,
                        ),
                        showAllMembers: _showAllMembers,
                        onToggleMembers: () =>
                            setState(() => _showAllMembers = !_showAllMembers),
                        showAllExpenses: _showAllExpenses,
                        onToggleExpenses: () => setState(
                          () => _showAllExpenses = !_showAllExpenses,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _splitMoney(GroupDetails details) async {
    final draft = await showDialog<GroupExpenseDraft>(
      context: context,
      builder: (context) =>
          GroupSplitDialog(members: details.members, onScan: _scanReceipt),
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
    });
  }

  Future<void> _settleShare(String expenseId) async {
    await _runGroupAction(() async {
      await ref.read(expenseGroupServiceProvider)!.settleMyShare(expenseId);
    });
  }

  Future<void> _showBillQr(GroupExpense expense) async {
    String? code;
    await _runGroupAction(() async {
      code = await ref
          .read(expenseGroupServiceProvider)!
          .openBillInvite(expense.id);
    });
    final joinCode = code;
    if (joinCode == null || !mounted) return;
    await showBillInviteQrSheet(
      context,
      description: expense.description,
      joinCode: joinCode,
      onCloseInvite: () => _runGroupAction(() async {
        await ref
            .read(expenseGroupServiceProvider)!
            .closeBillInvite(expense.id);
      }),
    );
  }

  Future<void> _editExpense(GroupDetails details, GroupExpense expense) async {
    final memberIds = {for (final member in details.members) member.userId};
    final members = [
      ...details.members,
      // Người ngoài nhóm đã vào bill: hiện trong dialog để sửa không xóa họ.
      for (final split in expense.splits)
        if (split.userId != null && !memberIds.contains(split.userId))
          GroupMember(
            userId: split.userId!,
            displayName: '${split.participantName ?? 'Thành viên'} (Khách)',
            role: 'member',
          ),
    ];
    final draft = await showDialog<GroupExpenseDraft>(
      context: context,
      builder: (context) =>
          GroupExpenseDialog(members: members, initialExpense: expense),
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
            splitMode: draft.equalSplit ? 'equal' : 'custom',
          );
    });
  }

  Future<void> _deleteExpense(GroupExpense expense) async {
    final tr = context.tr;
    final confirmed = await showConfirmDialog(
      context,
      title: tr.deleteSplitPrompt,
      message: tr.deleteSplitDesc(expense.description),
      confirmLabel: tr.delete,
      icon: Icons.delete_outline,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _runGroupAction(() async {
      await ref.read(expenseGroupServiceProvider)!.deleteExpense(expense.id);
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
    });
  }

  Future<void> _removeMember(
    String groupId,
    String userId,
    String displayName,
  ) async {
    final tr = context.tr;
    final confirmed = await showConfirmDialog(
      context,
      title: tr.deleteMemberPrompt,
      message: tr.deleteMemberDesc(displayName),
      confirmLabel: tr.removeFromGroup,
      icon: Icons.person_remove_outlined,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await _runGroupAction(() async {
      await ref
          .read(expenseGroupServiceProvider)!
          .removeMember(groupId: groupId, userId: userId);
    });
  }

  Future<void> _leaveGroup(GroupDetails details) async {
    final service = ref.read(expenseGroupServiceProvider);
    if (service == null) return;
    final isOwner = details.group.ownerId == service.currentUserId;
    final tr = context.tr;
    final confirmed = await showConfirmDialog(
      context,
      title: isOwner ? tr.deleteGroupPrompt : tr.leaveGroupPrompt,
      message: isOwner ? tr.deleteGroupDesc : tr.leaveGroupDesc,
      confirmLabel: isOwner ? tr.deleteGroupPrompt : tr.leaveGroupPrompt,
      icon: isOwner ? Icons.delete_outline : Icons.logout_outlined,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    var leftGroup = false;
    await _runGroupAction(() async {
      await service.leaveGroup(details.group.id);
      leftGroup = true;
    });
    if (leftGroup && mounted) {
      ref.invalidate(expenseGroupsProvider);
      context.pop();
    }
  }

  /// Chụp/chọn ảnh rồi đọc hóa đơn; `null` khi người dùng huỷ chọn ảnh.
  /// Lỗi đọc hóa đơn ném ra để dialog "Chia tiền" báo ngay trong tab Quét.
  Future<ReceiptPrefill?> _scanReceipt(ImageSource source) async {
    XFile? capturedImage;
    if (source == ImageSource.camera) {
      final completer = Completer<XFile?>();
      await context.push<void>(
        '/qr-payment?tab=receipt',
        extra: (XFile img) async {
          if (!completer.isCompleted) {
            completer.complete(img);
          }
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
      );
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      capturedImage = await completer.future;
    } else {
      capturedImage = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
        maxWidth: 2400,
      );
    }
    final image = capturedImage;
    if (image == null) return null;
    final bytes = await image.readAsBytes();
    final outcome = await ref
        .read(importCoordinatorProvider)
        .importImage(bytes: bytes, fileName: image.name, imagePath: image.path);
    final invoice = outcome.result.invoice;
    return ReceiptPrefill(
      description: receiptExpenseDescription(invoice.sellerName),
      totalMinor: invoice.totalMinor,
    );
  }

  Future<void> _runGroupAction(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      _reloadDetails();
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
    ref.invalidate(expenseGroupDetailsProvider(widget.groupId));
  }

  Future<void> _refresh() async {
    ref.invalidate(expenseGroupsProvider);
    try {
      _reloadDetails();
      await ref.read(expenseGroupDetailsProvider(widget.groupId).future);
    } on Object {
      // Lỗi đã được hiển thị qua trạng thái lỗi của chi tiết nhóm.
    }
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/groups');
    }
  }
}

class _GroupDetails extends StatelessWidget {
  const _GroupDetails({
    required this.details,
    required this.currentUserId,
    required this.busy,
    required this.onShowInviteQr,
    required this.onSplitMoney,
    required this.onSettle,
    required this.onShowBillQr,
    required this.onEditExpense,
    required this.onDeleteExpense,
    required this.onSetMemberRole,
    required this.onRemoveMember,
    required this.showAllMembers,
    required this.onToggleMembers,
    required this.showAllExpenses,
    required this.onToggleExpenses,
  });

  final GroupDetails details;
  final String currentUserId;
  final bool busy;
  final VoidCallback onShowInviteQr;
  final VoidCallback onSplitMoney;
  final Future<void> Function(String expenseId) onSettle;
  final Future<void> Function(GroupExpense expense) onShowBillQr;
  final Future<void> Function(GroupExpense expense) onEditExpense;
  final Future<void> Function(GroupExpense expense) onDeleteExpense;
  final Future<void> Function(String userId, String role) onSetMemberRole;
  final Future<void> Function(String userId, String displayName) onRemoveMember;
  final bool showAllMembers;
  final VoidCallback onToggleMembers;
  final bool showAllExpenses;
  final VoidCallback onToggleExpenses;

  @override
  Widget build(BuildContext context) {
    final names = {
      // Tên người ngoài nhóm trong bill, để nhật ký không hiện "Tài khoản đã xóa".
      for (final expense in details.expenses)
        for (final split in expense.splits)
          if (split.userId != null && split.participantName != null)
            split.userId!: split.participantName!,
      for (final member in details.members) member.userId: _memberName(member),
    };
    final balances = _balances();
    final transfers = GroupBalanceCalculator.calculateSettlementTransfers(
      balances,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    context.push('/groups/${details.group.id}/fund'),
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: Text(context.tr.groupFund),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : onSplitMoney,
                icon: const Icon(Icons.call_split_outlined),
                label: Text(context.tr.splitBill),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr.membersCount(details.members.length),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: context.tr.inviteViaQr,
                      onPressed: onShowInviteQr,
                      icon: const Icon(Icons.qr_code_2),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final member
                    in details.members
                        .take(showAllMembers ? details.members.length : 4)
                        .toList()
                        .asMap()
                        .entries) ...[
                  if (member.key > 0) const Divider(indent: 48, height: 1),
                  _MemberTile(
                    member: member.value,
                    currentUserId: currentUserId,
                    isGroupOwner: details.group.ownerId == currentUserId,
                    balanceLabel: _balanceLabel(
                      context,
                      balances[member.value.userId] ?? 0,
                    ),
                    onSetRole: onSetMemberRole,
                    onRemove: onRemoveMember,
                  ),
                ],
                if (details.members.length > 4)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: onToggleMembers,
                      child: Text(
                        showAllMembers
                            ? context.tr.collapseMembers
                            : context.tr.viewAllMembers(details.members.length),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (transfers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _SettlementSuggestions(transfers: transfers, names: names),
          ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                context.tr.sharedBillsCount(details.expenses.length),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (details.expenses.length > 3)
              TextButton(
                onPressed: onToggleExpenses,
                child: Text(
                  showAllExpenses
                      ? context.tr.collapse
                      : context.tr.viewAllCount(details.expenses.length),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (details.expenses.isEmpty) Text(context.tr.noSharedBills),
        for (final expense in details.expenses.take(
          showAllExpenses ? details.expenses.length : 3,
        ))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _ExpenseCard(
              expense: expense,
              names: names,
              memberIds: {for (final m in details.members) m.userId},
              currentUserId: currentUserId,
              onSettle: onSettle,
              canManage:
                  expense.payerId == currentUserId ||
                  details.group.ownerId == currentUserId,
              onShowBillQr: () => onShowBillQr(expense),
              onEdit: () => onEditExpense(expense),
              onDelete: () => onDeleteExpense(expense),
            ),
          ),
        if (details.auditEvents.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.history_outlined),
              title: Text('Lịch sử hoạt động (${details.auditEvents.length})'),
              children: [
                for (final event in details.auditEvents)
                  ListTile(
                    dense: true,
                    title: Text(_auditLabel(event, names)),
                    subtitle: Text(_formatAuditDate(event.createdAt)),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _memberName(GroupMember member) => _hasMemberName(member.displayName)
      ? member.displayName.trim()
      : 'Chưa đặt tên';

  bool _hasMemberName(String value) {
    final name = value.trim().toLowerCase();
    return name.isNotEmpty && name != 'thành viên' && name != 'chủ nhóm';
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
      'bill_joined' => _billAuditLabel(event, names, 'đã vào'),
      'bill_left' => _billAuditLabel(event, names, 'đã rời'),
      _ => 'Có hoạt động mới trong nhóm',
    };
  }

  String _billAuditLabel(
    GroupAuditEvent event,
    Map<String, String> names,
    String action,
  ) {
    // Người ngoài đã rời bill thì không còn tên trong split.
    final who = names[event.actorId] ?? 'Khách';
    final description = details.expenses
        .where((expense) => expense.id == event.expenseId)
        .firstOrNull
        ?.description;
    return description == null
        ? '$who $action bill'
        : '$who $action bill “$description”';
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

  String _balanceLabel(BuildContext context, int amount) {
    if (amount == 0) return context.tr.balanced;
    return amount > 0
        ? context.tr.shouldReceive(MoneyFormatter.format(amount))
        : context.tr.shouldPay(MoneyFormatter.format(-amount));
  }
}

class _DirectShareInbox extends ConsumerWidget {
  const _DirectShareInbox();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shares = ref.watch(directBillSharesProvider);
    return shares.when(
      loading: () => const Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: LinearProgressIndicator(),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
              context.tr.settlementSuggestions,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final transfer in transfers)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  context.tr.transferText(
                    names[transfer.fromUserId] ??
                        (context.tr.isEn
                            ? 'Deleted account'
                            : 'Tài khoản đã xóa'),
                    MoneyFormatter.format(transfer.amountMinor),
                    names[transfer.toUserId] ??
                        (context.tr.isEn
                            ? 'Deleted account'
                            : 'Tài khoản đã xóa'),
                  ),
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
    final hasName = _hasMemberName(member.displayName);
    final displayName = hasName ? member.displayName.trim() : 'Chưa đặt tên';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minVerticalPadding: 10,
      leading: const Icon(Icons.person_outline),
      title: Text(
        member.userId == currentUserId
            ? '$displayName (${context.tr.youTag})'
            : displayName,
      ),
      subtitle: Text(
        [
          member.role == 'owner'
              ? context.tr.groupRoleOwner
              : context.tr.groupRoleMember,
          if (member.phone?.isNotEmpty == true) member.phone!,
        ].join(' · '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 132),
            child: Text(
              balanceLabel,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (canManage)
            PopupMenuButton<String>(
              tooltip: context.tr.manageMemberTooltip,
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
                        ? context.tr.revokeOwnership
                        : context.tr.transferOwnership,
                  ),
                ),
                PopupMenuItem(
                  value: 'remove',
                  child: Text(context.tr.removeFromGroup),
                ),
              ],
            ),
        ],
      ),
    );
  }

  bool _hasMemberName(String value) {
    final name = value.trim().toLowerCase();
    return name.isNotEmpty && name != 'thành viên' && name != 'chủ nhóm';
  }
}

class _ExpenseCard extends StatelessWidget {
  const _ExpenseCard({
    required this.expense,
    required this.names,
    required this.memberIds,
    required this.currentUserId,
    required this.onSettle,
    required this.canManage,
    required this.onShowBillQr,
    required this.onEdit,
    required this.onDelete,
  });

  final GroupExpense expense;
  final Map<String, String> names;
  final Set<String> memberIds;
  final String currentUserId;
  final Future<void> Function(String expenseId) onSettle;
  final bool canManage;
  final Future<void> Function() onShowBillQr;
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
        myShare.amountMinor > 0 &&
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
                    tooltip: context.tr.isEn
                        ? 'Manage bill'
                        : 'Quản lý khoản chi',
                    onSelected: (value) {
                      if (value == 'invite') {
                        onShowBillQr();
                      } else if (value == 'edit') {
                        onEdit();
                      } else {
                        onDelete();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'invite',
                        child: ListTile(
                          leading: const Icon(Icons.qr_code_2),
                          title: Text(
                            context.tr.isEn
                                ? 'Bill invite QR'
                                : 'QR mời vào bill',
                            maxLines: 3,
                          ),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: const Icon(Icons.edit_outlined),
                          title: Text(
                            context.tr.isEn
                                ? 'Edit shared bill'
                                : 'Sửa khoản chi',
                            maxLines: 3,
                          ),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: const Icon(Icons.delete_outline),
                          title: Text(
                            context.tr.isEn
                                ? 'Delete shared bill'
                                : 'Xóa khoản chi',
                            maxLines: 3,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              context.tr.payerLabel(
                names[expense.payerId] ??
                    (context.tr.isEn ? 'Deleted account' : 'Tài khoản đã xóa'),
              ),
            ),
            if (expense.isSharedInvoice)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    const Icon(Icons.share_outlined, size: 16),
                    const SizedBox(width: 6),
                    Text(context.tr.sharedFromPersonal),
                  ],
                ),
              ),
            if (expense.splits.isNotEmpty) ...[
              const Divider(height: 20),
              for (var index = 0; index < expense.splits.length; index++) ...[
                if (index > 0) const Divider(height: 16, indent: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _splitName(expense.splits[index]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (expense.splits[index].userId != null &&
                                expense.splits[index].participantName != null &&
                                !memberIds.contains(
                                  expense.splits[index].userId,
                                ))
                              Text(
                                context.tr.groupRoleGuest,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${MoneyFormatter.format(expense.splits[index].amountMinor)}${expense.splits[index].isSettled ? ' · ${context.tr.paidTag}' : ''}',
                        textAlign: TextAlign.end,
                      ),
                    ],
                  ),
                ),
              ],
            ],
            if (canSettle)
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => onSettle(expense.id),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(context.tr.iHavePaid),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _splitName(GroupExpenseSplit split) {
    if (split.userId == null) return 'Tài khoản đã xóa';
    return names[split.userId!] ?? split.participantName ?? 'Chưa đặt tên';
  }
}

enum _JoinMethod { scan, type }
