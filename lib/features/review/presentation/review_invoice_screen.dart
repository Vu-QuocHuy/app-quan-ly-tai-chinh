import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme/app_tokens.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/money_formatter.dart';
import '../../ingestion/domain/invoice_validator.dart';
import '../../invoices/domain/invoice_models.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../../shared/widgets/app_callout.dart';
import '../../../shared/dialogs/confirm_dialog.dart';
import '../../../shared/widgets/app_skeleton.dart';

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
  late final TextEditingController _subtotalController;
  late final TextEditingController _taxController;
  late final TextEditingController _discountController;
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
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;
  bool _dirty = false;

  // Legacy manually entered invoices with tax or item rows keep the full form.
  bool get _isManualExpense =>
      widget.invoice.sourceType == InvoiceSourceType.manual &&
      widget.invoice.lines.isEmpty &&
      widget.invoice.taxMinor == 0 &&
      widget.invoice.discountMinor == 0 &&
      widget.invoice.subtotalMinor == widget.invoice.totalMinor;

  @override
  void initState() {
    super.initState();
    final invoice = widget.invoice;
    _sellerController = TextEditingController(text: invoice.sellerName);
    _subtotalController = TextEditingController(
      text: invoice.subtotalMinor.toString(),
    );
    _taxController = TextEditingController(text: invoice.taxMinor.toString());
    _discountController = TextEditingController(
      text: invoice.discountMinor.toString(),
    );
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
    if (invoice.sourceType == InvoiceSourceType.imageOcr) {
      final validation = const InvoiceValidator().validate(invoice);
      _validationMessages = [...validation.errors, ...validation.warnings];
      if (validation.errors.isNotEmpty) {
        _validationTone = CalloutTone.danger;
      }
    }
    for (final controller in _watchedControllers) {
      controller.addListener(_recomputeDirty);
    }
  }

  @override
  void dispose() {
    // Gỡ listener TRƯỚC khi dispose: gọi removeListener trên một controller đã
    // dispose sẽ ném.
    for (final controller in _watchedControllers) {
      controller.removeListener(_recomputeDirty);
    }
    _sellerController.dispose();
    _subtotalController.dispose();
    _taxController.dispose();
    _discountController.dispose();
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
    return PopScope(
      // Form này là nơi người dùng sửa kết quả OCR — mất nó là mất công sức
      // thật. Trước đây vuốt back là mất trắng, không hỏi gì.
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isManualExpense
                ? widget.invoice.status == InvoiceStatus.confirmed
                      ? 'Sửa khoản chi'
                      : 'Thêm khoản chi'
                : 'Kiểm tra hóa đơn',
          ),
        ),
        body: Form(
          key: _formKey,
          autovalidateMode: _autovalidate,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: AppBreakpoints.readingWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_isManualExpense)
                      _ReviewNotice(source: widget.invoice.sourceType),
                    if (_validationMessages.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _ValidationSummary(
                        tone: _validationTone,
                        messages: _validationMessages,
                        focusNode: _validationSummaryFocusNode,
                      ),
                    ],
                    if (_isManualExpense) ...[
                      TextFormField(
                        controller: _sellerController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Nội dung chi (tùy chọn)',
                          hintText: 'Ví dụ: ăn sáng, gửi xe',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildDateField(),
                      const SizedBox(height: 20),
                      _MoneyField(
                        controller: _totalController,
                        label: 'Số tiền *',
                        requiredPositive: true,
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        initialValue: _categoryForDropdown(
                          _categoryId,
                          categories,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Danh mục chi tiêu',
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
                        onChanged: (value) {
                          setState(() => _categoryId = value);
                          _recomputeDirty();
                        },
                      ),
                    ] else ...[
                      const SizedBox(height: 20),
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
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Hãy nhập tên người bán.'
                            : null,
                      ),
                      const SizedBox(height: 10),
                      _buildDateField(),
                      const SizedBox(height: 20),
                      Text(
                        'Số tiền',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      _fieldPair(
                        minFieldWidth: 148,
                        first: _MoneyField(
                          controller: _subtotalController,
                          label: 'Trước thuế',
                        ),
                        second: _MoneyField(
                          controller: _discountController,
                          label: 'Giảm giá',
                          lowConfidence: lowConfidence.contains(
                            'discountMinor',
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _fieldPair(
                        minFieldWidth: 148,
                        first: _MoneyField(
                          controller: _taxController,
                          label: 'Thuế',
                        ),
                        second: _MoneyField(
                          controller: _totalController,
                          label: 'Tổng thanh toán *',
                          requiredPositive: true,
                          lowConfidence: lowConfidence.contains('totalMinor'),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Phân loại',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      _fieldPair(
                        minFieldWidth: 148,
                        first: DropdownButtonFormField<String>(
                          initialValue: _categoryForDropdown(
                            _categoryId,
                            categories,
                          ),
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
                          onChanged: (value) {
                            setState(() => _categoryId = value);
                            _recomputeDirty();
                          },
                        ),
                        second: TextFormField(
                          controller: _tagsController,
                          decoration: const InputDecoration(
                            labelText: 'Nhãn',
                            hintText: 'Ví dụ: công việc',
                            helperText:
                                'Từ khóa để tìm/lọc; ngăn cách bằng dấu phẩy.',
                            prefixIcon: Icon(Icons.sell_outlined),
                          ),
                          textInputAction: TextInputAction.next,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _notesController,
                        decoration: const InputDecoration(
                          labelText: 'Ghi chú',
                          hintText: 'Thông tin cần nhớ về hóa đơn này',
                          prefixIcon: Icon(Icons.notes_outlined),
                          alignLabelWithHint: true,
                          helperText:
                              'Ghi chú riêng, hiển thị trong chi tiết hóa đơn.',
                        ),
                        minLines: 1,
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                      ),
                      const SizedBox(height: 24),
                      _buildLineItemsEditor(context, categories),
                    ],
                  ],
                ),
              ),
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
                  child: Text(_isManualExpense ? 'Hủy' : 'Để sau'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  key: const Key('confirm-invoice-button'),
                  onPressed: _saving ? null : _confirm,
                  icon: _saving
                      ? const ButtonSpinner()
                      : const Icon(Icons.check),
                  label: Text(
                    _saving
                        ? 'Đang lưu'
                        : _isManualExpense
                        ? widget.invoice.status == InvoiceStatus.confirmed
                              ? 'Cập nhật khoản chi'
                              : 'Lưu khoản chi'
                        : 'Xác nhận và lưu',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Liệt kê ĐÚNG những gì đang sai.
  ///
  /// Trước đây summary chỉ in hai câu hardcode về tên người bán và tổng tiền,
  /// nên bỏ trống mô tả một dòng hàng sẽ chặn nút Lưu mà không nói lý do.
  List<String> _collectFieldErrors() {
    final errors = <String>[];

    if (!_isManualExpense && _sellerController.text.trim().isEmpty) {
      errors.add('Hãy nhập tên người bán.');
    }

    final total = MoneyFormatter.tryParse(_totalController.text);
    if (total == null || total <= 0) {
      errors.add(
        _isManualExpense
            ? 'Số tiền phải lớn hơn 0.'
            : 'Tổng thanh toán phải lớn hơn 0.',
      );
    }
    if (_isManualExpense) return errors;
    if ((MoneyFormatter.tryParse(_subtotalController.text) ?? 0) < 0) {
      errors.add('Số tiền trước thuế không hợp lệ.');
    }
    if ((MoneyFormatter.tryParse(_taxController.text) ?? 0) < 0) {
      errors.add('Số tiền thuế không hợp lệ.');
    }
    if ((MoneyFormatter.tryParse(_discountController.text) ?? 0) < 0) {
      errors.add('Số tiền giảm giá không hợp lệ.');
    }

    for (var i = 0; i < _lineDrafts.length; i++) {
      final draft = _lineDrafts[i];
      final position = i + 1;
      if (draft.descriptionController.text.trim().isEmpty) {
        errors.add('Dòng hàng $position: hãy nhập mô tả.');
      }
      final lineTotal = MoneyFormatter.tryParse(draft.totalController.text);
      if (lineTotal == null || lineTotal < 0) {
        errors.add('Dòng hàng $position: thành tiền không hợp lệ.');
      }
      if (_validateOptionalDecimal(draft.quantityController.text) != null) {
        errors.add('Dòng hàng $position: số lượng không hợp lệ.');
      }
      if (_validateOptionalMoney(draft.unitPriceController.text) != null) {
        errors.add('Dòng hàng $position: đơn giá không hợp lệ.');
      }
    }

    if (errors.isEmpty) {
      errors.add('Có trường chưa hợp lệ. Hãy kiểm tra các ô được đánh dấu đỏ.');
    }
    return errors;
  }

  /// So khớp với bản gốc để biết người dùng đã sửa gì chưa.
  /// Mọi controller đang được theo dõi, để gắn/gỡ listener ở một chỗ.
  Iterable<TextEditingController> get _watchedControllers sync* {
    yield _sellerController;
    yield _subtotalController;
    yield _taxController;
    yield _discountController;
    yield _totalController;
    yield _notesController;
    yield _tagsController;
    for (final draft in _lineDrafts) {
      yield* _lineControllers(draft);
    }
  }

  Iterable<TextEditingController> _lineControllers(
    _InvoiceLineDraft draft,
  ) sync* {
    yield draft.descriptionController;
    yield draft.quantityController;
    yield draft.unitPriceController;
    yield draft.totalController;
  }

  /// `PopScope.canPop` được đọc lúc BUILD, mà gõ chữ vào `TextEditingController`
  /// không tự gây rebuild. Không có listener này thì cờ bẩn bị đóng băng ở giá
  /// trị của lần build gần nhất và người dùng mất bài mà không được hỏi.
  void _recomputeDirty() {
    final next = _computeDirty();
    if (next != _dirty && mounted) setState(() => _dirty = next);
  }

  bool _computeDirty() {
    final invoice = widget.invoice;
    // Các trường model là String? nhưng controller không bao giờ trả null.
    // So thẳng '' với null làm form LUÔN bẩn ngay khi mở, nên hộp thoại "bỏ
    // thay đổi?" bật lên kể cả khi người dùng chưa gõ gì.
    String norm(String? value) => value ?? '';

    if (_sellerController.text != norm(invoice.sellerName)) return true;
    if (_subtotalController.text != invoice.subtotalMinor.toString()) {
      return true;
    }
    if (_taxController.text != invoice.taxMinor.toString()) return true;
    if (_discountController.text != invoice.discountMinor.toString()) {
      return true;
    }
    if (_totalController.text != invoice.totalMinor.toString()) return true;
    if (_notesController.text != norm(invoice.notes)) return true;
    if (_tagsController.text != invoice.tags.join(', ')) return true;
    if (_issuedAt != invoice.issuedAt) return true;
    if (_categoryId != invoice.categoryId) return true;
    if (_lineDrafts.length != invoice.lines.length) return true;
    for (var i = 0; i < _lineDrafts.length; i++) {
      final draft = _lineDrafts[i];
      final line = invoice.lines[i];
      if (draft.descriptionController.text != norm(line.description)) {
        return true;
      }
      if (draft.quantityController.text != (line.quantity?.toString() ?? '')) {
        return true;
      }
      if (draft.unitPriceController.text !=
          (line.unitPriceMinor?.toString() ?? '')) {
        return true;
      }
      if (draft.totalController.text != line.totalMinor.toString()) return true;
      if (draft.categoryId != line.categoryId) return true;
    }
    return false;
  }

  Future<void> _confirmDiscard() async {
    final discard = await showConfirmDialog(
      context,
      title: 'Bỏ các thay đổi?',
      message:
          'Bạn đã sửa hóa đơn này nhưng chưa lưu. Thoát bây giờ sẽ mất các '
          'thay đổi đó.',
      confirmLabel: 'Bỏ thay đổi',
      cancelLabel: 'Tiếp tục sửa',
      destructive: true,
    );
    if (discard && mounted) Navigator.of(context).pop();
  }

  Future<void> _pickDate() async {
    final result = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDate: _issuedAt ?? DateTime.now(),
    );
    if (result != null) {
      setState(() => _issuedAt = result);
      _recomputeDirty();
    }
  }

  Future<void> _confirm() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() {
        _validationMessages = _collectFieldErrors();
        _validationTone = CalloutTone.danger;
        _autovalidate = AutovalidateMode.onUserInteraction;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _validationSummaryFocusNode.requestFocus();
      });
      return;
    }
    final now = DateTime.now();
    final total = MoneyFormatter.tryParse(_totalController.text) ?? 0;
    final subtotal = _isManualExpense
        ? total
        : MoneyFormatter.tryParse(_subtotalController.text) ?? 0;
    final tax = _isManualExpense
        ? 0
        : MoneyFormatter.tryParse(_taxController.text) ?? 0;
    final discount = _isManualExpense
        ? 0
        : MoneyFormatter.tryParse(_discountController.text) ?? 0;
    final sellerName = _sellerController.text.trim().isEmpty && _isManualExpense
        ? 'Khoản chi'
        : _sellerController.text.trim();
    final categories = ref.read(categoriesProvider).asData?.value ?? const [];
    final categoryId = _categoryForSave(_categoryId, categories);
    final lines = _lineDrafts
        .map((draft) => _toInvoiceLine(draft, categories))
        .toList(growable: false);
    final updated = widget.invoice.copyWith(
      sellerName: sellerName,
      issuedAt: _isManualExpense
          ? (_issuedAt ?? widget.invoice.createdAt)
          : _issuedAt,
      subtotalMinor: subtotal,
      taxMinor: tax,
      discountMinor: discount,
      totalMinor: total,
      lines: _isManualExpense ? const [] : lines,
      categoryId: categoryId,
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
        sellerName: sellerName,
        subtotal: subtotal,
        tax: tax,
        discount: discount,
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
      if (!_isManualExpense &&
          _categoryId != null &&
          categories.any((item) => item.id == _categoryId)) {
        await repository.saveMerchantRule(updated.sellerName, _categoryId!);
      }
      if (mounted) context.pop(true);
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

  Widget _buildDateField() {
    final isManualExpense = _isManualExpense;
    final date =
        _issuedAt ?? (isManualExpense ? widget.invoice.createdAt : null);
    return Semantics(
      button: true,
      label: date == null
          ? isManualExpense
                ? 'Chọn ngày chi'
                : 'Chọn ngày lập hóa đơn'
          : '${isManualExpense ? 'Ngày chi' : 'Ngày lập'} ${DateFormat('dd/MM/yyyy').format(date)}',
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        leading: const Icon(Icons.calendar_today_outlined),
        title: Text(isManualExpense ? 'Ngày chi' : 'Ngày lập hóa đơn'),
        subtitle: Text(
          date == null
              ? 'Chưa xác định'
              : DateFormat('dd/MM/yyyy').format(date),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _pickDate,
      ),
    );
  }

  List<FieldEvidenceEntity> _updatedEvidence({
    required String sellerName,
    required int subtotal,
    required int tax,
    required int discount,
    required int total,
  }) {
    final values = <String, String>{
      'sellerName': sellerName,
      'subtotalMinor': subtotal.toString(),
      'taxMinor': tax.toString(),
      'discountMinor': discount.toString(),
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

  Widget _fieldPair({
    required Widget first,
    required Widget second,
    required double minFieldWidth,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < minFieldWidth * 2 + 12) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 10), second],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }

  Widget _buildLineItemsEditor(
    BuildContext context,
    List<CategoryEntity> categories,
  ) {
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
            child: _buildLineCard(context, index, categories),
          ),
        OutlinedButton.icon(
          onPressed: _addLine,
          icon: const Icon(Icons.add),
          label: const Text('Thêm dòng hàng hóa'),
        ),
      ],
    );
  }

  Widget _buildLineCard(
    BuildContext context,
    int index,
    List<CategoryEntity> categories,
  ) {
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
            const SizedBox(height: 10),
            _fieldPair(
              minFieldWidth: 130,
              first: _MoneyField(
                controller: draft.totalController,
                label: 'Thành tiền *',
              ),
              second: DropdownButtonFormField<String>(
                initialValue: _categoryForDropdown(
                  draft.categoryId,
                  categories,
                ),
                decoration: const InputDecoration(
                  labelText: 'Danh mục chi tiêu',
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
                onChanged: (value) {
                  setState(() => draft.categoryId = value);
                  _recomputeDirty();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addLine() {
    final draft = _InvoiceLineDraft.empty();
    // Draft mới cũng phải theo dõi được, nếu không thì sửa dòng vừa thêm sẽ
    // không tính là bẩn.
    for (final controller in _lineControllers(draft)) {
      controller.addListener(_recomputeDirty);
    }
    setState(() => _lineDrafts.add(draft));
    _recomputeDirty();
  }

  Future<void> _removeLine(int index) async {
    final description = _lineDrafts[index].descriptionController.text.trim();
    final confirmed = await showConfirmDialog(
      context,
      title: 'Xóa dòng hàng?',
      message:
          '“${description.isEmpty ? 'Dòng hàng này' : description}” sẽ bị '
          'xóa khỏi hóa đơn đang chỉnh sửa.',
      confirmLabel: 'Xóa dòng',
      destructive: true,
    );
    if (!confirmed || !mounted || index >= _lineDrafts.length) return;
    final draft = _lineDrafts.removeAt(index);
    for (final controller in _lineControllers(draft)) {
      controller.removeListener(_recomputeDirty);
    }
    draft.dispose();
    setState(() {});
    _recomputeDirty();
  }

  InvoiceLineEntity _toInvoiceLine(
    _InvoiceLineDraft draft,
    List<CategoryEntity> categories,
  ) {
    return InvoiceLineEntity(
      id: draft.id,
      description: draft.descriptionController.text.trim(),
      quantity: _parseDecimal(draft.quantityController.text),
      unitPriceMinor: MoneyFormatter.tryParse(draft.unitPriceController.text),
      totalMinor: MoneyFormatter.tryParse(draft.totalController.text) ?? 0,
      categoryId: _categoryForSave(draft.categoryId, categories),
    );
  }

  String? _categoryForDropdown(
    String? candidate,
    List<CategoryEntity> categories,
  ) {
    if (categories.any((item) => item.id == candidate)) return candidate;
    if (categories.any((item) => item.id == 'other')) return 'other';
    return null;
  }

  String? _categoryForSave(String? candidate, List<CategoryEntity> categories) {
    if (categories.isEmpty) return 'other';
    return _categoryForDropdown(candidate, categories);
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
    String? total,
    String? categoryId,
  }) : descriptionController = TextEditingController(text: description),
       quantityController = TextEditingController(text: quantity),
       unitPriceController = TextEditingController(text: unitPrice),
       totalController = TextEditingController(text: total),
       categoryId = categoryId;

  factory _InvoiceLineDraft.empty() =>
      _InvoiceLineDraft(id: 'line-${const Uuid().v4()}', total: '0');

  factory _InvoiceLineDraft.fromEntity(InvoiceLineEntity line) =>
      _InvoiceLineDraft(
        id: line.id,
        description: line.description,
        quantity: line.quantity?.toString(),
        unitPrice: line.unitPriceMinor?.toString(),
        total: line.totalMinor.toString(),
        categoryId: line.categoryId,
      );

  final String id;
  final TextEditingController descriptionController;
  final TextEditingController quantityController;
  final TextEditingController unitPriceController;
  final TextEditingController totalController;
  String? categoryId;

  void dispose() {
    descriptionController.dispose();
    quantityController.dispose();
    unitPriceController.dispose();
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
        suffixText: '₫',
        helperText: lowConfidence
            ? 'Độ tin cậy thấp — vui lòng kiểm tra'
            : null,
      ),
      validator: (value) {
        final parsed = MoneyFormatter.tryParse(value ?? '');
        if (parsed == null || parsed < 0) return 'Số tiền không hợp lệ.';
        if (requiredPositive && parsed <= 0) return 'Số tiền phải lớn hơn 0.';
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
