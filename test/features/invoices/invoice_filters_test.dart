import 'package:flutter_test/flutter_test.dart';

import 'package:hoadon_insight/features/invoices/domain/invoice_filters.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  final invoices = [
    _invoice(
      id: 'coffee',
      sellerName: 'Cà phê Bình Minh',
      invoiceNumber: 'HD-001',
      categoryId: 'food',
      sourceType: InvoiceSourceType.xml,
      status: InvoiceStatus.confirmed,
      issuedAt: DateTime(2026, 8, 5),
      notes: 'Tiếp khách tháng tám',
      tags: const ['công việc'],
    ),
    _invoice(
      id: 'office',
      sellerName: 'Văn phòng phẩm Sao Mai',
      invoiceNumber: 'HD-002',
      categoryId: 'office',
      sourceType: InvoiceSourceType.imageOcr,
      status: InvoiceStatus.needsReview,
      issuedAt: DateTime(2026, 7, 20),
    ),
  ];

  test('searches seller, invoice number, notes and tags', () {
    expect(
      const InvoiceFilter(query: 'bình minh').apply(invoices),
      hasLength(1),
    );
    expect(
      const InvoiceFilter(query: 'HD-002').apply(invoices).single.id,
      'office',
    );
    expect(
      const InvoiceFilter(query: 'tiếp khách').apply(invoices).single.id,
      'coffee',
    );
    expect(
      const InvoiceFilter(query: 'công việc').apply(invoices).single.id,
      'coffee',
    );
  });

  test('combines month, category, status and source filters', () {
    final result = const InvoiceFilter(
      monthKey: '2026-08',
      categoryId: 'food',
      status: InvoiceStatus.confirmed,
      sourceType: InvoiceSourceType.xml,
    ).apply(invoices);

    expect(result.map((item) => item.id), ['coffee']);
  });

  test('empty filter returns all invoices', () {
    expect(const InvoiceFilter().apply(invoices), hasLength(2));
  });
}

InvoiceEntity _invoice({
  required String id,
  required String sellerName,
  required String invoiceNumber,
  required String categoryId,
  required InvoiceSourceType sourceType,
  required InvoiceStatus status,
  required DateTime issuedAt,
  String? notes,
  List<String> tags = const [],
}) {
  return InvoiceEntity(
    id: id,
    sellerName: sellerName,
    invoiceNumber: invoiceNumber,
    currencyCode: 'VND',
    subtotalMinor: 100000,
    taxMinor: 10000,
    totalMinor: 110000,
    sourceType: sourceType,
    status: status,
    categoryId: categoryId,
    issuedAt: issuedAt,
    createdAt: issuedAt,
    updatedAt: issuedAt,
    notes: notes,
    tags: tags,
  );
}
