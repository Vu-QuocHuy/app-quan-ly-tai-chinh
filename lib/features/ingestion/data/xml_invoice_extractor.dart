import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/string_normalizer.dart';
import '../../invoices/domain/invoice_models.dart';
import '../domain/extraction.dart';
import '../domain/invoice_validator.dart';
import '../domain/source_hasher.dart';

class XmlInvoiceExtractor implements InvoiceExtractor {
  XmlInvoiceExtractor({Uuid? uuid, InvoiceValidator? validator})
    : _uuid = uuid ?? const Uuid(),
      _validator = validator ?? const InvoiceValidator();

  final Uuid _uuid;
  final InvoiceValidator _validator;

  @override
  String get adapterName => 'vietnam-einvoice-xml';

  @override
  String get adapterVersion => '1.0.0';

  @override
  bool canHandle(ExtractionInput input) =>
      input.fileName.toLowerCase().endsWith('.xml') ||
      utf8.decode(input.bytes, allowMalformed: true).trimLeft().startsWith('<');

  @override
  Future<ExtractionResult> extract(ExtractionInput input) async {
    try {
      final xmlText = utf8.decode(input.bytes);
      if (RegExp(
        r'<!\s*(?:DOCTYPE|ENTITY)',
        caseSensitive: false,
      ).hasMatch(xmlText)) {
        throw const ExtractionException(
          'XML chứa khai báo DTD/entity không được hỗ trợ.',
        );
      }
      final document = XmlDocument.parse(xmlText);
      final now = DateTime.now();
      final id = _uuid.v4();
      final seller = _sellerElement(document);
      final general = _firstElement(document, const ['TTChung', 'GeneralInfo']);
      final totals = _firstElement(document, const [
        'TToan',
        'Summary',
        'Totals',
      ]);
      final sellerName =
          _valueWithin(seller, const [
            'Ten',
            'TenNBan',
            'Name',
            'SellerName',
          ]) ??
          _value(document, const ['TenNBan', 'SellerName']) ??
          '';
      final subtotal = _money(
        _valueWithin(totals, const [
              'TgTCThue',
              'TgTThue',
              'Subtotal',
              'TotalBeforeTax',
            ]) ??
            _value(document, const ['TgTCThue', 'Subtotal']),
      );
      final tax = _money(
        _valueWithin(totals, const ['TgTThue', 'TaxAmount', 'TotalTax']) ??
            _value(document, const ['TgTThue', 'TaxAmount']),
      );
      final total = _money(
        _valueWithin(totals, const [
              'TgTTTBSo',
              'TgTTTToan',
              'TotalAmount',
              'GrandTotal',
            ]) ??
            _value(document, const ['TgTTTBSo', 'TotalAmount']),
      );
      final source = InvoiceSourceType.xml;
      final lines = _lineElements(document)
          .map((element) {
            return InvoiceLineEntity(
              id: _uuid.v4(),
              description:
                  _valueWithin(element, const [
                    'THHDVu',
                    'Ten',
                    'Description',
                    'ItemName',
                  ]) ??
                  'Hàng hóa/dịch vụ',
              quantity: _decimal(
                _valueWithin(element, const ['SLuong', 'Quantity']),
              ),
              unitPriceMinor: _nullableMoney(
                _valueWithin(element, const ['DGia', 'UnitPrice']),
              ),
              taxRate: _taxRate(
                _valueWithin(element, const ['TSuat', 'TaxRate']),
              ),
              totalMinor: _money(
                _valueWithin(element, const ['ThTien', 'Amount', 'LineTotal']),
              ),
            );
          })
          .toList(growable: false);
      final invoice = InvoiceEntity(
        id: id,
        sellerName: StringNormalizer.compact(sellerName),
        sellerTaxCode:
            _valueWithin(seller, const [
              'MST',
              'MSTNBan',
              'TaxCode',
              'SellerTaxCode',
            ]) ??
            _value(document, const ['MSTNBan', 'SellerTaxCode']),
        invoiceNumber: _valueWithin(general, const [
          'SHDon',
          'InvoiceNumber',
          'No',
        ]),
        invoiceSymbol: _valueWithin(general, const [
          'KHHDon',
          'InvoiceSymbol',
          'Serial',
        ]),
        issuedAt: _date(
          _valueWithin(general, const ['NLap', 'IssuedDate', 'InvoiceDate']),
        ),
        currencyCode:
            _valueWithin(general, const [
              'DVTTe',
              'Currency',
              'CurrencyCode',
            ]) ??
            AppConstants.defaultCurrency,
        subtotalMinor: subtotal,
        taxMinor: tax,
        totalMinor: total,
        sourceType: source,
        sourceHash: SourceHasher.sha256Of(input.bytes),
        status: InvoiceStatus.validating,
        createdAt: now,
        updatedAt: now,
        lines: lines,
        evidence: _evidence(id, source, sellerName: sellerName, total: total),
      );
      final validation = _validator.validate(invoice);
      return ExtractionResult(
        invoice: invoice.copyWith(
          status: validation.requiresReview
              ? InvoiceStatus.needsReview
              : InvoiceStatus.confirmed,
          confirmedAt: validation.requiresReview ? null : now,
        ),
        adapterName: adapterName,
        adapterVersion: adapterVersion,
        warnings: [...validation.errors, ...validation.warnings],
      );
    } on XmlParserException catch (error) {
      throw ExtractionException('File XML không hợp lệ.', cause: error);
    } on FormatException catch (error) {
      throw ExtractionException(
        'Không thể đọc encoding của file XML.',
        cause: error,
      );
    }
  }

