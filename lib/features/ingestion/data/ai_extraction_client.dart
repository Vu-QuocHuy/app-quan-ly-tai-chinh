import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/supabase_function_client.dart';
import '../../invoices/domain/invoice_models.dart';
import '../domain/extraction.dart';
import '../domain/invoice_validator.dart';
import '../domain/source_hasher.dart';

class TransactionDraftResult {
  const TransactionDraftResult({
    required this.isTransaction,
    required this.type,
    required this.amountMinor,
    required this.date,
    required this.description,
    required this.categoryId,
    required this.clarification,
  });

  final bool isTransaction;
  final String type;
  final int? amountMinor;
  final DateTime? date;
  final String description;
  final String? categoryId;
  final String clarification;

  bool get isReady =>
      isTransaction &&
      (type == 'income' || type == 'expense') &&
      amountMinor != null;

  Map<String, Object?> toJson() => {
    'type': type,
    'amountMinor': amountMinor,
    'date': date == null ? null : _dateOnly(date!),
    'description': description,
    'categoryId': categoryId,
  };
}

class AiExtractionClient implements InvoiceExtractor {
  static const _maxSafeInteger = 9007199254740991;
  static const _maxItems = 200;
  static const _maxEvidence = 200;
  static const _supportedCurrencies = {'VND', 'USD', 'EUR', 'JPY', 'CNY'};
  static const _supportedCategories = {
    'food',
    'transport',
    'shopping',
    'utilities',
    'health',
    'education',
    'entertainment',
    'other',
  };

  AiExtractionClient({
    SupabaseClient? supabaseClient,
    Uuid? uuid,
    InvoiceValidator? validator,
    this.enabled = true,
    this.locale = 'vi-VN',
  }) : _supabaseFunctions = supabaseClient == null
           ? null
           : SupabaseFunctionClient(client: supabaseClient),
       _uuid = uuid ?? const Uuid(),
       _validator = validator ?? const InvoiceValidator();

  final SupabaseFunctionClient? _supabaseFunctions;
  final Uuid _uuid;
  final InvoiceValidator _validator;
  final bool enabled;
  final String locale;

  bool get isConfigured => enabled && _supabaseFunctions?.isConfigured == true;

  @override
  String get adapterName => 'backend-ai-structured-output';

  @override
  String get adapterVersion => 'v1';

  @override
  bool canHandle(ExtractionInput input) =>
      isConfigured && (input.ocrText?.trim().isNotEmpty ?? false);

  @override
  Future<ExtractionResult> extract(ExtractionInput input) async {
    if (!isConfigured) {
      throw const NetworkException('Backend AI chưa được cấu hình.');
    }
    final body = {
      'action': 'extract',
      'requestId': _uuid.v4(),
      'locale': locale,
      'text': input.ocrText,
    };
    final data = await _supabaseFunctions!.invoke(
      body,
      errorMessage:
          'Không thể kết nối dịch vụ trích xuất. Dữ liệu OCR vẫn được giữ để thử lại.',
    );
    return parseResponse(data, input);
  }

  Future<String?> classifyMerchant(String merchant) async {
    if (!isConfigured || merchant.trim().isEmpty) return null;
    final body = {
      'action': 'classify',
      'requestId': _uuid.v4(),
      'locale': locale,
      'merchant': merchant.trim(),
    };
    final data = await _supabaseFunctions!.invoke(
      body,
      errorMessage: 'Không thể phân loại merchant từ backend.',
    );
    final categoryId = data['categoryId'];
    return categoryId is String && _supportedCategories.contains(categoryId)
        ? categoryId
        : null;
  }

