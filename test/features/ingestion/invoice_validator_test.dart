import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/ingestion/domain/invoice_validator.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  const validator = InvoiceValidator();
  final now = DateTime(2026, 8, 20);

  InvoiceEntity invoice({
    String seller = 'Demo',
    int subtotal = 100000,
    int tax = 10000,
    int discount = 0,
    int total = 110000,
  }) {
    return InvoiceEntity(
      id: 'invoice-1',
      sellerName: seller,
      issuedAt: now,
      currencyCode: 'VND',
      subtotalMinor: subtotal,
      taxMinor: tax,
      discountMinor: discount,
      totalMinor: total,
      sourceType: InvoiceSourceType.xml,
      status: InvoiceStatus.validating,
      createdAt: now,
      updatedAt: now,
    );
  }

  test('accepts internally consistent invoice', () {
    final result = validator.validate(invoice());
    expect(result.isValid, isTrue);
    expect(result.warnings, isEmpty);
  });

  test('requires review when totals do not reconcile', () {
    final result = validator.validate(invoice(total: 90000));
    expect(result.isValid, isTrue);
    expect(result.requiresReview, isTrue);
    expect(result.warnings, isNotEmpty);
  });

  test('accounts for invoice discount when comparing totals', () {
    final result = validator.validate(invoice(discount: 10000, total: 100000));
    expect(result.isValid, isTrue);
    expect(result.warnings, isEmpty);
  });

  test('rejects a negative invoice discount', () {
    final result = validator.validate(invoice(discount: -1));
    expect(result.isValid, isFalse);
    expect(result.errors, contains('Số tiền giảm giá không hợp lệ.'));
  });

  test('rejects empty seller and non-positive total', () {
    final result = validator.validate(invoice(seller: '', total: 0));
    expect(result.isValid, isFalse);
    expect(result.errors, hasLength(2));
  });

  test('warns when line items do not reconcile with subtotal', () {
    final result = validator.validate(
      invoice().copyWith(
        lines: const [
          InvoiceLineEntity(
            id: 'line-1',
            description: 'Item',
            totalMinor: 90000,
          ),
        ],
      ),
    );

    expect(result.isValid, isTrue);
    expect(
      result.warnings,
      contains('Tổng các dòng hàng chưa khớp với tiền trước thuế.'),
    );
  });

  test('warns when the invoice date is in the future', () {
    final result = validator.validate(
      invoice().copyWith(issuedAt: DateTime.now().add(const Duration(days: 2))),
    );
    expect(result.warnings, contains('Ngày lập hóa đơn nằm trong tương lai.'));
  });

  group('applyRuleConfidence', () {
    const evidence = [
      FieldEvidenceEntity(
        id: 'e-seller',
        fieldName: 'sellerName',
        normalizedValue: 'Demo',
        source: InvoiceSourceType.imageOcr,
        confidence: 0.75,
      ),
      FieldEvidenceEntity(
        id: 'e-total',
        fieldName: 'totalMinor',
        normalizedValue: '110000',
        source: InvoiceSourceType.imageOcr,
        confidence: 0.75,
      ),
    ];

    double totalConfidence(InvoiceEntity value) => value.evidence
        .singleWhere((item) => item.fieldName == 'totalMinor')
        .confidence;

    test('keeps confidence when totals reconcile', () {
      final result = validator.applyRuleConfidence(
        invoice().copyWith(
          evidence: evidence,
          lines: const [
            InvoiceLineEntity(id: 'l1', description: 'A', totalMinor: 60000),
            InvoiceLineEntity(id: 'l2', description: 'B', totalMinor: 40000),
          ],
        ),
      );
      expect(totalConfidence(result), 0.75);
    });

    test('downgrades total when subtotal + tax does not match total', () {
      final result = validator.applyRuleConfidence(
        invoice(total: 90000).copyWith(evidence: evidence),
      );
      expect(totalConfidence(result), InvoiceValidator.ruleFailedConfidence);
      expect(
        result.evidence
            .singleWhere((item) => item.fieldName == 'sellerName')
            .confidence,
        0.75,
      );
    });

    test('downgrades total when line items do not sum to total', () {
      final result = validator.applyRuleConfidence(
        invoice(subtotal: 0, tax: 0, total: 110000).copyWith(
          evidence: evidence,
          lines: const [
            InvoiceLineEntity(id: 'l1', description: 'A', totalMinor: 50000),
          ],
        ),
      );
      expect(totalConfidence(result), InvoiceValidator.ruleFailedConfidence);
    });
  });
}
