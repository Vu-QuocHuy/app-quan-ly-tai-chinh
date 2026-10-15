import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../shared/dialogs/confirm_dialog.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/money_text.dart';
import '../../invoices/domain/invoice_models.dart';
import '../../notifications/data/budget_notification_service.dart';
import '../domain/plan_models.dart';

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(plansProvider);
    final expenseCategories =
        ref.watch(categoriesProvider).value ?? const <CategoryEntity>[];
    final incomeCategories =
        ref.watch(incomeCategoriesProvider).value ?? const <CategoryEntity>[];
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kế hoạch tiền bạc'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Chi cố định'),
              Tab(text: 'Thu cố định'),
              Tab(text: 'Tiết kiệm'),
            ],
          ),
        ),
        body: plans.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Text('Không thể tải kế hoạch: ${friendlyMessage(error)}'),
          ),
          data: (items) {
            final bills = items.whereType<RecurringBill>().toList()
              ..sort((a, b) => a.nextDueDate.compareTo(b.nextDueDate));
            final incomes = items.whereType<RecurringIncome>().toList()
              ..sort((a, b) => a.nextDueDate.compareTo(b.nextDueDate));
            final goals = items.whereType<SavingsGoal>().toList()
              ..sort((a, b) => a.targetDate.compareTo(b.targetDate));
            return TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    AppSpacing.xl,
                    AppSpacing.gutter,
                    AppSpacing.xxl,
                  ),
                  children: [
                    FilledButton.icon(
                      onPressed: () =>
                          _editBill(context, ref, expenseCategories),
                      icon: const Icon(Icons.add),
                      label: const Text('Thêm khoản chi cố định'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    for (final bill in bills)
                      _RecurringPlanCard(
                        title: bill.title,
                        amountMinor: bill.amountMinor,
                        detail:
                            '${_categoryName(bill.categoryId ?? '', expenseCategories)} · ${_frequencyLabel(bill.frequency)}',
                        due:
                            '${_isOverdue(bill.nextDueDate) ? 'Quá hạn' : 'Đến hạn'} ${_dateLabel(bill.nextDueDate)}',
                        overdue: _isOverdue(bill.nextDueDate),
                        onTap: () =>
                            _billActions(context, ref, bill, expenseCategories),
                      ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    AppSpacing.xl,
                    AppSpacing.gutter,
                    AppSpacing.xxl,
                  ),
                  children: [
                    FilledButton.icon(
                      onPressed: incomeCategories.isEmpty
                          ? null
                          : () => _editRecurringIncome(
                              context,
                              ref,
                              incomeCategories,
                            ),
                      icon: const Icon(Icons.add),
                      label: const Text('Thêm khoản thu cố định'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (incomeCategories.isEmpty)
                      const _Hint(
                        'Chưa tải được danh mục thu. Vui lòng thử lại sau.',
                      ),
                    for (final income in incomes)
                      _RecurringPlanCard(
                        title: income.title,
                        amountMinor: income.amountMinor,
                        detail: _categoryName(
                          income.categoryId,
                          incomeCategories,
                        ),
                        due: 'Nhận ${_dateLabel(income.nextDueDate)}',
                        onTap: () => _incomeActions(
                          context,
                          ref,
                          income,
                          incomeCategories,
                        ),
                      ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    AppSpacing.xl,
                    AppSpacing.gutter,
                    AppSpacing.xxl,
                  ),
                  children: [
                    FilledButton.icon(
                      onPressed: () => _editGoal(context, ref),
                      icon: const Icon(Icons.add),
                      label: const Text('Thêm mục tiêu'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    for (final goal in goals)
                      Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _goalActions(context, ref, goal),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        goal.name,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                    ),
                                    Text(
                                      '${(goal.progress * 100).clamp(0, 100).round()}%',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                LinearProgressIndicator(
                                  value: goal.progress.clamp(0, 1).toDouble(),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '${MoneyFormatter.format(goal.savedMinor)} / ${MoneyFormatter.format(goal.targetMinor)}',
                                ),
                                Text(
                                  goal.remainingMinor == 0
                                      ? 'Đã đạt mục tiêu'
                                      : 'Cần dành ${MoneyFormatter.format(goal.monthlyNeeded(DateTime.now()))}/tháng · Hạn ${_dateLabel(goal.targetDate)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _editRecurringIncome(
    BuildContext context,
    WidgetRef ref,
    List<CategoryEntity> categories, [
    RecurringIncome? income,
  ]) async {
    if (categories.isEmpty) return;
    final title = TextEditingController(text: income?.title);
    final amount = TextEditingController(text: income?.amountMinor.toString());
    final fallbackId = categories
        .where((category) => category.id == unclassifiedIncomeCategoryId)
        .map((category) => category.id)
        .firstOrNull;
    var categoryId =
        categories.any((category) => category.id == income?.categoryId)
        ? income!.categoryId
        : fallbackId ??
              categories.firstOrNull?.id ??
              unclassifiedIncomeCategoryId;
    final now = DateTime.now();
    var due = income?.nextDueDate ?? DateTime(now.year, now.month, now.day + 1);
    String? error;
    final result = await showDialog<RecurringIncome>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            income == null ? 'Thêm khoản thu cố định' : 'Sửa khoản thu cố định',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Tên khoản thu'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Số tiền mỗi tháng',
                    suffixText: '₫',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String>(
                  key: const ValueKey('recurring-income-category'),
                  initialValue: categoryId,
                  decoration: const InputDecoration(labelText: 'Danh mục thu'),
                  items: categories
                      .map(
                        (category) => DropdownMenuItem(
                          value: category.id,
                          child: Text(category.name),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) setState(() => categoryId = value);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                TextButton.icon(
                  onPressed: () async {
                    final chosen = await showDatePicker(
                      context: context,
                      initialDate: due,
                      firstDate: income == null
                          ? DateTime(now.year, now.month, 1)
                          : DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (chosen != null) setState(() => due = chosen);
                  },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    '${income == null ? 'Nhận từ' : 'Nhận tiếp'} ${_dateLabel(due)}',
                  ),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
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
              onPressed: () {
                final parsed = MoneyFormatter.tryParse(amount.text);
                if (title.text.trim().isEmpty ||
                    parsed == null ||
                    parsed <= 0 ||
                    parsed > maxPlanMoney ||
                    categoryId.trim().isEmpty) {
                  setState(
                    () => error = 'Nhập tên, số tiền và danh mục hợp lệ.',
                  );
                  return;
                }
                Navigator.pop(
                  context,
                  RecurringIncome(
                    id: income?.id ?? const Uuid().v4(),
                    title: title.text.trim(),
                    amountMinor: parsed,
                    categoryId: categoryId,
                    anchorDate: income != null && income.nextDueDate == due
                        ? income.anchorDate
                        : due,
                    nextDueDate: due,
                    updatedAt: DateTime.now(),
                  ),
                );
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    // Dialog fields can remain mounted during the closing transition.
    if (result != null && context.mounted) await _save(context, ref, result);
  }

  Future<void> _editBill(
    BuildContext context,
    WidgetRef ref,
    List<CategoryEntity> categories, [
    RecurringBill? bill,
  ]) async {
    final title = TextEditingController(text: bill?.title);
    final amount = TextEditingController(text: bill?.amountMinor.toString());
    var frequency = bill?.frequency ?? BillFrequency.monthly;
    var categoryId = bill?.categoryId;
    var due = bill?.nextDueDate ?? DateTime.now();
    String? error;
    final result = await showDialog<RecurringBill>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            bill == null ? 'Thêm khoản chi cố định' : 'Sửa khoản chi cố định',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Tên khoản'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Số tiền',
                    suffixText: '₫',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<BillFrequency>(
                  initialValue: frequency,
                  decoration: const InputDecoration(labelText: 'Lặp lại'),
                  items: BillFrequency.values
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_frequencyLabel(value)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) setState(() => frequency = value);
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String>(
                  key: const ValueKey('recurring-bill-category'),
                  initialValue: categoryId ?? '',
                  decoration: const InputDecoration(
                    labelText: 'Danh mục ngân sách',
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('Chưa phân loại'),
                    ),
                    if (categoryId != null &&
                        !categories.any((item) => item.id == categoryId))
                      DropdownMenuItem(
                        value: categoryId,
                        child: const Text('Danh mục hiện không có sẵn'),
                      ),
                    for (final category in categories)
                      DropdownMenuItem(
                        value: category.id,
                        child: Text(category.name),
                      ),
                  ],
                  onChanged: (value) => setState(
                    () => categoryId = value == null || value.isEmpty
                        ? null
                        : value,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextButton.icon(
                  onPressed: () async {
                    final chosen = await showDatePicker(
                      context: context,
                      initialDate: due,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (chosen != null) setState(() => due = chosen);
                  },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text('Đến hạn: ${_dateLabel(due)}'),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
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
              onPressed: () {
                final parsed = MoneyFormatter.tryParse(amount.text);
                if (title.text.trim().isEmpty ||
                    parsed == null ||
                    parsed <= 0 ||
                    parsed > maxPlanMoney) {
                  setState(() => error = 'Nhập tên và số tiền hợp lệ.');
                  return;
                }
                Navigator.pop(
                  context,
                  RecurringBill(
                    id: bill?.id ?? const Uuid().v4(),
                    title: title.text.trim(),
                    amountMinor: parsed,
                    frequency: frequency,
                    anchorDate: bill != null && bill.nextDueDate == due
                        ? bill.anchorDate
                        : due,
                    nextDueDate: due,
                    categoryId: categoryId,
                    updatedAt: DateTime.now(),
                  ),
                );
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (result != null && context.mounted) await _save(context, ref, result);
  }

  Future<void> _editGoal(
    BuildContext context,
    WidgetRef ref, [
    SavingsGoal? goal,
  ]) async {
    final name = TextEditingController(text: goal?.name);
    final target = TextEditingController(text: goal?.targetMinor.toString());
    var date =
        goal?.targetDate ??
        DateTime(
          DateTime.now().year + 1,
          DateTime.now().month,
          DateTime.now().day,
        );
    String? error;
    final result = await showDialog<SavingsGoal>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(goal == null ? 'Thêm mục tiêu' : 'Sửa mục tiêu'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Tên mục tiêu'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: target,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Số tiền mục tiêu',
                    suffixText: '₫',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextButton.icon(
                  onPressed: () async {
                    final chosen = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (chosen != null) setState(() => date = chosen);
                  },
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text('Hạn ${_dateLabel(date)}'),
                ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
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
              onPressed: () {
                final parsed = MoneyFormatter.tryParse(target.text);
                if (name.text.trim().isEmpty ||
                    parsed == null ||
                    parsed <= 0 ||
                    parsed > maxPlanMoney ||
                    (goal?.savedMinor ?? 0) > parsed) {
                  setState(
                    () =>
                        error = 'Nhập tên và mục tiêu lớn hơn số tiền đã dành.',
                  );
                  return;
                }
                Navigator.pop(
                  context,
                  SavingsGoal(
                    id: goal?.id ?? const Uuid().v4(),
                    name: name.text.trim(),
                    targetMinor: parsed,
                    savedMinor: goal?.savedMinor ?? 0,
                    targetDate: date,
                    updatedAt: DateTime.now(),
                  ),
                );
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (result != null && context.mounted) await _save(context, ref, result);
  }

  Future<void> _incomeActions(
    BuildContext context,
    WidgetRef ref,
    RecurringIncome income,
    List<CategoryEntity> categories,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: Text(income.title),
              subtitle: Text(
                'Lần nhận tiếp theo: ${_dateLabel(income.nextDueDate)}',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Sửa'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Ngừng khoản thu định kỳ'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'edit') {
      return _editRecurringIncome(context, ref, categories, income);
    }
    if (action == 'delete') return _delete(context, ref, income);
  }

  Future<void> _billActions(
    BuildContext context,
    WidgetRef ref,
    RecurringBill bill,
    List<CategoryEntity> categories,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: Text(bill.title),
              subtitle: Text('Đến hạn ${_dateLabel(bill.nextDueDate)}'),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Đã thanh toán và ghi khoản chi'),
              onTap: () => Navigator.pop(context, 'paid'),
            ),
            ListTile(
              leading: const Icon(Icons.skip_next_outlined),
              title: const Text('Đã ghi chi trước đó hoặc bỏ qua kỳ này'),
              onTap: () => Navigator.pop(context, 'skip'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Sửa'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Xóa'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'edit') return _editBill(context, ref, categories, bill);
    if (action == 'delete') return _delete(context, ref, bill);
    if (action != 'skip' && action != 'paid') return;
    try {
      final current = await ref.read(planRepositoryProvider).findById(bill.id);
      if (current is! RecurringBill) return;
      if (action == 'paid') {
        final hash = 'recurring:${current.id}:${_dateKey(current.nextDueDate)}';
        final invoices = ref.read(invoiceRepositoryProvider);
        if (await invoices.findBySourceHash(hash) == null) {
          final now = DateTime.now();
          await invoices.saveInvoice(
            InvoiceEntity(
              id: const Uuid().v5(Namespace.url.value, hash),
              sellerName: current.title,
              currencyCode: 'VND',
              subtotalMinor: current.amountMinor,
              taxMinor: 0,
              totalMinor: current.amountMinor,
              sourceType: InvoiceSourceType.manual,
              status: InvoiceStatus.confirmed,
              sourceHash: hash,
              categoryId: current.categoryId,
              issuedAt: now,
              createdAt: now,
              updatedAt: now,
              confirmedAt: now,
              notes: 'Khoản định kỳ: ${_dateLabel(current.nextDueDate)}',
            ),
          );
        }
      }
      await ref
          .read(planRepositoryProvider)
          .save(
            current.copyWith(
              nextDueDate: current.followingDueDate,
              updatedAt: DateTime.now(),
            ),
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'paid'
                  ? 'Đã ghi khoản chi.'
                  : 'Đã chuyển sang kỳ tiếp theo.',
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _goalActions(
    BuildContext context,
    WidgetRef ref,
    SavingsGoal goal,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(title: Text(goal.name)),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Cập nhật tiền đã để dành'),
              onTap: () => Navigator.pop(context, 'add'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Sửa'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Xóa'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'edit') return _editGoal(context, ref, goal);
    if (action == 'delete') return _delete(context, ref, goal);
    if (action != 'add') return;
    final controller = TextEditingController(text: goal.savedMinor.toString());
    String? error;
    final amount = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Tiền đã để dành'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tổng đã dành',
                  suffixText: '₫',
                ),
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
                final parsed = MoneyFormatter.tryParse(controller.text);
                if (parsed == null || parsed < 0 || parsed > maxPlanMoney) {
                  setState(() => error = 'Nhập số tiền hợp lệ.');
                  return;
                }
                Navigator.pop(context, parsed);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (amount == null) return;
    try {
      final current = await ref.read(planRepositoryProvider).findById(goal.id);
      if (current is SavingsGoal && context.mounted) {
        await _save(
          context,
          ref,
          current.copyWith(savedMinor: amount, updatedAt: DateTime.now()),
        );
      }
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _save(BuildContext context, WidgetRef ref, PlanItem item) async {
    try {
      await ref.read(planRepositoryProvider).save(item);
      if (item is RecurringBill) {
        try {
          await BudgetNotificationService.instance.requestPermission();
        } on Object {
          // The plan remains saved even if notifications are unavailable.
        }
      }
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PlanItem item,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: item is RecurringIncome
          ? 'Ngừng khoản thu cố định?'
          : 'Xóa kế hoạch?',
      message: item is RecurringIncome
          ? 'Các khoản thu đã ghi vẫn còn trong lịch sử. Lịch thu này sẽ bị xóa trên các thiết bị của bạn.'
          : 'Kế hoạch này sẽ bị xóa trên các thiết bị của bạn.',
      confirmLabel: item is RecurringIncome ? 'Ngừng' : 'Xóa',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(planRepositoryProvider).delete(item.id);
    } on Object catch (error) {
      if (context.mounted) _showError(context, error);
    }
  }

  void _showError(BuildContext context, Object error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyMessage(error))));
    }
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(20), child: Text(text)),
  );
}

class _RecurringPlanCard extends StatelessWidget {
  const _RecurringPlanCard({
    required this.title,
    required this.amountMinor,
    required this.detail,
    required this.due,
    required this.onTap,
    this.overdue = false,
  });

  final String title;
  final int amountMinor;
  final String detail;
  final String due;
  final VoidCallback onTap;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              const SizedBox(width: AppSpacing.sm),
              const Icon(Icons.chevron_right, size: AppIconSizes.md),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          MoneyText(amountMinor, emphasis: MoneyEmphasis.title),
          const SizedBox(height: AppSpacing.md),
          Text(
            detail,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            due,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: overdue
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

String _frequencyLabel(BillFrequency frequency) => switch (frequency) {
  BillFrequency.weekly => 'Hàng tuần',
  BillFrequency.monthly => 'Hàng tháng',
  BillFrequency.yearly => 'Hàng năm',
};

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String _dateLabel(DateTime date) => '${date.day}/${date.month}/${date.year}';
bool _isOverdue(DateTime date) =>
    DateTime(date.year, date.month, date.day).isBefore(
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
    );

String _categoryName(String id, List<CategoryEntity> categories) =>
    categories.where((category) => category.id == id).firstOrNull?.name ??
    'Chưa phân loại';
