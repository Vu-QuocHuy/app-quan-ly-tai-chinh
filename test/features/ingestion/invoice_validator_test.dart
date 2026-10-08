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
}
