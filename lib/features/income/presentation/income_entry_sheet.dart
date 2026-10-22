import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/money_input_formatter.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../budgets/presentation/category_management.dart';
import '../../invoices/domain/invoice_models.dart';
import '../data/income_repository.dart';

class IncomeEntrySheet extends ConsumerStatefulWidget {
  const IncomeEntrySheet({
    this.entry,
    this.initialAmountMinor,
    this.initialDate,
    this.initialCategoryId,
    super.key,
  });

  final IncomeEntry? entry;
  final int? initialAmountMinor;
  final DateTime? initialDate;
  final String? initialCategoryId;

  @override
  ConsumerState<IncomeEntrySheet> createState() => _IncomeEntrySheetState();
}

class _IncomeEntrySheetState extends ConsumerState<IncomeEntrySheet> {
  late final TextEditingController _amount = TextEditingController(
    text: MoneyInputFormatter.format(
      (widget.entry?.amountMinor ?? widget.initialAmountMinor)?.toString(),
    ),
  );
  String? _categoryId;
  late final _note = TextEditingController(text: widget.entry?.note ?? '');
  late DateTime _date =
      widget.entry?.receivedAt ??
      widget.initialDate ??
      DateUtils.dateOnly(DateTime.now());
  bool _saving = false;
  String? _error;
  String? _categoryError;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.entry?.categoryId ?? widget.initialCategoryId;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = MoneyFormatter.tryParse(_amount.text);
    if (value == null || value <= 0 || value > 9007199254740991) {
      setState(() => _error = 'Nhập số tiền nguyên lớn hơn 0.');
      return;
    }
    final categories =
        ref.read(incomeCategoriesProvider).valueOrNull ?? const [];
    final categoryId = categories.any((category) => category.id == _categoryId)
        ? _categoryId
        : categories.firstOrNull?.id;
    if (categoryId == null) {
      setState(() => _categoryError = 'Hãy tạo hoặc chọn danh mục thu.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(incomeRepositoryProvider)
          .save(
            value,
            source: widget.entry?.source ?? IncomeSource.manual,
            categoryId: categoryId,
            existing: widget.entry,
            note: _note.text,
            receivedAt: _date,
          );
      if (mounted) Navigator.pop(context, true);
    } on Object {
      if (mounted) {
        setState(() => _error = 'Không lưu được khoản thu. Hãy thử lại.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final entry = widget.entry;
    if (entry == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa khoản thu?', maxLines: 3),
        content: const Text(
          'Khoản thu này sẽ bị xóa khỏi lịch sử và tổng thu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await ref.read(incomeRepositoryProvider).delete(entry.id);
      if (mounted) Navigator.pop(context, true);
    } on Object {
      if (mounted) {
        setState(() => _error = 'Không xóa được khoản thu. Hãy thử lại.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addCategory(List<CategoryEntity> categories) async {
    final category = await createCategoryFromEntry(
      context,
      ref,
      categories,
      CategoryKind.income,
    );
    if (category != null && mounted) {
      setState(() {
        _categoryId = category.id;
        _categoryError = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        ref.watch(incomeCategoriesProvider).valueOrNull ?? const [];
    final categoryId = categories.any((category) => category.id == _categoryId)
        ? _categoryId
        : categories.firstOrNull?.id;
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            12,
            24,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.entry == null ? 'Thêm khoản thu' : 'Sửa khoản thu',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _amount,
                autofocus: true,
                enabled: !_saving,
                inputFormatters: [const MoneyInputFormatter()],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: false,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: 'Số tiền (₫)',
                  errorText: _error,
                  prefixIcon: const Icon(Icons.add_circle_outline),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey('income-category-${categoryId ?? 'loading'}'),
                initialValue: categoryId,
                decoration: InputDecoration(
                  labelText: 'Danh mục thu',
                  errorText: _categoryError,
                  prefixIcon: const Icon(Icons.category_outlined),
                ),
                items: [
                  for (final category in categories)
                    DropdownMenuItem(
                      value: category.id,
                      child: Text(category.name),
                    ),
                ],
                onChanged: _saving || categories.isEmpty
                    ? null
                    : (id) => setState(() {
                        _categoryId = id;
                        _categoryError = null;
                      }),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _saving ? null : () => _addCategory(categories),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm loại khoản thu'),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _note,
                enabled: !_saving,
                maxLines: 3,
                maxLength: 2000,
                decoration: const InputDecoration(labelText: 'Nội dung'),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(
                  'Ngày giao dịch: ${DateFormat('dd/MM/yyyy').format(_date)}',
                ),
                onPressed: _saving
                    ? null
                    : () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _date,
                          firstDate: DateTime(1900),
                          lastDate: DateTime(2100, 12, 31),
                        );
                        if (date != null && mounted) {
                          setState(() => _date = date);
                        }
                      },
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Đang lưu…' : 'Lưu khoản thu'),
              ),
              if (widget.entry != null)
                TextButton(
                  onPressed: _saving ? null : _delete,
                  child: const Text('Xóa khoản thu'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
