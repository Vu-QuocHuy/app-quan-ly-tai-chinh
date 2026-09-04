import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../ingestion/domain/invoice_validator.dart';
import '../../invoices/domain/invoice_models.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../../shared/widgets/app_callout.dart';

class ReviewInvoiceScreen extends ConsumerStatefulWidget {
  const ReviewInvoiceScreen({required this.invoice, super.key});

  final InvoiceEntity invoice;

  @override
  ConsumerState<ReviewInvoiceScreen> createState() =>
      _ReviewInvoiceScreenState();
}

class _ReviewInvoiceScreenState extends ConsumerState<ReviewInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _validationSummaryFocusNode = FocusNode();
  late final TextEditingController _sellerController;
  late final TextEditingController _taxCodeController;
  late final TextEditingController _numberController;
  late final TextEditingController _subtotalController;
  late final TextEditingController _taxController;
  late final TextEditingController _totalController;
  late final TextEditingController _notesController;
  late final TextEditingController _tagsController;
  late final List<_InvoiceLineDraft> _lineDrafts;
  late DateTime? _issuedAt;
  late String? _categoryId;
  bool _saving = false;
  List<String> _validationMessages = const [];
  // Ba thứ khác nhau về ngữ nghĩa từng bị nhét chung một khối đỏ:
  // lỗi chặn, cảnh báo tư vấn, và lỗi hệ thống khi lưu.
  CalloutTone _validationTone = CalloutTone.warning;

  @override
  void initState() {
    super.initState();
    final invoice = widget.invoice;
    _sellerController = TextEditingController(text: invoice.sellerName);
    _taxCodeController = TextEditingController(text: invoice.sellerTaxCode);
    _numberController = TextEditingController(text: invoice.invoiceNumber);
    _subtotalController = TextEditingController(
      text: invoice.subtotalMinor.toString(),
    );
    _taxController = TextEditingController(text: invoice.taxMinor.toString());
    _totalController = TextEditingController(
      text: invoice.totalMinor.toString(),
    );
    _notesController = TextEditingController(text: invoice.notes);
    _tagsController = TextEditingController(text: invoice.tags.join(', '));
    _lineDrafts = invoice.lines
        .map(_InvoiceLineDraft.fromEntity)
        .toList(growable: true);
    _issuedAt = invoice.issuedAt;
    _categoryId = invoice.categoryId;
  }

  @override
  void dispose() {
    _sellerController.dispose();
    _taxCodeController.dispose();
    _numberController.dispose();
    _subtotalController.dispose();
    _taxController.dispose();
    _totalController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    for (final draft in _lineDrafts) {
      draft.dispose();
    }
    _validationSummaryFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final lowConfidence = widget.invoice.evidence
        .where((item) => item.confidence < 0.75)
        .map((item) => item.fieldName)
        .toSet();
    return Scaffold(
      appBar: AppBar(title: const Text('Kiểm tra hóa đơn')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReviewNotice(source: widget.invoice.sourceType),
              if (_validationMessages.isNotEmpty) ...[
                const SizedBox(height: 12),
                _ValidationSummary(
                  tone: _validationTone,
                  messages: _validationMessages,
                  focusNode: _validationSummaryFocusNode,
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Thông tin hóa đơn',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _sellerController,
                decoration: InputDecoration(
                  labelText: 'Tên người bán *',
                  helperText: lowConfidence.contains('sellerName')
                      ? 'Độ tin cậy thấp — vui lòng kiểm tra'
                      : null,
                  prefixIcon: const Icon(Icons.storefront_outlined),
                ),
                textInputAction: TextInputAction.next,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Hãy nhập tên người bán.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _taxCodeController,
                decoration: const InputDecoration(
                  labelText: 'Mã số thuế người bán',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _numberController,
                decoration: const InputDecoration(
                  labelText: 'Số hóa đơn',
                  prefixIcon: Icon(Icons.numbers),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              Semantics(
                button: true,
                label: _issuedAt == null
                    ? 'Chọn ngày lập hóa đơn'
                    : 'Ngày lập ${DateFormat('dd/MM/yyyy').format(_issuedAt!)}',
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: const Text('Ngày lập hóa đơn'),
                  subtitle: Text(
                    _issuedAt == null
                        ? 'Chưa xác định'
                        : DateFormat('dd/MM/yyyy').format(_issuedAt!),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickDate,
                ),
              ),
              const SizedBox(height: 24),
              Text('Số tiền', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              _MoneyField(controller: _subtotalController, label: 'Trước thuế'),
              const SizedBox(height: 12),
              _MoneyField(controller: _taxController, label: 'Thuế'),
              const SizedBox(height: 12),
              _MoneyField(
                controller: _totalController,
                label: 'Tổng thanh toán *',
                requiredPositive: true,
                lowConfidence: lowConfidence.contains('totalMinor'),
              ),
              const SizedBox(height: 24),
              Text('Phân loại', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _categoryId,
                decoration: const InputDecoration(
                  labelText: 'Danh mục',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: categories
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(item.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setState(() => _categoryId = value),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tagsController,
                decoration: const InputDecoration(
                  labelText: 'Nhãn',
                  hintText: 'Ví dụ: công việc, hoàn tiền',
                  helperText: 'Phân tách nhiều nhãn bằng dấu phẩy.',
                  prefixIcon: Icon(Icons.sell_outlined),
                ),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú',
                  hintText: 'Thông tin cần nhớ về hóa đơn này',
                  prefixIcon: Icon(Icons.notes_outlined),
                  alignLabelWithHint: true,
                ),
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 24),
              _buildLineItemsEditor(context),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _saving ? null : () => context.pop(),
                child: const Text('Để sau'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                key: const Key('confirm-invoice-button'),
                onPressed: _saving ? null : _confirm,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_saving ? 'Đang lưu' : 'Xác nhận và lưu'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final result = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDate: _issuedAt ?? DateTime.now(),
    );
    if (result != null) setState(() => _issuedAt = result);
  }

  Future<void> _confirm() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      final messages = <String>[
        if (_sellerController.text.trim().isEmpty) 'Hãy nhập tên người bán.',
        if ((MoneyFormatter.tryParse(_totalController.text) ?? 0) <= 0)
          'Tổng tiền phải lớn hơn 0.',
      ];
      setState(() => _validationMessages = messages);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _validationSummaryFocusNode.requestFocus();
      });
      return;
    }
    final now = DateTime.now();
    final subtotal = MoneyFormatter.tryParse(_subtotalController.text) ?? 0;
    final tax = MoneyFormatter.tryParse(_taxController.text) ?? 0;
    final total = MoneyFormatter.tryParse(_totalController.text) ?? 0;
    final lines = _lineDrafts.map(_toInvoiceLine).toList(growable: false);
    final updated = widget.invoice.copyWith(
      sellerName: _sellerController.text.trim(),
      sellerTaxCode: _taxCodeController.text.trim(),
      invoiceNumber: _numberController.text.trim(),
      issuedAt: _issuedAt,
      subtotalMinor: subtotal,
      taxMinor: tax,
      totalMinor: total,
      lines: lines,
      categoryId: _categoryId ?? 'other',
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      clearNotes: _notesController.text.trim().isEmpty,
      tags: _tagsController.text
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toSet()
          .toList(growable: false),
      status: InvoiceStatus.confirmed,
      updatedAt: now,
      confirmedAt: now,
      evidence: _updatedEvidence(
        sellerName: _sellerController.text.trim(),
        sellerTaxCode: _taxCodeController.text.trim(),
        invoiceNumber: _numberController.text.trim(),
        subtotal: subtotal,
        tax: tax,
        total: total,
      ),
    );
    final validation = const InvoiceValidator().validate(updated);
    if (!validation.isValid) {
      setState(() {
        _validationMessages = validation.errors;
        _validationTone = CalloutTone.danger;
      });
      return;
    }
    setState(() {
      _saving = true;
      _validationMessages = validation.warnings;
      // Cảnh báo tư vấn KHÔNG phải lỗi -> không dùng màu phá hủy.
      _validationTone = CalloutTone.warning;
    });
    try {
      final repository = ref.read(invoiceRepositoryProvider);
      await repository.saveInvoice(updated);
      if (_categoryId != null) {
        await repository.saveMerchantRule(updated.sellerName, _categoryId!);
      }
      if (mounted) context.go('/invoices');
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _validationMessages = ['Không thể lưu: ${friendlyMessage(error)}'];
          _validationTone = CalloutTone.danger;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<FieldEvidenceEntity> _updatedEvidence({
    required String sellerName,
    required String sellerTaxCode,
    required String invoiceNumber,
    required int subtotal,
    required int tax,
    required int total,
  }) {
    final values = <String, String>{
      'sellerName': sellerName,
      'sellerTaxCode': sellerTaxCode,
      'invoiceNumber': invoiceNumber,
      'subtotalMinor': subtotal.toString(),
      'taxMinor': tax.toString(),
      'totalMinor': total.toString(),
    };
    return widget.invoice.evidence
        .map((item) {
          final value = values[item.fieldName];
          if (value == null || value == item.normalizedValue) return item;
          return FieldEvidenceEntity(
            id: item.id,
            fieldName: item.fieldName,
            rawValue: item.rawValue,
            normalizedValue: value,
            source: item.source,
            confidence: item.confidence,
            correctedByUser: true,
          );
        })
        .toList(growable: false);
  }

  Widget _buildLineItemsEditor(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Hàng hóa, dịch vụ',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Text(
              '${_lineDrafts.length} dòng',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < _lineDrafts.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildLineCard(context, index),
          ),
        OutlinedButton.icon(
          onPressed: _addLine,
          icon: const Icon(Icons.add),
          label: const Text('Thêm dòng hàng hóa'),
        ),
      ],
    );
  }

  Widget _buildLineCard(BuildContext context, int index) {
    final draft = _lineDrafts[index];
    return Card(
      key: ValueKey(draft.id),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Dòng ${index + 1}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Xóa dòng ${index + 1}',
                  onPressed: () => _removeLine(index),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            TextFormField(
              controller: draft.descriptionController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Mô tả hàng hóa/dịch vụ *',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Hãy nhập mô tả dòng hàng.'
                  : null,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: draft.quantityController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Số lượng'),
                    validator: (value) => _validateOptionalDecimal(value),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: draft.unitPriceController,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Đơn giá',
                      suffixText: '₫',
                    ),
                    validator: (value) => _validateOptionalMoney(value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: draft.taxRateController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Thuế suất',
                suffixText: '%',
              ),
              validator: (value) => _validateOptionalDecimal(value),
            ),
            const SizedBox(height: 12),
            _MoneyField(
              controller: draft.totalController,
              label: 'Thành tiền *',
            ),
          ],
        ),
      ),
    );
  }

  void _addLine() {
    setState(() => _lineDrafts.add(_InvoiceLineDraft.empty()));
  }

  void _removeLine(int index) {
    final draft = _lineDrafts.removeAt(index);
    draft.dispose();
    setState(() {});
  }

  InvoiceLineEntity _toInvoiceLine(_InvoiceLineDraft draft) {
    return InvoiceLineEntity(
      id: draft.id,
      description: draft.descriptionController.text.trim(),
      quantity: _parseDecimal(draft.quantityController.text),
      unitPriceMinor: MoneyFormatter.tryParse(draft.unitPriceController.text),
      taxRate: _parseDecimal(draft.taxRateController.text),
      totalMinor: MoneyFormatter.tryParse(draft.totalController.text) ?? 0,
    );
  }

  String? _validateOptionalDecimal(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = _parseDecimal(value);
    return parsed == null || parsed < 0 ? 'Giá trị không hợp lệ.' : null;
  }

  String? _validateOptionalMoney(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = MoneyFormatter.tryParse(value);
    return parsed == null || parsed < 0 ? 'Số tiền không hợp lệ.' : null;
  }

  double? _parseDecimal(String value) {
    if (value.trim().isEmpty) return null;
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }
}

