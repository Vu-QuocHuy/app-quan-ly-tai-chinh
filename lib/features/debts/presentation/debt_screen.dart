import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/finance_colors.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/finmi_page_header.dart';
import '../data/debt_notification_store.dart';
import '../data/debt_repository.dart';
import '../domain/debt_models.dart';
import 'debt_entry_sheet.dart';
import 'debt_settle_dialog.dart';

class DebtScreen extends ConsumerStatefulWidget {
  const DebtScreen({super.key, this.initialDebtId});

  final String? initialDebtId;

  @override
  ConsumerState<DebtScreen> createState() => _DebtScreenState();
}

class _DebtScreenState extends ConsumerState<DebtScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _highlightedDebtId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _highlightedDebtId = widget.initialDebtId;
    _searchController.addListener(() {
      setState(
        () => _searchQuery = _searchController.text.trim().toLowerCase(),
      );
    });

    // Nhắc nhở người dùng cập nhật số điện thoại lần đầu để nhận thông báo nợ
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final phone = await DebtNotificationStore.getCurrentUserPhone(ref);
      if ((phone == null || phone.isEmpty) && mounted) {
        _showMyPhoneDialog(context, isFirstTime: true);
      }

      // Tự động chuyển tab tới khoản nợ được chỉ định qua initialDebtId
      if (widget.initialDebtId != null && mounted) {
        final debts = ref.read(debtsListProvider).valueOrNull ?? [];
        final target = debts
            .where((d) => d.id == widget.initialDebtId)
            .firstOrNull;
        if (target != null) {
          if (target.isSettled) {
            _tabController.animateTo(3);
          } else if (target.type == DebtType.theyOwe) {
            _tabController.animateTo(1);
          } else if (target.type == DebtType.iOwe) {
            _tabController.animateTo(2);
          }
        }
      }
    });
  }

  @override
  void didUpdateWidget(DebtScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialDebtId != oldWidget.initialDebtId &&
        widget.initialDebtId != null) {
      setState(() => _highlightedDebtId = widget.initialDebtId);
      final debts = ref.read(debtsListProvider).valueOrNull ?? [];
      final target = debts
          .where((d) => d.id == widget.initialDebtId)
          .firstOrNull;
      if (target != null) {
        if (target.isSettled) {
          _tabController.animateTo(3);
        } else if (target.type == DebtType.theyOwe) {
          _tabController.animateTo(1);
        } else if (target.type == DebtType.iOwe) {
          _tabController.animateTo(2);
        }
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<DebtRecord> _filterDebts(List<DebtRecord> allDebts, int tabIndex) {
    var filtered = allDebts;

    // Filter by tab
    switch (tabIndex) {
      case 0: // Tất cả đang nợ
        filtered = filtered.where((d) => !d.isSettled).toList();
        break;
      case 1: // Cần thu (Người khác nợ tôi)
        filtered = filtered
            .where((d) => !d.isSettled && d.type == DebtType.theyOwe)
            .toList();
        break;
      case 2: // Cần trả (Tôi nợ người khác)
        filtered = filtered
            .where((d) => !d.isSettled && d.type == DebtType.iOwe)
            .toList();
        break;
      case 3: // Đã thanh toán xong
        filtered = filtered.where((d) => d.isSettled).toList();
        break;
    }

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((d) {
        final name = d.personName.toLowerCase();
        final notes = (d.notes ?? '').toLowerCase();
        return name.contains(_searchQuery) || notes.contains(_searchQuery);
      }).toList();
    }

    return filtered;
  }

  Future<void> _deleteDebt(DebtRecord debt) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa khoản nợ?'),
        content: Text(
          'Bạn có chắc chắn muốn xóa khoản nợ của "${debt.personName}" không? Thao tác này không thể hoàn tác.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(debtsListProvider.notifier).delete(debt.id);
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            content: Text('Đã xóa khoản nợ của ${debt.personName}.'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Hộp thoại yêu cầu người gửi cập nhật Tên và Số điện thoại nếu chưa có
  Future<Map<String, String>?> _showSenderProfileDialog(
    BuildContext context, {
    String? currentName,
    String? currentPhone,
  }) async {
    final tr = context.tr;
    final nameCtrl = TextEditingController(text: currentName ?? '');
    final phoneCtrl = TextEditingController(text: currentPhone ?? '');
    String? errorText;

    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.person_pin_circle_outlined,
                color: Theme.of(ctx).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr.isEn ? 'Sender Information' : 'Thông tin người gửi',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr.isEn
                    ? 'Please enter your name and phone number so the recipient clearly knows who is sending the reminder.'
                    : 'Vui lòng xác nhận tên và số điện thoại của bạn để người nhận biết rõ ai gửi thông báo nhắc nợ.',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: tr.isEn ? 'Your Name *' : 'Họ và tên của bạn *',
                  hintText: tr.isEn ? 'e.g. John Doe' : 'Ví dụ: Nguyễn Văn A',
                  prefixIcon: const Icon(Icons.person_outline),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: InputDecoration(
                  labelText: tr.isEn
                      ? 'Your Phone Number *'
                      : 'Số điện thoại của bạn *',
                  hintText: 'Ví dụ: 0987654321',
                  prefixIcon: const Icon(Icons.phone_android_rounded),
                  border: const OutlineInputBorder(),
                  errorText: errorText,
                  isDense: true,
                ),
                onChanged: (_) {
                  if (errorText != null) setDialogState(() => errorText = null);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, null),
              child: Text(tr.isEn ? 'Cancel' : 'Hủy'),
            ),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final phone = phoneCtrl.text.trim();
                if (name.isEmpty) {
                  setDialogState(
                    () => errorText = tr.isEn
                        ? 'Please enter your name'
                        : 'Vui lòng nhập tên',
                  );
                  return;
                }
                if (phone.length != 10 || !phone.startsWith('0')) {
                  setDialogState(
                    () => errorText = tr.isEn
                        ? 'Invalid 10-digit phone number'
                        : 'Số điện thoại phải gồm 10 chữ số (bắt đầu bằng 0)',
                  );
                  return;
                }
                await DebtNotificationStore.setCurrentUserPhone(
                  phone,
                  ref: ref,
                );
                if (ctx.mounted) {
                  Navigator.pop(dialogCtx, {'name': name, 'phone': phone});
                }
              },
              child: Text(tr.isEn ? 'Confirm & Send' : 'Xác nhận & Gửi'),
            ),
          ],
        ),
      ),
    );
  }

  /// Gửi lời nhắc nợ (in-app notification & tùy chọn SMS)
  Future<void> _remindDebt(BuildContext context, DebtRecord debt) async {
    final phone = debt.phoneNumber;
    if (phone == null || phone.isEmpty) return;

    final user = ref.read(authUserProvider).valueOrNull;
    var fullName = (user?.userMetadata?['full_name'] as String?)?.trim();
    var myPhone = await DebtNotificationStore.getCurrentUserPhone(ref);

    if (!context.mounted) return;

    // Nếu người gửi chưa có SĐT hoặc chưa có Tên, mở dialog yêu cầu nhập
    if (myPhone == null ||
        myPhone.isEmpty ||
        fullName == null ||
        fullName.isEmpty) {
      final info = await _showSenderProfileDialog(
        context,
        currentName: fullName,
        currentPhone: myPhone,
      );
      if (info == null) return; // User cancelled
      fullName = info['name'];
      myPhone = info['phone'];
    }

    final senderName = (fullName != null && fullName.isNotEmpty)
        ? fullName
        : (myPhone != null && myPhone.isNotEmpty ? myPhone : 'Chủ nợ');

    // Kiểm tra xem đã từng gửi thông báo chưa (để hiển thị thông báo gửi lại)
    final existingNotif = await DebtNotificationStore.getNotificationForDebt(
      debt.id,
    );
    final isResend = existingNotif != null;

    final sent = await DebtNotificationStore.sendDebtNotification(
      ref: ref,
      targetPhone: phone,
      senderName: senderName,
      senderPhone: myPhone,
      debtId: debt.id,
      amountMinor: debt.remainingMinor,
      notes: debt.notes,
      dueDate: debt.dueDate,
    );

    // Cập nhật trạng thái thông báo gửi nợ
    ref.invalidate(sentDebtNotificationStatusProvider(debt.id));

    if (context.mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      final tr = context.tr;
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
          content: Text(
            sent
                ? (isResend
                      ? (tr.isEn
                            ? 'Resent debt reminder in app to $phone'
                            : 'Đã gửi lại thông báo nhắc nợ trong app tới $phone')
                      : (tr.isEn
                            ? 'Debt reminder sent in app to $phone'
                            : 'Đã gửi thông báo nhắc nợ trong app tới $phone'))
                : (tr.isEn
                      ? 'Phone number $phone does not have a Finmi account'
                      : 'Số điện thoại $phone chưa có tài khoản Finmi'),
          ),
          action: sent
              ? null
              : SnackBarAction(
                  label: tr.isEn ? 'Send SMS' : 'Gửi SMS',
                  onPressed: () async {
                    final msg =
                        'Chào ${debt.personName}, $senderName nhắc bạn khoản nợ ${MoneyFormatter.format(debt.remainingMinor)}${debt.notes != null ? ' (${debt.notes})' : ''}. Cảm ơn bạn!';
                    final uri = Uri.parse(
                      'sms:$phone?body=${Uri.encodeComponent(msg)}',
                    );
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                ),
        ),
      );
    }
  }

  /// Hộp thoại xem và cập nhật số điện thoại cá nhân
  Future<void> _showMyPhoneDialog(
    BuildContext context, {
    bool isFirstTime = false,
  }) async {
    final currentPhone =
        await DebtNotificationStore.getCurrentUserPhone(ref) ?? '';
    if (!mounted || !context.mounted) return;
    final controller = TextEditingController(text: currentPhone);

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        String? errorText;
        return AlertDialog(
          title: Text(
            isFirstTime
                ? 'Chào mừng bạn đến Quản lý nợ'
                : 'Số điện thoại cá nhân',
          ),
          content: StatefulBuilder(
            builder: (ctx, setDialogState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFirstTime
                      ? 'Vui lòng nhập số điện thoại của bạn để nhận thông báo tự động khi bạn bè ghi nhận khoản nợ.'
                      : 'Mỗi người dùng có một số điện thoại duy nhất để nhận thông báo nợ trong app.',
                  style: Theme.of(dialogCtx).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(dialogCtx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Số điện thoại của bạn *',
                    hintText: 'Ví dụ: 0987654321',
                    prefixIcon: const Icon(Icons.phone_android_rounded),
                    border: const OutlineInputBorder(),
                    errorText: errorText,
                  ),
                  onChanged: (_) {
                    if (errorText != null) {
                      setDialogState(() => errorText = null);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(isFirstTime ? 'Để sau' : 'Hủy'),
            ),
            FilledButton(
              onPressed: () async {
                final text = controller.text
                    .replaceAll(RegExp(r'\s+'), '')
                    .trim();
                final messenger = ScaffoldMessenger.of(context);
                if (text.isEmpty) {
                  messenger.clearSnackBars();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Vui lòng nhập số điện thoại.'),
                      duration: Duration(seconds: 3),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                if (!RegExp(r'^0[0-9]{9}$').hasMatch(text)) {
                  messenger.clearSnackBars();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Số điện thoại phải gồm đúng 10 số và bắt đầu bằng 0.',
                      ),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 3),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                // Kiểm tra xem số điện thoại đã được dùng bởi tài khoản khác chưa
                final isTaken =
                    await DebtNotificationStore.isPhoneTakenByAnotherUser(
                      text,
                      ref: ref,
                    );
                if (isTaken) {
                  messenger.clearSnackBars();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Số điện thoại này đã được sử dụng bởi tài khoản khác.',
                      ),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 3),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }

                await DebtNotificationStore.setCurrentUserPhone(text, ref: ref);
                ref.invalidate(userPhoneProvider);
                ref.invalidate(debtNotificationsProvider);
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                if (mounted) {
                  messenger.clearSnackBars();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Đã lưu số điện thoại: $text'),
                      duration: const Duration(seconds: 3),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: const Text('Lưu'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = ref.watch(debtSummaryProvider);
    final debtsAsync = ref.watch(debtsListProvider);
    final notifsAsync = ref.watch(debtNotificationsProvider);

    final unreadCount =
        notifsAsync.valueOrNull?.where((n) => !n.isRead).length ?? 0;

    final tr = context.tr;
    return Scaffold(
      appBar: FinmiPageHeader(
        title: tr.debtManagement,
        actions: [
          IconButton(
            tooltip: tr.debtNotificationsTitle,
            icon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text('$unreadCount'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
            onPressed: () => context.push('/invoices?tab=debts'),
          ),
          IconButton(
            tooltip: tr.debtPersonalPhone,
            icon: const Icon(Icons.phone_android_rounded),
            onPressed: () => _showMyPhoneDialog(context),
          ),
          IconButton(
            tooltip: tr.debtAddTooltip,
            icon: const Icon(Icons.add_rounded),
            onPressed: () => showDebtEntrySheet(context),
          ),
        ],
      ),
      body: debtsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Lỗi tải dữ liệu: $e')),
        data: (debts) => NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSummaryCards(context, summary),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: tr.debtSearchHint,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () => _searchController.clear(),
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverAppBarDelegate(
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelColor: theme.colorScheme.primary,
                  unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                  indicatorColor: theme.colorScheme.primary,
                  tabs: [
                    Tab(text: tr.debtAll),
                    Tab(
                      text:
                          '${tr.debtToCollect} (${summary.activeReceivableCount})',
                    ),
                    Tab(
                      text: '${tr.debtToPay} (${summary.activePayableCount})',
                    ),
                    Tab(text: tr.debtSettled),
                  ],
                ),
                theme.colorScheme.surface,
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              for (var i = 0; i < 4; i++)
                _buildDebtList(context, _filterDebts(debts, i), i),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCards(BuildContext context, DebtSummary summary) {
    final theme = Theme.of(context);
    final finance = context.finance;
    final tr = context.tr;

    return Row(
      children: [
        Expanded(
          child: AppCard(
            padding: const EdgeInsets.all(14),
            color: theme.colorScheme.surfaceContainerHigh,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.arrow_downward_rounded,
                      size: 16,
                      color: finance.income.color,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      tr.debtToCollect,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  MoneyFormatter.format(summary.totalReceivableMinor),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: finance.income.color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tr.isEn
                      ? '${summary.activeReceivableCount} debts to collect'
                      : '${summary.activeReceivableCount} khoản người khác nợ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AppCard(
            padding: const EdgeInsets.all(14),
            color: theme.colorScheme.surfaceContainerHigh,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.arrow_upward_rounded,
                      size: 16,
                      color: finance.expense.color,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      tr.debtToPay,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  MoneyFormatter.format(summary.totalPayableMinor),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: finance.expense.color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tr.isEn
                      ? '${summary.activePayableCount} debts to pay'
                      : '${summary.activePayableCount} khoản bạn đang nợ',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDebtList(
    BuildContext context,
    List<DebtRecord> debts,
    int tabIndex,
  ) {
    final tr = context.tr;
    if (debts.isEmpty) {
      final messages = [
        tr.isEn
            ? 'No active debts to settle.'
            : 'Không có khoản nợ nào cần thanh toán.',
        tr.isEn
            ? 'Nobody owes you money right now.'
            : 'Hiện không ai nợ tiền bạn.',
        tr.isEn
            ? 'You do not owe anyone right now.'
            : 'Bạn không nợ ai khoản nào.',
        tr.isEn
            ? 'No debts settled yet.'
            : 'Chưa có khoản nợ nào được thanh toán.',
      ];
      return AppEmptyState(
        icon: Icons.check_circle_outline_rounded,
        title: tr.isEn ? 'All Clear' : 'Trống trải',
        message: _searchQuery.isNotEmpty
            ? (tr.isEn
                  ? 'No debts matching "$_searchQuery".'
                  : 'Không tìm thấy khoản nợ khớp với từ khóa "$_searchQuery".')
            : messages[tabIndex],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      itemCount: debts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final debt = debts[index];
        return _DebtCard(
          debt: debt,
          isHighlighted: debt.id == _highlightedDebtId,
          onSettle: () => showDebtSettleDialog(context, ref, debt),
          onRemind: (d) => _remindDebt(context, d),
          onEdit: () => showDebtEntrySheet(context, existing: debt),
          onDelete: () => _deleteDebt(debt),
        );
      },
    );
  }
}

class _DebtCard extends ConsumerWidget {
  const _DebtCard({
    required this.debt,
    required this.onSettle,
    required this.onRemind,
    required this.onEdit,
    required this.onDelete,
    this.isHighlighted = false,
  });

  final DebtRecord debt;
  final VoidCallback onSettle;
  final ValueChanged<DebtRecord> onRemind;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final finance = context.finance;
    final tr = context.tr;
    final isTheyOwe = debt.type == DebtType.theyOwe;
    final color = isTheyOwe ? finance.income.color : finance.expense.color;

    final notifStatus = (isTheyOwe && !debt.isSettled)
        ? ref.watch(sentDebtNotificationStatusProvider(debt.id)).valueOrNull
        : null;

    final cardContent = AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isHighlighted) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.visibility_outlined,
                    size: 12,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    tr.isEn ? 'Viewing Debt' : 'Khoản nợ đang xem',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isTheyOwe
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      debt.personName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isTheyOwe
                          ? (tr.isEn ? 'They owe you' : 'Người khác nợ bạn')
                          : (tr.isEn ? 'You owe them' : 'Bạn nợ người khác'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (debt.isSettled)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: finance.income.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tr.isEn ? 'Settled' : 'Đã thanh toán',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: finance.income.color,
                    ),
                  ),
                )
              else if (isTheyOwe && notifStatus != null) ...[
                if (notifStatus.isSaved)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: finance.income.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 12,
                          color: finance.income.color,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          tr.isEn ? 'Saved to debts' : 'Đối phương đã lưu nợ',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: finance.income.color,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.hourglass_top_rounded,
                          size: 12,
                          color: Colors.amber.shade900,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          tr.isEn ? 'Pending save' : 'Chờ đối phương lưu nợ',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
              ] else if (debt.isOverdue)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: finance.expense.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tr.isEn ? 'Overdue' : 'Quá hạn',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: finance.expense.color,
                    ),
                  ),
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (val) {
                  if (val == 'edit') onEdit();
                  if (val == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(tr.isEn ? 'Edit' : 'Chỉnh sửa'),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      tr.isEn ? 'Delete' : 'Xóa',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    debt.isSettled
                        ? (tr.isEn ? 'Debt amount:' : 'Khoản nợ:')
                        : (tr.isEn ? 'Remaining:' : 'Còn lại:'),
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    MoneyFormatter.format(
                      debt.isSettled ? debt.amountMinor : debt.remainingMinor,
                    ),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: debt.isSettled
                          ? theme.colorScheme.onSurface
                          : color,
                    ),
                  ),
                ],
              ),
              if (!debt.isSettled)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isTheyOwe &&
                        debt.phoneNumber != null &&
                        debt.phoneNumber!.isNotEmpty) ...[
                      IconButton.outlined(
                        tooltip: notifStatus != null && !notifStatus.isSaved
                            ? (tr.isEn
                                  ? 'Resend debt reminder'
                                  : 'Gửi lại thông báo nhắc nợ')
                            : (tr.isEn
                                  ? 'Remind via App / SMS'
                                  : 'Nhắc nợ qua App / SMS'),
                        icon: Icon(
                          notifStatus != null && !notifStatus.isSaved
                              ? Icons.replay_rounded
                              : Icons.send_rounded,
                          size: 16,
                          color: notifStatus != null && !notifStatus.isSaved
                              ? Colors.amber.shade900
                              : null,
                        ),
                        onPressed: () => onRemind(debt),
                        style: IconButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(6),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    FilledButton.icon(
                      onPressed: onSettle,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: Text(
                        isTheyOwe
                            ? (tr.isEn ? 'Collect' : 'Thu hồi')
                            : (tr.isEn ? 'Mark paid' : 'Xác nhận đã trả'),
                      ),
                    ),
                  ],
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: finance.income.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_rounded,
                        size: 15,
                        color: finance.income.color,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        tr.isEn ? 'Settled' : 'Đã thanh toán',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: finance.income.color,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (debt.paidAmountMinor > 0 && !debt.isSettled) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: debt.progress,
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${tr.isEn ? 'Paid' : 'Đã trả'}: ${MoneyFormatter.format(debt.paidAmountMinor)}',
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
                Text(
                  '${tr.isEn ? 'Total' : 'Tổng'}: ${MoneyFormatter.format(debt.amountMinor)}',
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
              ],
            ),
          ],
          if (debt.dueDate != null ||
              (debt.notes != null && debt.notes!.isNotEmpty)) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.45,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  if (debt.dueDate != null) ...[
                    Icon(
                      Icons.event_outlined,
                      size: 14,
                      color: debt.isOverdue
                          ? finance.expense.color
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${tr.isEn ? 'Due' : 'Hạn'}: ${DateFormat('dd/MM/yyyy').format(debt.dueDate!)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: debt.isOverdue
                            ? finance.expense.color
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: debt.isOverdue ? FontWeight.w600 : null,
                      ),
                    ),
                    if (debt.notes != null && debt.notes!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        '•',
                        style: TextStyle(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                  if (debt.notes != null && debt.notes!.isNotEmpty) ...[
                    if (debt.dueDate == null) ...[
                      Icon(
                        Icons.notes_rounded,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        debt.notes!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );

    if (isHighlighted) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.primary, width: 2),
        ),
        child: cardContent,
      );
    }
    return cardContent;
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar, this._backgroundColor);

  final TabBar _tabBar;
  final Color _backgroundColor;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return ColoredBox(color: _backgroundColor, child: _tabBar);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}
