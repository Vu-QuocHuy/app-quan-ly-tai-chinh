import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../data/income_repository.dart';

class IncomeEntrySheet extends ConsumerStatefulWidget {
  const IncomeEntrySheet({this.entry, super.key});

  final IncomeEntry? entry;

  @override
  ConsumerState<IncomeEntrySheet> createState() => _IncomeEntrySheetState();
}

class _IncomeEntrySheetState extends ConsumerState<IncomeEntrySheet> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.entry?.amountMinor.toString() ?? '',
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = int.tryParse(_amount.text);
    if (value == null || value <= 0 || value > 9007199254740991) {
      setState(() => _error = 'Nhập số tiền lớn hơn 0.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(incomeRepositoryProvider)
          .save(value, existing: widget.entry);
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
        title: const Text('Xóa khoản thu?'),
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: 'Số tiền (₫)',
                errorText: _error,
                prefixIcon: const Icon(Icons.add_circle_outline),
              ),
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
    );
  }
}
