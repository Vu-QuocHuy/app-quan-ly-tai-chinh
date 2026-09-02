import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/ingestion/domain/duplicate_detector.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  const detector = DuplicateDetector();
  final date = DateTime(2026, 8, 20);

  InvoiceEntity invoice({
    required String id,
    String? hash,
    String number = '001',
    int total = 110000,
  }) {
    return InvoiceEntity(
      id: id,
      sellerName: 'Demo',
      sellerTaxCode: '0312345678',
      invoiceNumber: number,
      issuedAt: date,
      currencyCode: 'VND',
      subtotalMinor: 100000,
      taxMinor: 10000,
      totalMinor: total,
      sourceType: InvoiceSourceType.xml,
      sourceHash: hash,
      status: InvoiceStatus.confirmed,
      createdAt: date,
      updatedAt: date,
    );
  }

  test('returns exact match immediately for same source hash', () {
    final match = detector.findLikelyDuplicate(
      invoice(id: 'new', hash: 'same'),
      [invoice(id: 'old', hash: 'same')],
    );
    expect(match?.invoiceId, 'old');
    expect(match?.score, 1);
  });

  test('finds fuzzy duplicate from legal identity and totals', () {
    final match = detector.findLikelyDuplicate(invoice(id: 'new'), [
      invoice(id: 'old'),
    ]);
    expect(match?.score, greaterThanOrEqualTo(0.7));
    expect(match?.reasons, contains('Cùng số hóa đơn'));
  });
}
