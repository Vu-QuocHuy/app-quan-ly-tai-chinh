import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:hoadon_insight/features/sharing/domain/shared_bill_models.dart';

void main() {
  final invoice = InvoiceEntity(
    id: 'invoice-1',
    sellerName: 'Cửa hàng demo',
    sellerTaxCode: '0123456789',
    invoiceNumber: '0001',
    invoiceSymbol: 'AA/26E',
    issuedAt: DateTime.utc(2026, 9, 19),
    currencyCode: 'VND',
    subtotalMinor: 90000,
    taxMinor: 9000,
    totalMinor: 99000,
    sourceType: InvoiceSourceType.manual,
    status: InvoiceStatus.confirmed,
    createdAt: DateTime.utc(2026, 9, 19),
    updatedAt: DateTime.utc(2026, 9, 19),
    notes: 'Không đưa ghi chú riêng tư vào snapshot.',
    tags: const ['private'],
    lines: const [
      InvoiceLineEntity(description: 'Cà phê', totalMinor: 99000, id: 'line-1'),
    ],
  );

  test('builds a minimal share snapshot without private notes or tags', () {
    final payload = invoiceShareSnapshot(invoice);

    expect(payload['seller_name'], 'Cửa hàng demo');
    expect(payload['total_minor'], 99000);
    expect(payload.containsKey('notes'), isFalse);
    expect(payload.containsKey('tags'), isFalse);
    expect(payload['lines'], [
      {'description': 'Cà phê', 'total_minor': 99000},
    ]);
  });

  test('parses a direct share and preserves split totals', () {
    final share = DirectBillShare.fromMap({
      'id': '550e8400-e29b-41d4-a716-446655440000',
      'owner_id': '550e8400-e29b-41d4-a716-446655440001',
      'recipient_id': null,
      'recipient_email': 'friend@example.com',
      'source_invoice_id': 'invoice-1',
      'source_snapshot': invoiceShareSnapshot(invoice),
      'total_minor': 99000,
      'owner_amount_minor': 49000,
      'recipient_amount_minor': 50000,
      'status': 'pending',
      'created_at': '2026-09-19T00:00:00Z',
      'updated_at': '2026-09-19T00:00:00Z',
      'accepted_at': null,
    });

    expect(share.isPending, isTrue);
    expect(share.snapshot.sellerName, 'Cửa hàng demo');
    expect(share.recipientAmountMinor, 50000);
  });

  test('rejects a share whose split does not equal the total', () {
    expect(
      () => DirectBillShare.fromMap({
        'id': '550e8400-e29b-41d4-a716-446655440000',
        'owner_id': '550e8400-e29b-41d4-a716-446655440001',
        'recipient_email': 'friend@example.com',
        'source_invoice_id': 'invoice-1',
        'source_snapshot': invoiceShareSnapshot(invoice),
        'total_minor': 99000,
        'owner_amount_minor': 40000,
        'recipient_amount_minor': 40000,
        'status': 'pending',
        'created_at': '2026-09-19T00:00:00Z',
        'updated_at': '2026-09-19T00:00:00Z',
      }),
      throwsFormatException,
    );
  });
}
