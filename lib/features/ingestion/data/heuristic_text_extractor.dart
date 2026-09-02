import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../../invoices/domain/invoice_models.dart';
import '../domain/extraction.dart';
import '../domain/invoice_validator.dart';
import '../domain/source_hasher.dart';

class HeuristicTextExtractor implements InvoiceExtractor {
  HeuristicTextExtractor({Uuid? uuid, InvoiceValidator? validator})
    : _uuid = uuid ?? const Uuid(),
      _validator = validator ?? const InvoiceValidator();

  final Uuid _uuid;
  final InvoiceValidator _validator;

  @override
  String get adapterName => 'offline-text-fallback';

  @override
  String get adapterVersion => '1.0.0';

  @override
  bool canHandle(ExtractionInput input) =>
      input.ocrText?.trim().isNotEmpty ?? false;

  @override
  Future<ExtractionResult> extract(ExtractionInput input) async {
    final text = input.ocrText?.trim();
    if (text == null || text.isEmpty) {
      throw const ExtractionException('OCR không nhận diện được nội dung.');
    }
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final total = _findTotal(text);
    final now = DateTime.now();
    final id = _uuid.v4();
    final invoice = InvoiceEntity(
      id: id,
      sellerName: lines.isEmpty ? '' : lines.first,
      invoiceNumber: _match(
        text,
        RegExp(
          r'(?:số|so|invoice\s*(?:no|number))\s*[:#]?\s*([A-Z0-9/-]+)',
          caseSensitive: false,
        ),
      ),
      issuedAt: _findDate(text),
      currencyCode: AppConstants.defaultCurrency,
      subtotalMinor: total,
      taxMinor: 0,
      totalMinor: total,
      sourceType: input.sourceType,
      sourceHash: input.bytes.isEmpty
          ? null
          : SourceHasher.sha256Of(input.bytes),
      status: InvoiceStatus.needsReview,
      createdAt: now,
      updatedAt: now,
      evidence: [
        FieldEvidenceEntity(
          id: '$id-seller',
          fieldName: 'sellerName',
          rawValue: lines.isEmpty ? null : lines.first,
          normalizedValue: lines.isEmpty ? '' : lines.first,
          source: input.sourceType,
          confidence: lines.isEmpty ? 0 : 0.6,
        ),
        FieldEvidenceEntity(
          id: '$id-total',
          fieldName: 'totalMinor',
          rawValue: total.toString(),
          normalizedValue: total.toString(),
          source: input.sourceType,
          confidence: total > 0 ? 0.7 : 0,
        ),
      ],
    );
    final validation = _validator.validate(invoice);
    return ExtractionResult(
      invoice: invoice,
      adapterName: adapterName,
      adapterVersion: adapterVersion,
      warnings: [
        'Đang dùng bộ trích xuất offline; hãy kiểm tra lại dữ liệu.',
        ...validation.errors,
        ...validation.warnings,
      ],
    );
  }

  int _findTotal(String text) {
    final expression = RegExp(
      r'(?:tổng\s*(?:cộng|tiền|thanh\s*toán)?|total|amount)\s*[: ]+([0-9][0-9., ]*)',
      caseSensitive: false,
    );
    final raw = _match(text, expression);
    if (raw == null) return 0;
    return int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  DateTime? _findDate(String text) {
    final raw = _match(text, RegExp(r'\b(\d{1,2}[/-]\d{1,2}[/-]\d{4})\b'));
    if (raw == null) return null;
    final parts = raw.split(RegExp(r'[/.-]'));
    return DateTime(
      int.parse(parts[2]),
      int.parse(parts[1]),
      int.parse(parts[0]),
    );
  }

  String? _match(String text, RegExp expression) =>
      expression.firstMatch(text)?.group(1)?.trim();
}
