import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/database/app_database.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/core/utils/money_formatter.dart';
import 'package:hoadon_insight/features/invoices/data/drift_invoice_repository.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:hoadon_insight/features/sync/presentation/sync_conflicts_screen.dart';

void main() {
  late AppDatabase database;
  late DriftInvoiceRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftInvoiceRepository(database);
  });

  tearDown(() => database.close());

  testWidgets('shows both versions and resolves a conflict on a small phone', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final local = await _seedConflict(repository);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [invoiceRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(home: const SyncConflictsScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Local Store'), findsAtLeastNWidgets(1));
    // Trước đây assertion này ghim đúng một bug: màn hình in nguyên
    // `'$value $currency'` -> "120000 VND". Nay số tiền đi qua
    // MoneyFormatter nên hiện "120.000 ₫".
    expect(
      find.text(MoneyFormatter.format(120000, currencyCode: 'VND')),
      findsOneWidget,
    );
    expect(find.text('Dùng bản cloud'), findsOneWidget);
    expect(find.text('Giữ bản trên máy'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Dùng bản cloud'));
    await tester.pumpAndSettle();

    expect(find.text('Dữ liệu đã nhất quán'), findsOneWidget);
    expect((await repository.findById(local.id))?.sellerName, 'Cloud Store');

    // Let Drift finish closing its query stream before the test binding checks
    // for pending timers during ProviderScope disposal.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('keeps conflict actions usable in landscape with larger text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(812, 375));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _seedConflict(repository);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [invoiceRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: const SyncConflictsScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Dùng bản cloud'), findsOneWidget);
    expect(find.text('Giữ bản trên máy'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  });
}

Future<InvoiceEntity> _seedConflict(DriftInvoiceRepository repository) async {
  final local = _invoice('Local Store', 100000);
  await repository.saveInvoice(local);
  await repository.markInvoiceConflict(
    local.id,
    remote: local.copyWith(sellerName: 'Cloud Store', totalMinor: 120000),
  );
  return local;
}

InvoiceEntity _invoice(String seller, int total) {
  final now = DateTime(2026, 8, 31);
  return InvoiceEntity(
    id: 'conflict-ui',
    sellerName: seller,
    currencyCode: 'VND',
    subtotalMinor: total,
    taxMinor: 0,
    totalMinor: total,
    sourceType: InvoiceSourceType.manual,
    status: InvoiceStatus.confirmed,
    createdAt: now,
    updatedAt: now,
  );
}