class _InvoiceLineDraft {
  _InvoiceLineDraft({
    required this.id,
    String? description,
    String? quantity,
    String? unitPrice,
    String? taxRate,
    String? total,
  }) : descriptionController = TextEditingController(text: description),
       quantityController = TextEditingController(text: quantity),
       unitPriceController = TextEditingController(text: unitPrice),
       taxRateController = TextEditingController(text: taxRate),
       totalController = TextEditingController(text: total);

  factory _InvoiceLineDraft.empty() =>
      _InvoiceLineDraft(id: 'line-${const Uuid().v4()}', total: '0');

  factory _InvoiceLineDraft.fromEntity(InvoiceLineEntity line) =>
      _InvoiceLineDraft(
        id: line.id,
        description: line.description,
        quantity: line.quantity?.toString(),
        unitPrice: line.unitPriceMinor?.toString(),
        taxRate: line.taxRate?.toString(),
        total: line.totalMinor.toString(),
      );

  final String id;
  final TextEditingController descriptionController;
  final TextEditingController quantityController;
  final TextEditingController unitPriceController;
  final TextEditingController taxRateController;
  final TextEditingController totalController;

  void dispose() {
    descriptionController.dispose();
    quantityController.dispose();
    unitPriceController.dispose();
    taxRateController.dispose();
    totalController.dispose();
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.controller,
    required this.label,
    this.requiredPositive = false,
    this.lowConfidence = false,
  });

  final TextEditingController controller;
  final String label;
  final bool requiredPositive;
  final bool lowConfidence;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.payments_outlined),
        suffixText: '₫',
        helperText: lowConfidence
            ? 'Độ tin cậy thấp — vui lòng kiểm tra'
            : null,
      ),
      validator: (value) {
        final parsed = MoneyFormatter.tryParse(value ?? '');
        if (parsed == null || parsed < 0) return 'Số tiền không hợp lệ.';
        if (requiredPositive && parsed <= 0) return 'Tổng tiền phải lớn hơn 0.';
        return null;
      },
    );
  }
}

class _ReviewNotice extends StatelessWidget {
  const _ReviewNotice({required this.source});

  final InvoiceSourceType source;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.fact_check_outlined, color: scheme.onPrimaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                source == InvoiceSourceType.xml
                    ? 'Dữ liệu được đọc từ XML. Hãy kiểm tra các trường còn thiếu trước khi lưu.'
                    : 'Dữ liệu OCR/AI có thể sai. Hãy đối chiếu tên người bán, ngày và tổng thanh toán.',
                style: TextStyle(color: scheme.onPrimaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ValidationSummary extends StatelessWidget {
  const _ValidationSummary({
    required this.messages,
    required this.focusNode,
    required this.tone,
  });

  final List<String> messages;
  final FocusNode focusNode;
  final CalloutTone tone;

  @override
  Widget build(BuildContext context) {
    final isBlocking = tone == CalloutTone.danger;
    return Focus(
      focusNode: focusNode,
      child: AppCallout(
        liveRegion: true,
        tone: tone,
        title: isBlocking ? 'Cần sửa trước khi lưu' : 'Nên kiểm tra lại',
        message: messages.map((message) => '• $message').join('\n'),
      ),
    );
  }
}
