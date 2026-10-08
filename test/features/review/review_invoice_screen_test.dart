import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_repository.dart';
import 'package:hoadon_insight/features/review/presentation/review_invoice_screen.dart';

void main() {
  testWidgets('shows OCR consistency warnings before the user saves', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 20);
    final invoice = InvoiceEntity(
      id: 'ocr-draft',
      sellerName: 'Cửa hàng',
      issuedAt: now,
      currencyCode: 'VND',
      subtotalMinor: 200000,
      taxMinor: 0,
      totalMinor: 200000,
      sourceType: InvoiceSourceType.imageOcr,
      status: InvoiceStatus.needsReview,
      createdAt: now,
      updatedAt: now,
      lines: const [
        InvoiceLineEntity(
          id: 'line-1',
          description: 'Mặt hàng',
          quantity: 1,
          unitPriceMinor: 90000,
          totalMinor: 90000,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriesProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(home: ReviewInvoiceScreen(invoice: invoice)),
      ),
    );

    expect(
      find.textContaining('Tổng các dòng hàng chưa khớp với tiền trước thuế.'),
      findsOneWidget,
    );
    expect(find.text('Thuế suất'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Thuế'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Giảm giá'), findsOneWidget);
  });

  testWidgets('maps unavailable OCR categories to Khác before saving', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 20);
    final invoice = InvoiceEntity(
      id: 'unknown-category-draft',
      sellerName: 'Cửa hàng',
      currencyCode: 'VND',
      subtotalMinor: 100000,
      taxMinor: 0,
      totalMinor: 100000,
      sourceType: InvoiceSourceType.imageOcr,
      status: InvoiceStatus.needsReview,
      categoryId: 'category-from-model-that-no-longer-exists',
      createdAt: now,
      updatedAt: now,
      lines: const [
        InvoiceLineEntity(
          id: 'line-1',
          description: 'Mặt hàng',
          totalMinor: 100000,
          categoryId: 'unknown-line-category',
        ),
      ],
    );

    final repository = _RecordingInvoiceRepository();
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (context, state) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => context.push('/review'),
                child: const Text('Mở hóa đơn'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/review',
          builder: (context, state) => ReviewInvoiceScreen(invoice: invoice),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          invoiceRepositoryProvider.overrideWithValue(repository),
          categoriesProvider.overrideWith(
            (ref) => Stream.value([
              const CategoryEntity(
                id: 'other',
                name: 'Khác',
                iconName: 'category',
                colorValue: 0xFF64748B,
              ),
            ]),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('Mở hóa đơn'));
    await tester.pumpAndSettle();
    expect(find.text('Khác'), findsNWidgets(2));

    final discountField = find.widgetWithText(TextFormField, 'Giảm giá');
    await tester.ensureVisible(discountField);
    await tester.enterText(discountField, '5000');
    await tester.tap(find.byKey(const Key('confirm-invoice-button')));
    await tester.pumpAndSettle();

    expect(repository.savedInvoice?.categoryId, 'other');
    expect(repository.savedInvoice?.discountMinor, 5000);
    expect(repository.savedInvoice?.lines.single.categoryId, 'other');
  });

  testWidgets('asks before leaving after only a quantity edit', (tester) async {
    final now = DateTime(2026, 8, 20);
    final invoice = InvoiceEntity(
      id: 'quantity-edit-draft',
      sellerName: 'Cửa hàng',
      currencyCode: 'VND',
      subtotalMinor: 100000,
      taxMinor: 0,
      totalMinor: 100000,
      sourceType: InvoiceSourceType.imageOcr,
      status: InvoiceStatus.needsReview,
      createdAt: now,
      updatedAt: now,
      lines: const [
        InvoiceLineEntity(
          id: 'line-1',
          description: 'Mặt hàng',
          quantity: 1,
          unitPriceMinor: 100000,
          totalMinor: 100000,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriesProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => ReviewInvoiceScreen(invoice: invoice),
                    ),
                  ),
                  child: const Text('Mở hóa đơn'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở hóa đơn'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Số lượng'), '2');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Bỏ các thay đổi?'), findsOneWidget);
  });

  testWidgets('confirms before removing a receipt line', (tester) async {
    final now = DateTime(2026, 8, 20);
    final invoice = InvoiceEntity(
      id: 'line-delete-draft',
      sellerName: 'Cửa hàng',
      currencyCode: 'VND',
      subtotalMinor: 100000,
      taxMinor: 0,
      totalMinor: 100000,
      sourceType: InvoiceSourceType.imageOcr,
      status: InvoiceStatus.needsReview,
      createdAt: now,
      updatedAt: now,
      lines: const [
        InvoiceLineEntity(
          id: 'line-1',
          description: 'Mặt hàng',
          quantity: 1,
          unitPriceMinor: 100000,
          totalMinor: 100000,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          categoriesProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(home: ReviewInvoiceScreen(invoice: invoice)),
      ),
    );

    final deleteButton = find.byTooltip('Xóa dòng 1');
    await tester.ensureVisible(deleteButton);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    expect(find.text('Xóa dòng hàng?'), findsOneWidget);

    await tester.tap(find.text('Hủy'));
    await tester.pumpAndSettle();
    expect(deleteButton, findsOneWidget);

    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xóa dòng'));
    await tester.pumpAndSettle();
    expect(deleteButton, findsNothing);
  });

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

    expect(find.text('Nội dung chi (tùy chọn)'), findsOneWidget);
    expect(find.text('Hãy nhập tên người bán.'), findsNothing);
    expect(find.text('Số tiền phải lớn hơn 0.'), findsWidgets);
  });

  testWidgets('saves a manual expense without a receipt or description', (
    tester,
  ) async {
    final date = DateTime(2026, 8, 20);
    final invoice = InvoiceEntity(
      id: 'manual-expense-draft',
      sellerName: '',
      currencyCode: 'VND',
      subtotalMinor: 0,
      taxMinor: 0,
      totalMinor: 0,
      sourceType: InvoiceSourceType.manual,
      status: InvoiceStatus.needsReview,
      createdAt: date,
      updatedAt: date,
    );
    final repository = _RecordingInvoiceRepository();
    final router = GoRouter(
      initialLocation: '/review',
      routes: [
        GoRoute(
          path: '/review',
          builder: (context, state) => ReviewInvoiceScreen(invoice: invoice),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          invoiceRepositoryProvider.overrideWithValue(repository),
          categoriesProvider.overrideWith(
            (ref) => Stream.value([
              const CategoryEntity(
                id: 'food',
                name: 'Ăn uống',
                iconName: 'restaurant',
                colorValue: 0xFF4C7A5A,
              ),
              const CategoryEntity(
                id: 'other',
                name: 'Khác',
                iconName: 'category',
                colorValue: 0xFF64748B,
              ),
            ]),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Thêm khoản chi'), findsOneWidget);
    expect(find.text('Hàng hóa, dịch vụ'), findsNothing);
    expect(find.text('Tên người bán *'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Số tiền *'),
      '25000',
    );
    await tester.tap(find.byKey(const Key('confirm-invoice-button')));
    await tester.pumpAndSettle();

    final saved = repository.savedInvoice!;
    expect(saved.sellerName, 'Khoản chi');
    expect(saved.issuedAt, date);
    expect(saved.totalMinor, 25000);
    expect(saved.subtotalMinor, 25000);
    expect(saved.taxMinor, 0);
    expect(saved.categoryId, 'other');
    expect(saved.lines, isEmpty);
    expect(saved.status, InvoiceStatus.confirmed);
  });
}

class _RecordingInvoiceRepository implements InvoiceRepository {
  InvoiceEntity? savedInvoice;

  @override
  Future<void> saveInvoice(InvoiceEntity invoice) async {
    savedInvoice = invoice;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
