import '../../../shared/widgets/finmi_page_header.dart';
import '../../../shared/widgets/app_refresh.dart';
import '../../../app/theme/finmi_theme.dart';
import '../../../app/theme/finance_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../shared/dialogs/confirm_dialog.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/category_avatar.dart';
import '../../../core/localization/app_strings.dart';
import '../../invoices/domain/invoice_models.dart';
import '../../notifications/data/budget_notification_service.dart';
import '../domain/plan_models.dart';

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tr = context.tr;
    final plans = ref.watch(plansProvider);
    final expenseCategories =
        ref.watch(categoriesProvider).value ?? const <CategoryEntity>[];
    final incomeCategories =
        ref.watch(incomeCategoriesProvider).value ?? const <CategoryEntity>[];
    return Scaffold(
      body: AppRefreshIndicator(
        onRefresh: () => refreshFromCloud(context, ref),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            FinmiSliverHeader(
              title: tr.isEn ? 'Recurring plans' : 'Thu chi định kỳ',
              actions: [
                FinmiHeaderAction(
                  icon: Icons.add,
                  tooltip: tr.isEn ? 'Add recurring item' : 'Thêm khoản định kỳ',
                  onPressed: () async {
                    final kind = await showModalBottomSheet<int>(
                      context: context,
                      useSafeArea: true,
                      useRootNavigator: true,
                      showDragHandle: true,
                      builder: (context) => SafeArea(
                        top: false,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              title: Text(tr.isEn ? 'Recurring income' : 'Khoản thu định kỳ'),
                              leading: const Icon(Icons.south_west),
                              enabled: incomeCategories.isNotEmpty,
                              onTap: () => Navigator.pop(context, 0),
                            ),
                            ListTile(
                              title: Text(tr.isEn ? 'Recurring expense' : 'Khoản chi định kỳ'),
                              leading: const Icon(Icons.north_east),
                              onTap: () => Navigator.pop(context, 1),
                            ),
                            ListTile(
                              title: Text(tr.isEn ? 'Savings goal' : 'Mục tiêu tiết kiệm'),
                              leading: const Icon(Icons.savings_outlined),
                              onTap: () => Navigator.pop(context, 2),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (!context.mounted) return;
                    if (kind == 0) {
                      await _editRecurringIncome(
                        context,
                        ref,
                        incomeCategories,
                      );
                      return;
                    }
                    if (kind == 1) {
                      await _editBill(context, ref, expenseCategories);
                      return;
                    }
                    if (kind == 2) {
                      await _editGoal(context, ref);
                    }
                  },
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
              sliver: plans.when(
                loading: () => const SliverToBoxAdapter(
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => SliverToBoxAdapter(
                  child: Column(
                    children: [
                      Text('Không thể tải kế hoạch: ${friendlyMessage(error)}'),
                      TextButton(
                        onPressed: () => ref.invalidate(plansProvider),
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
                data: (items) {
                  final bills = items.whereType<RecurringBill>().toList()
                    ..sort((a, b) => a.nextDueDate.compareTo(b.nextDueDate));
                  final incomes = items.whereType<RecurringIncome>().toList()
                    ..sort((a, b) => a.nextDueDate.compareTo(b.nextDueDate));
                  final goals = items.whereType<SavingsGoal>().toList()
                    ..sort((a, b) => a.targetDate.compareTo(b.targetDate));
                  return SliverList.list(
                    children: [
                      Text(
                        tr.isEn
                            ? 'Fixed income and expenses that repeat periodically.'
                            : 'Các khoản thu nhập và chi tiêu cố định lặp lại theo chu kỳ.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        tr.isEn ? '↓ Recurring Income' : '↓ Khoản thu định kỳ',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: context.finance.income.color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (incomes.isEmpty)
                        _EmptyPlanCard(
                          title: tr.isEn ? 'No recurring income yet' : 'Chưa có khoản thu định kỳ',
                          subtitle: tr.isEn
                              ? 'Add salary or fixed monthly income sources to monitor steady cash flow.'
                              : 'Thêm lương hoặc các nguồn thu nhập cố định hàng tháng để theo dõi dòng tiền ổn định.',
                          buttonLabel: tr.isEn ? 'Add income' : 'Thêm khoản thu',
                          icon: Icons.south_west_rounded,
                          accentColor: context.finance.income.color,
                          onAdd: () => _editRecurringIncome(
                            context,
                            ref,
                            incomeCategories,
                          ),
                        ),
                      for (final income in incomes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _RecurringPlanCard(
                            title: income.title,
                            amountMinor: income.amountMinor,
                            income: true,
                            detail: _categoryName(
                              income.categoryId,
                              incomeCategories,
                              tr: tr,
                            ),
                            due: '${tr.isEn ? 'Receive' : 'Nhận'} ${_dateLabel(income.nextDueDate)}',
                            onTap: () => _incomeActions(
                              context,
                              ref,
                              income,
                              incomeCategories,
                            ),
                          ),
                        ),

                      if (incomeCategories.isEmpty)
                        _Hint(
                          tr.isEn
                              ? 'Failed to load income categories. Please try again later.'
                              : 'Chưa tải được danh mục thu. Vui lòng thử lại sau.',
                        ),
                      const SizedBox(height: 20),
                      Text(
                        tr.isEn ? '↑ Recurring Expense' : '↑ Khoản chi định kỳ',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: context.finance.expense.color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (bills.isEmpty)
                        _EmptyPlanCard(
                          title: tr.isEn ? 'No recurring expense yet' : 'Chưa có khoản chi định kỳ',
                          subtitle: tr.isEn
                              ? 'Add rent, internet, subscriptions... to get reminders when due.'
                              : 'Thêm tiền thuê nhà, internet, gói cước... để được Finmi nhắc nhở khi đến hạn thanh toán.',
                          buttonLabel: tr.isEn ? 'Add expense' : 'Thêm khoản chi',
                          icon: Icons.north_east_rounded,
                          accentColor: context.finance.expense.color,
                          onAdd: () => _editBill(
                            context,
                            ref,
                            expenseCategories,
                          ),
                        ),
                      for (final bill in bills)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _RecurringPlanCard(
                            title: bill.title,
                            amountMinor: bill.amountMinor,
                            detail:
                                '${_categoryName(bill.categoryId ?? '', expenseCategories, tr: tr)} · ${_frequencyLabel(bill.frequency, isEn: tr.isEn)}',
                            due:
                                '${_isOverdue(bill.nextDueDate) ? (tr.isEn ? 'Overdue' : 'Quá hạn') : (tr.isEn ? 'Due' : 'Đến hạn')} ${_dateLabel(bill.nextDueDate)}',
                            overdue: _isOverdue(bill.nextDueDate),
                            onTap: () => _billActions(
                              context,
                              ref,
                              bill,
                              expenseCategories,
                            ),
                          ),
                        ),

                      const SizedBox(height: 20),
                      Text(
                        tr.isEn ? 'Savings Goals' : 'Mục tiêu tiết kiệm',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: context.finmi.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (goals.isEmpty)
                        _EmptyPlanCard(
                          title: tr.isEn ? 'No savings goals yet' : 'Chưa có mục tiêu tiết kiệm',
                          subtitle: tr.isEn
                              ? 'Set goals for shopping, emergency funds or travel to track saving progress.'
                              : 'Đặt mục tiêu mua sắm, tích lũy khẩn cấp hoặc du lịch để kiểm soát tiến độ để dành tiền.',
                          buttonLabel: tr.isEn ? 'Add goal' : 'Thêm mục tiêu',
                          icon: Icons.savings_outlined,
                          accentColor: context.finmi.accent,
                          onAdd: () => _editGoal(context, ref),
                        ),
                      for (final goal in goals)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AppCard(
                            onTap: () => _goalActions(context, ref, goal),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  goal.name,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${MoneyFormatter.format(goal.savedMinor)} / ${MoneyFormatter.format(goal.targetMinor)}',
                                ),
                                const SizedBox(height: 8),
                                LinearProgressIndicator(
                                  value: goal.progress.clamp(0, 1),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  goal.remainingMinor == 0
                                      ? (tr.isEn ? 'Goal achieved' : 'Đã đạt mục tiêu')
                                      : '${tr.isEn ? 'Need to save' : 'Cần dành'} ${MoneyFormatter.format(goal.monthlyNeeded(DateTime.now()))}/${tr.isEn ? 'mo' : 'tháng'} · ${tr.isEn ? 'Due' : 'Hạn'} ${_dateLabel(goal.targetDate)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
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
        builder: (context, setState) {
          final theme = Theme.of(context);
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.finance.income.container,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.south_west_rounded,
                    color: context.finance.income.color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    income == null ? 'Thêm khoản thu cố định' : 'Sửa khoản thu cố định',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400, minWidth: 280),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: title,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: 'Tên khoản thu',
                        hintText: 'Ví dụ: Lương tháng, Cho thuê nhà...',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        prefixIcon: Icon(Icons.edit_note_rounded),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: amount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Số tiền mỗi tháng',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        prefixIcon: Icon(Icons.payments_outlined),
                        suffixText: '₫',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('recurring-income-category'),
                      initialValue: categoryId,
                      isExpanded: true,
                      isDense: true,
                      alignment: AlignmentDirectional.centerStart,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      elevation: 3,
                      borderRadius: BorderRadius.circular(16),
                      menuMaxHeight: 280,
                      dropdownColor: theme.colorScheme.surfaceContainerHigh,
                      decoration: const InputDecoration(
                        labelText: 'Danh mục thu',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        prefixIcon: Icon(Icons.category_outlined),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      selectedItemBuilder: (context) {
                        return categories.map((c) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CategoryAvatar(category: c, radius: 11),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  c.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          );
                        }).toList();
                      },
                      items: categories
                          .map(
                            (category) => DropdownMenuItem(
                              value: category.id,
                              child: Row(
                                children: [
                                  CategoryAvatar(category: category, radius: 12),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      category.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value != null) setState(() => categoryId = value);
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    InkWell(
                      onTap: () async {
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
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    income == null ? 'Ngày nhận' : 'Lần nhận tiếp',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _dateLabel(due),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.edit_calendar_outlined,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
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
          );
        },
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
        builder: (context, setState) {
          final theme = Theme.of(context);
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.finance.expense.container,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.north_east_rounded,
                    color: context.finance.expense.color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    bill == null ? 'Thêm khoản chi cố định' : 'Sửa khoản chi cố định',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400, minWidth: 280),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: title,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: 'Tên khoản',
                        hintText: 'Ví dụ: Tiền thuê nhà, Internet, Điện nước...',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        prefixIcon: Icon(Icons.edit_note_rounded),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: amount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Số tiền',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        prefixIcon: Icon(Icons.payments_outlined),
                        suffixText: '₫',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<BillFrequency>(
                      initialValue: frequency,
                      isExpanded: true,
                      isDense: true,
                      alignment: AlignmentDirectional.centerStart,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      elevation: 3,
                      borderRadius: BorderRadius.circular(16),
                      menuMaxHeight: 280,
                      dropdownColor: theme.colorScheme.surfaceContainerHigh,
                      decoration: const InputDecoration(
                        labelText: 'Tần suất lặp lại',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        prefixIcon: Icon(Icons.repeat_rounded),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
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
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<String>(
                      key: const ValueKey('recurring-bill-category'),
                      initialValue: categoryId ?? '',
                      isExpanded: true,
                      isDense: true,
                      alignment: AlignmentDirectional.centerStart,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      elevation: 3,
                      borderRadius: BorderRadius.circular(16),
                      menuMaxHeight: 280,
                      dropdownColor: theme.colorScheme.surfaceContainerHigh,
                      decoration: const InputDecoration(
                        labelText: 'Danh mục ngân sách',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        prefixIcon: Icon(Icons.category_outlined),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      selectedItemBuilder: (context) {
                        return [
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.help_outline, size: 20),
                              SizedBox(width: 10),
                              Flexible(child: Text('Chưa phân loại', overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                          if (categoryId != null &&
                              !categories.any((item) => item.id == categoryId))
                            const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.error_outline, size: 20),
                                SizedBox(width: 10),
                                Flexible(child: Text('Danh mục hiện không có sẵn', overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                          for (final category in categories)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CategoryAvatar(category: category, radius: 11),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    category.name,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                        ];
                      },
                      items: [
                        const DropdownMenuItem<String>(
                          value: '',
                          child: Row(
                            children: [
                              Icon(Icons.help_outline, size: 20),
                              SizedBox(width: 10),
                              Expanded(child: Text('Chưa phân loại')),
                            ],
                          ),
                        ),
                        if (categoryId != null &&
                            !categories.any((item) => item.id == categoryId))
                          DropdownMenuItem(
                            value: categoryId,
                            child: const Row(
                              children: [
                                Icon(Icons.error_outline, size: 20),
                                SizedBox(width: 10),
                                Expanded(child: Text('Danh mục hiện không có sẵn')),
                              ],
                            ),
                          ),
                        for (final category in categories)
                          DropdownMenuItem(
                            value: category.id,
                            child: Row(
                              children: [
                                CategoryAvatar(category: category, radius: 12),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    category.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (value) => setState(
                        () => categoryId = value == null || value.isEmpty
                            ? null
                            : value,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    InkWell(
                      onTap: () async {
                        final chosen = await showDatePicker(
                          context: context,
                          initialDate: due,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (chosen != null) setState(() => due = chosen);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Hạn thanh toán',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _dateLabel(due),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.edit_calendar_outlined,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
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
          );
        },
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
        builder: (context, setState) {
          final theme = Theme.of(context);
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.finmi.accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.savings_outlined,
                    color: context.finmi.accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    goal == null ? 'Thêm mục tiêu tiết kiệm' : 'Sửa mục tiêu tiết kiệm',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400, minWidth: 280),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: name,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: 'Tên mục tiêu',
                        hintText: 'Ví dụ: Quỹ khẩn cấp, Mua laptop, Du lịch...',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        prefixIcon: Icon(Icons.flag_outlined),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: target,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Số tiền mục tiêu',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        prefixIcon: Icon(Icons.savings_outlined),
                        suffixText: '₫',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    InkWell(
                      onTap: () async {
                        final chosen = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (chosen != null) setState(() => date = chosen);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Thời hạn hoàn thành',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _dateLabel(date),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.edit_calendar_outlined,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
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
          );
        },
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
    final tr = context.tr;
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: Text(income.title),
              subtitle: Text(
                '${tr.isEn ? "Next due" : "Lần nhận tiếp theo"}: ${_dateLabel(income.nextDueDate)}',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(tr.isEn ? 'Edit' : 'Sửa', maxLines: 3),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(tr.isEn ? 'Stop recurring income' : 'Ngừng khoản thu định kỳ', maxLines: 3),
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
    final tr = context.tr;
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: Text(bill.title),
              subtitle: Text(
                '${tr.isEn ? "Due" : "Đến hạn"} ${_dateLabel(bill.nextDueDate)}',
                maxLines: 3,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: Text(tr.isEn ? 'Mark paid and record expense' : 'Đã thanh toán và ghi khoản chi', maxLines: 3),
              onTap: () => Navigator.pop(context, 'paid'),
            ),
            ListTile(
              leading: const Icon(Icons.skip_next_outlined),
              title: Text(
                tr.isEn ? 'Already recorded or skip this period' : 'Đã ghi chi trước đó hoặc bỏ qua kỳ này',
                maxLines: 3,
              ),
              onTap: () => Navigator.pop(context, 'skip'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(tr.isEn ? 'Edit' : 'Sửa', maxLines: 3),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(tr.isEn ? 'Delete' : 'Xóa', maxLines: 3),
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
              notes: '${tr.isEn ? "Recurring bill" : "Khoản định kỳ"}: ${_dateLabel(current.nextDueDate)}',
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
                  ? (tr.isEn ? 'Expense recorded.' : 'Đã ghi khoản chi.')
                  : (tr.isEn ? 'Moved to next period.' : 'Đã chuyển sang kỳ tiếp theo.'),
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
    final tr = context.tr;
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(title: Text(goal.name)),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: Text(tr.isEn ? 'Update saved amount' : 'Cập nhật tiền đã để dành', maxLines: 3),
              onTap: () => Navigator.pop(context, 'add'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(tr.isEn ? 'Edit' : 'Sửa', maxLines: 3),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(tr.isEn ? 'Delete' : 'Xóa', maxLines: 3),
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
        builder: (context, setState) {
          final theme = Theme.of(context);
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.finmi.accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.savings_outlined,
                    color: context.finmi.accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Cập nhật tiền đã để dành',
                    maxLines: 2,
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400, minWidth: 280),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Tổng số tiền đã tích lũy',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      prefixIcon: Icon(Icons.payments_outlined),
                      suffixText: '₫',
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      error!,
                      style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                    ),
                  ],
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
          );
        },
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
    this.income = false,
  });

  final String title;
  final int amountMinor;
  final String detail;
  final String due;
  final VoidCallback onTap;
  final bool overdue;
  final bool income;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 3),
        Text(
          detail,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          due,
          style: theme.textTheme.bodySmall?.copyWith(
            color: overdue
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    final amount = Text(
      '${income ? '+' : '-'} ${MoneyFormatter.format(amountMinor)}',
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: income
            ? context.finance.income.color
            : theme.colorScheme.onSurface,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: context.needsStackedLayout
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [details, const SizedBox(height: 8), amount],
            )
          : Row(
              children: [
                Expanded(child: details),
                const SizedBox(width: 12),
                Flexible(child: amount),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
    );
  }
}

String _frequencyLabel(BillFrequency frequency, {bool isEn = false}) => switch (frequency) {
  BillFrequency.weekly => isEn ? 'Weekly' : 'Hàng tuần',
  BillFrequency.monthly => isEn ? 'Monthly' : 'Hàng tháng',
  BillFrequency.yearly => isEn ? 'Yearly' : 'Hàng năm',
};

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String _dateLabel(DateTime date) => '${date.day}/${date.month}/${date.year}';
bool _isOverdue(DateTime date) =>
    DateTime(date.year, date.month, date.day).isBefore(
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
    );

String _categoryName(String id, List<CategoryEntity> categories, {AppStrings? tr}) {
  final cat = categories.where((category) => category.id == id).firstOrNull;
  if (cat == null) return tr?.isEn ?? false ? 'Unclassified' : 'Chưa phân loại';
  return tr != null ? tr.categoryName(cat.name, categoryId: cat.id) : cat.name;
}

class _EmptyPlanCard extends StatelessWidget {
  const _EmptyPlanCard({
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.icon,
    required this.accentColor,
    required this.onAdd,
  });

  final String title;
  final String subtitle;
  final String buttonLabel;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
          width: 1.25,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(buttonLabel),
              style: OutlinedButton.styleFrom(
                foregroundColor: accentColor,
                side: BorderSide(
                  color: accentColor.withValues(alpha: 0.45),
                  width: 1.2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