  XmlElement? _sellerElement(XmlDocument document) =>
      _firstElement(document, const ['NBan', 'Seller', 'SellerInfo']);

  XmlElement? _firstElement(XmlDocument document, List<String> names) {
    for (final element in document.descendants.whereType<XmlElement>()) {
      if (names.contains(element.name.local)) return element;
    }
    return null;
  }

  String? _value(XmlDocument document, List<String> names) {
    return _valueWithin(document.rootElement, names);
  }

  String? _valueWithin(XmlElement? root, List<String> names) {
    if (root == null) return null;
    for (final element in root.descendants.whereType<XmlElement>()) {
      if (names.contains(element.name.local)) {
        final value = element.innerText.trim();
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  Iterable<XmlElement> _lineElements(XmlDocument document) {
    const names = {'HHDVu', 'LineItem', 'InvoiceItem'};
    return document.descendants.whereType<XmlElement>().where(
      (element) => names.contains(element.name.local),
    );
  }

  List<FieldEvidenceEntity> _evidence(
    String invoiceId,
    InvoiceSourceType source, {
    required String sellerName,
    required int total,
  }) {
    return [
      FieldEvidenceEntity(
        id: '$invoiceId-seller',
        fieldName: 'sellerName',
        rawValue: sellerName,
        normalizedValue: StringNormalizer.compact(sellerName),
        source: source,
        confidence: sellerName.isEmpty ? 0 : 0.99,
      ),
      FieldEvidenceEntity(
        id: '$invoiceId-total',
        fieldName: 'totalMinor',
        rawValue: total.toString(),
        normalizedValue: total.toString(),
        source: source,
        confidence: total > 0 ? 0.99 : 0,
      ),
    ];
  }

  int _money(String? value) => _nullableMoney(value) ?? 0;

  int? _nullableMoney(String? value) {
    if (value == null) return null;
    final normalized = value
        .replaceAll(RegExp(r'\s'), '')
        .replaceAll(',', '')
        .replaceAll(RegExp(r'[^0-9.-]'), '');
    return double.tryParse(normalized)?.round();
  }

  double? _decimal(String? value) {
    if (value == null) return null;
    return double.tryParse(value.replaceAll(',', '.'));
  }

  double? _taxRate(String? value) {
    if (value == null) return null;
    return double.tryParse(value.replaceAll('%', '').replaceAll(',', '.'));
  }

  DateTime? _date(String? value) {
    if (value == null) return null;
    final iso = DateTime.tryParse(value);
    if (iso != null) return iso;
    final parts = value.split(RegExp(r'[/.-]'));
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }
}