  Future<TransactionDraftResult> draftTransaction(
    String text, {
    required DateTime today,
    required List<CategoryEntity> categories,
    TransactionDraftResult? previous,
  }) async {
    if (!isConfigured) {
      throw const NetworkException('AI tạo giao dịch chưa được cấu hình.');
    }
    if (text.trim().isEmpty || text.length > 3_000 || categories.length > 100) {
      throw const FormatException('Mô tả giao dịch không hợp lệ.');
    }
    final data = await _supabaseFunctions!.invoke({
      'action': 'draft_transaction',
      'requestId': _uuid.v4(),
      'locale': locale,
      'text': text.trim(),
      'today': _dateOnly(today),
      'categories': categories
          .map(
            (category) => {
              'id': category.id,
              'name': category.name,
              'kind': category.kind.name,
            },
          )
          .toList(growable: false),
      if (previous != null) 'previousDraft': previous.toJson(),
    }, errorMessage: 'Không thể phân tích giao dịch. Bản nháp chưa được lưu.');
    final isTransaction = data['isTransaction'];
    final type = data['type'];
    final amount = data['amountMinor'];
    final dateValue = data['date'];
    final description = data['description'];
    final categoryId = data['categoryId'];
    final clarification = data['clarification'];
    if (isTransaction is! bool ||
        type is! String ||
        !{'income', 'expense', 'unclear'}.contains(type) ||
        (amount != null &&
            (amount is! int || amount < 1 || amount > _maxSafeInteger)) ||
        (dateValue != null && dateValue is! String) ||
        description is! String ||
        description.length > 300 ||
        (categoryId != null && categoryId is! String) ||
        clarification is! String ||
        clarification.length > 300) {
      throw const FormatException('AI trả về bản nháp giao dịch không hợp lệ.');
    }
    final date = dateValue == null ? null : _parseDateOnly(dateValue as String);
    if (dateValue != null && date == null) {
      throw const FormatException('Ngày giao dịch AI trả về không hợp lệ.');
    }
    final validCategory =
        categoryId is String &&
        categories.any(
          (category) =>
              category.id == categoryId &&
              ((type == 'income' && category.kind == CategoryKind.income) ||
                  (type == 'expense' && category.kind == CategoryKind.expense)),
        );
    return TransactionDraftResult(
      isTransaction: isTransaction,
      type: type,
      amountMinor: amount,
      date: date,
      description: description.trim(),
      categoryId: validCategory ? categoryId : null,
      clarification: clarification.trim(),
    );
  }

  Future<ExtractionResult> extractImage(ExtractionInput input) async {
    if (!isConfigured) {
      throw const NetworkException('Backend AI chưa được cấu hình.');
    }
    final body = {
      'action': 'extract',
      'requestId': _uuid.v4(),
      'locale': locale,
      'imageBase64': base64Encode(input.bytes),
      'mimeType': _mimeType(input.fileName),
    };
    final data = await _supabaseFunctions!.invoke(
      body,
      errorMessage:
          'Không thể kết nối dịch vụ phân tích ảnh. Vui lòng thử lại sau.',
    );
    return parseResponse(data, input);
  }

  String _mimeType(String fileName) {
    return switch (fileName.toLowerCase().split('.').last) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
  }

  ExtractionResult parseResponse(
    Map<String, dynamic> json,
    ExtractionInput input,
  ) {
    final now = DateTime.now();
    final id = _uuid.v4();
    final invoiceJson = _object(json['invoice'] ?? json, 'invoice');
    final items = _list(invoiceJson['items'], 'invoice.items');
    if (items.length > _maxItems) {
      throw const ExtractionException('Backend trả quá nhiều dòng hàng hóa.');
    }
    final evidence = _list(json['evidence'], 'evidence');
    if (evidence.length > _maxEvidence) {
      throw const ExtractionException(
        'Backend trả quá nhiều bằng chứng dữ liệu.',
      );
    }
    final invoice = InvoiceEntity(
      id: id,
      sellerName: _requiredString(invoiceJson['sellerName'], 'sellerName', 500),
      invoiceSymbol: _optionalString(
        invoiceJson['invoiceSymbol'],
        'invoiceSymbol',
        300,
      ),
      issuedAt: _optionalDate(invoiceJson['invoiceDate'], 'invoiceDate'),
      currencyCode: _enumString(
        invoiceJson['currencyCode'],
        'currencyCode',
        _supportedCurrencies,
      ),
      subtotalMinor: _requiredMoney(
        invoiceJson['subtotalMinor'],
        'subtotalMinor',
      ),
      taxMinor: _requiredMoney(invoiceJson['taxMinor'], 'taxMinor'),
      discountMinor: invoiceJson['discountMinor'] == null
          ? 0
          : _requiredMoney(invoiceJson['discountMinor'], 'discountMinor'),
      totalMinor: _requiredMoney(invoiceJson['totalMinor'], 'totalMinor'),
      sourceType: input.sourceType,
      sourceHash: input.bytes.isEmpty
          ? null
          : SourceHasher.sha256Of(input.bytes),
      status: InvoiceStatus.needsReview,
      categoryId: _categoryId(invoiceJson['categoryId']),
      createdAt: now,
      updatedAt: now,
      lines: [
        for (var index = 0; index < items.length; index++)
          _lineFromJson(items[index], input, index),
      ],
      evidence: [
        for (var index = 0; index < evidence.length; index++)
          _evidenceFromJson(evidence[index], input, index),
      ],
    );
    final validation = _validator.validate(invoice);
    return ExtractionResult(
      invoice: invoice,
      adapterName: adapterName,
      adapterVersion: adapterVersion,
      warnings: [...validation.errors, ...validation.warnings],
    );
  }

