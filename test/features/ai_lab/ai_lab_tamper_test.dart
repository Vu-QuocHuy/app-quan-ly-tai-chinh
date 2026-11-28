import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/ai_lab/application/ai_lab_tamper.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

InvoiceEntity _invoice(int total) {
  final now = DateTime(2026, 9, 17);
  return InvoiceEntity(
    id: 'inv',
    sellerName: 'Siêu thị Demo',
    currencyCode: 'VND',
    subtotalMinor: total,
    taxMinor: 0,
    totalMinor: total,
    sourceType: InvoiceSourceType.imageOcr,
    status: InvoiceStatus.needsReview,
    createdAt: now,
    updatedAt: now,
    evidence: [
      FieldEvidenceEntity(
        id: 'e',
        fieldName: 'totalMinor',
        normalizedValue: '$total',
        source: InvoiceSourceType.imageOcr,
        confidence: 0.75,
      ),
    ],
  );
}

void main() {
  test('raises the total by 10% and keeps every other field', () {
    final original = _invoice(125000);
    final tampered = tamperInvoiceTotal(original);
    expect(tampered.totalMinor, 137500);
    expect(tampered.subtotalMinor, 125000);
    expect(tampered.sellerName, original.sellerName);
    expect(tampered.evidence.single.confidence, 0.75);
    expect(tampered.evidence.single.normalizedValue, '125000');
  });

  test('rounds to whole dong', () {
    expect(tamperInvoiceTotal(_invoice(12345)).totalMinor, 13580);
    expect(tamperInvoiceTotal(_invoice(1005)).totalMinor, 1106);
  });

  test('raises by at least 1 for tiny totals', () {
    expect(tamperInvoiceTotal(_invoice(4)).totalMinor, 5);
    expect(tamperInvoiceTotal(_invoice(0)).totalMinor, 1);
  });
}
