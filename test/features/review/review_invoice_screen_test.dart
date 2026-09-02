import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:hoadon_insight/features/review/presentation/review_invoice_screen.dart';

void main() {
  testWidgets('shows inline errors when required fields are invalid', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 20);
    final invoice = InvoiceEntity(
      id: 'draft',
      sellerName: '',
      currencyCode: 'VND',
      subtotalMinor: 0,
      taxMinor: 0,
      totalMinor: 0,
      sourceType: InvoiceSourceType.manual,
      status: InvoiceStatus.needsReview,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriesProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(home: ReviewInvoiceScreen(invoice: invoice)),
      ),
    );

    final saveButton = find.byKey(const Key('confirm-invoice-button'));
    tester.widget<FilledButton>(saveButton).onPressed?.call();
    await tester.pumpAndSettle();

    expect(find.text('Hãy nhập tên người bán.'), findsWidgets);
    expect(find.text('Tổng tiền phải lớn hơn 0.'), findsWidgets);
  });
}