  InvoiceLineEntity _lineFromJson(
    Object? value,
    ExtractionInput input,
    int index,
  ) {
    final item = _object(value, 'items[$index]');
    return InvoiceLineEntity(
      id: _uuid.v4(),
      description: _requiredString(
        item['description'],
        'items[$index].description',
        500,
      ),
      quantity: _optionalNonNegativeDouble(
        item['quantity'],
        'items[$index].quantity',
      ),
      unitPriceMinor: _optionalMoney(
        item['unitPriceMinor'],
        'items[$index].unitPriceMinor',
      ),
      totalMinor: _requiredMoney(
        item['totalMinor'],
        'items[$index].totalMinor',
      ),
      categoryId: _categoryId(item['categoryId']),
    );
  }

  FieldEvidenceEntity _evidenceFromJson(
    Object? value,
    ExtractionInput input,
    int index,
  ) {
    final item = _object(value, 'evidence[$index]');
    return FieldEvidenceEntity(
      id: _uuid.v4(),
      fieldName: _requiredString(item['field'], 'evidence[$index].field', 64),
      rawValue: _optionalString(
        item['rawValue'],
        'evidence[$index].rawValue',
        5000,
      ),
      normalizedValue: _requiredString(
        item['value'],
        'evidence[$index].value',
        5000,
      ),
      source: input.sourceType,
      confidence: _confidence(
        item['confidence'],
        'evidence[$index].confidence',
      ),
    );
  }

  Map<String, dynamic> _object(Object? value, String field) {
    if (value is! Map || value.keys.any((key) => key is! String)) {
      throw ExtractionException('$field không hợp lệ.');
    }
    return Map<String, dynamic>.from(value);
  }

  List<Object?> _list(Object? value, String field) {
    if (value == null) return const [];
    if (value is! List) throw ExtractionException('$field không hợp lệ.');
    return value;
  }

  String _requiredString(Object? value, String field, int maxLength) {
    if (value is! String || value.trim().isEmpty || value.length > maxLength) {
      throw ExtractionException('$field không hợp lệ.');
    }
    return value.trim();
  }

  String? _optionalString(Object? value, String field, int maxLength) {
    if (value == null) return null;
    if (value is! String || value.length > maxLength) {
      throw ExtractionException('$field không hợp lệ.');
    }
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  String _enumString(Object? value, String field, Set<String> allowed) {
    final normalized = _requiredString(value, field, 32);
    if (!allowed.contains(normalized)) {
      throw ExtractionException('$field không được hỗ trợ.');
    }
    return normalized;
  }

  String _categoryId(Object? value) {
    if (value is! String) return 'other';
    final normalized = value.trim().toLowerCase();
    return _supportedCategories.contains(normalized) ? normalized : 'other';
  }

  int _requiredMoney(Object? value, String field) {
    final parsed = _optionalMoney(value, field);
    if (parsed == null) throw ExtractionException('$field không hợp lệ.');
    return parsed;
  }

  int? _optionalMoney(Object? value, String field) {
    if (value == null) return null;
    if (value is! num ||
        !value.toDouble().isFinite ||
        value != value.truncate()) {
      throw ExtractionException('$field không hợp lệ.');
    }
    if (value < 0 || value > _maxSafeInteger) {
      throw ExtractionException('$field không hợp lệ.');
    }
    return value.toInt();
  }

  double? _optionalNonNegativeDouble(Object? value, String field) {
    if (value == null) return null;
    if (value is! num || !value.toDouble().isFinite || value < 0) {
      throw ExtractionException('$field không hợp lệ.');
    }
    return value.toDouble();
  }

  double _confidence(Object? value, String field) {
    if (value is! num || !value.toDouble().isFinite) {
      throw ExtractionException('$field không hợp lệ.');
    }
    final confidence = value.toDouble();
    if (confidence < 0 || confidence > 1) {
      throw ExtractionException('$field không hợp lệ.');
    }
    return confidence;
  }

  DateTime? _optionalDate(Object? value, String field) {
    if (value == null) return null;
    if (value is! String) throw ExtractionException('$field không hợp lệ.');
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw ExtractionException('$field không hợp lệ.');
    return parsed;
  }
}

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

DateTime? _parseDateOnly(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
  final date = DateTime.tryParse(value);
  if (date == null || _dateOnly(date) != value) return null;
  return DateTime(date.year, date.month, date.day);
}
