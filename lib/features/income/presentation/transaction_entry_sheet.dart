import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../../shared/dialogs/confirm_dialog.dart';
import '../../../shared/widgets/finmi_text_field.dart';
import '../../budgets/presentation/category_management.dart';
import '../../invoices/domain/invoice_models.dart';
import '../data/income_repository.dart';

Future<bool?> showTransactionEntry(
  BuildContext context, {
  bool income = true,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => TransactionEntrySheet(initialIncome: income),
);

class TransactionEntrySheet extends ConsumerStatefulWidget {
  const TransactionEntrySheet({this.initialIncome = true, super.key});
  final bool initialIncome;

  @override
  ConsumerState<TransactionEntrySheet> createState() =>
      _TransactionEntrySheetState();
}

class _TransactionEntrySheetState extends ConsumerState<TransactionEntrySheet> {
  final _form = GlobalKey<FormState>();
  final _incomeDraft = _EntryDraft();
  final _expenseDraft = _EntryDraft();
  late bool _income = widget.initialIncome;
  bool _saving = false;
  bool _closing = false;
  String? _error;
  _EntryDraft get _draft => _income ? _incomeDraft : _expenseDraft;
  bool get _dirty => [_incomeDraft, _expenseDraft].any((d) => d.dirty);

  @override
  void dispose() {
    _incomeDraft.dispose();
    _expenseDraft.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_saving) return;
    if (_dirty && !await showDiscardChangesDialog(context)) return;
    if (!mounted) return;
    setState(() => _closing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    final draft = _draft;
    final amount = MoneyFormatter.tryParse(draft.amount.text)!;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_income) {
        await ref
            .read(incomeRepositoryProvider)
            .save(
              amount,
              source: IncomeSource.manual,
              categoryId: draft.categoryId,
              receivedAt: draft.date,
              note: draft.note.text,
            );
      } else {
        final now = DateTime.now();
        final categories = ref.read(categoriesProvider).valueOrNull ?? [];
        final category = categories
            .where((c) => c.id == draft.categoryId)
            .first;
        await ref
            .read(invoiceRepositoryProvider)
            .saveInvoice(
              InvoiceEntity(
                id: const Uuid().v4(),
                sellerName: draft.note.text.trim().isEmpty
                    ? category.name
                    : draft.note.text.trim(),
                notes: draft.note.text.trim(),
                currencyCode: 'VND',
                subtotalMinor: amount,
                taxMinor: 0,
                totalMinor: amount,
                sourceType: InvoiceSourceType.manual,
                status: InvoiceStatus.confirmed,
                categoryId: draft.categoryId,
                issuedAt: draft.date,
                createdAt: now,
                updatedAt: now,
                confirmedAt: now,
              ),
            );
      }
      if (!mounted) return;
      setState(() => _closing = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
    } on Object {
      if (mounted) {
        setState(() => _error = 'Không lưu được giao dịch. Hãy thử lại.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(
      _income ? incomeCategoriesProvider : categoriesProvider,
    );
    final items = categories.valueOrNull ?? const <CategoryEntity>[];
    final draft = _draft;
    return PopScope(
      canPop: _closing || (!_saving && !_dirty),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Thêm thu/chi',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Đóng',
                      onPressed: _saving ? null : _close,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked =
                        constraints.maxWidth < 330 ||
                        MediaQuery.textScalerOf(context).scale(14) > 18;
                    Widget tab(bool income, String label) => OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                              _income = income;
                              _error = null;
                            }),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: _income == income
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                        side: BorderSide(
                          color: _income == income
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                          width: 1.25,
                        ),
                      ),
                      child: Text(label, textAlign: TextAlign.center),
                    );
                    return stacked
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              tab(true, 'Thêm khoản thu'),
                              const SizedBox(height: 8),
                              tab(false, 'Thêm khoản chi'),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(child: tab(true, 'Thêm khoản thu')),
                              const SizedBox(width: 8),
                              Expanded(child: tab(false, 'Thêm khoản chi')),
                            ],
                          );
                  },
                ),
                const SizedBox(height: 20),
                FinmiTextField(
                  key: ValueKey('amount-$_income'),
                  controller: draft.amount,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Số tiền (₫)'),
                  onChanged: (_) => setState(() {}),
                  validator: (text) {
                    final value = MoneyFormatter.tryParse(text ?? '');
                    return value == null ||
                            value <= 0 ||
                            value > 9007199254740991
                        ? 'Nhập số tiền nguyên lớn hơn 0.'
                        : null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  key: ValueKey('category-$_income-${draft.categoryId}'),
                  initialValue: items.any((c) => c.id == draft.categoryId)
                      ? draft.categoryId
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Danh mục',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: [
                    for (final c in items)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => draft.categoryId = value),
                  validator: (value) =>
                      value == null ? 'Chọn danh mục giao dịch.' : null,
                ),
                if (categories.hasError)
                  TextButton(
                    onPressed: () => ref.invalidate(
                      _income ? incomeCategoriesProvider : categoriesProvider,
                    ),
                    child: const Text('Tải lại danh mục'),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _saving
                        ? null
                        : () async {
                            final c = await createCategoryFromEntry(
                              context,
                              ref,
                              items,
                              _income
                                  ? CategoryKind.income
                                  : CategoryKind.expense,
                            );
                            if (c != null && mounted) {
                              setState(() => draft.categoryId = c.id);
                            }
                          },
                    icon: const Icon(Icons.add),
                    label: const Text('Thêm danh mục'),
                  ),
                ),
                FinmiTextField(
                  key: ValueKey('note-$_income'),
                  controller: draft.note,
                  enabled: !_saving,
                  maxLines: 3,
                  maxLength: 2000,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Nội dung',
                    hintText: 'Ghi chú về giao dịch',
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    'Ngày giao dịch: ${DateFormat('dd/MM/yyyy').format(draft.date)}',
                  ),
                  onPressed: _saving
                      ? null
                      : () async {
                          final value = await showDatePicker(
                            context: context,
                            initialDate: draft.date,
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2100, 12, 31),
                          );
                          if (value != null && mounted) {
                            setState(() {
                              draft.date = value;
                              draft.dateChanged = true;
                            });
                          }
                        },
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Đang lưu…' : 'Lưu giao dịch'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EntryDraft {
  final amount = TextEditingController();
  final note = TextEditingController();
  String? categoryId;
  DateTime date = DateUtils.dateOnly(DateTime.now());
  bool dateChanged = false;
  bool get dirty =>
      amount.text.isNotEmpty ||
      note.text.isNotEmpty ||
      categoryId != null ||
      dateChanged;
  void dispose() {
    amount.dispose();
    note.dispose();
  }
}
