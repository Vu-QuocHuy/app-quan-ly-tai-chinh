import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/database/app_database.dart';
import 'package:hoadon_insight/features/invoices/data/drift_invoice_repository.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_filters.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  late AppDatabase database;
  late DriftInvoiceRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftInvoiceRepository(database);
  });

  tearDown(() => database.close());

  test('persists invoice, lines and evidence transactionally', () async {
    final now = DateTime(2026, 8, 20);
    final invoice = InvoiceEntity(
      id: 'invoice-1',
      sellerName: 'Demo',
      currencyCode: 'VND',
      subtotalMinor: 100000,
      taxMinor: 10000,
      totalMinor: 110000,
      sourceType: InvoiceSourceType.xml,
      sourceHash: 'hash-1',
      status: InvoiceStatus.confirmed,
      categoryId: 'other',
      createdAt: now,
      updatedAt: now,
      confirmedAt: now,
      lines: const [
        InvoiceLineEntity(
          id: 'line-1',
          description: 'Dịch vụ',
          totalMinor: 100000,
        ),
      ],
      evidence: const [
        FieldEvidenceEntity(
          id: 'evidence-1',
          fieldName: 'totalMinor',
          normalizedValue: '110000',
          source: InvoiceSourceType.xml,
          confidence: 0.99,
        ),
      ],
    );

    await repository.saveInvoice(invoice);
    final restored = await repository.findById(invoice.id);

    expect(restored?.sellerName, 'Demo');
    expect(restored?.lines.single.description, 'Dịch vụ');
    expect(restored?.evidence.single.confidence, 0.99);
    expect((await repository.watchInvoices().first), hasLength(1));
    final summary = (await repository.watchInvoiceSummaries().first).single;
    expect(summary.lines, isEmpty);
    expect(summary.evidence, isEmpty);
    expect(summary.totalMinor, 110000);
  });

  test('seeds default categories', () async {
    final categories = await repository.watchCategories().first;
    expect(categories, hasLength(8));
    expect(categories.map((item) => item.id), containsAll(['food', 'other']));
  });

  test('creates, updates and deletes a budget', () async {
    const budget = BudgetEntity(
      id: '2026-08-food',
      monthKey: '2026-08',
      categoryId: 'food',
      limitMinor: 2000000,
    );

    await repository.saveBudget(budget);
    expect(await repository.watchBudgets('2026-08').first, hasLength(1));

    await repository.saveBudget(
      const BudgetEntity(
        id: '2026-08-food',
        monthKey: '2026-08',
        categoryId: 'food',
        limitMinor: 2500000,
      ),
    );
    expect(
      (await repository.watchBudgets('2026-08').first).single.limitMinor,
      2500000,
    );

    await repository.deleteBudget(budget.id);
    expect(await repository.watchBudgets('2026-08').first, isEmpty);
  });

  test('manages custom categories and safely removes references', () async {
    const category = CategoryEntity(
      id: 'custom-office',
      name: 'Văn phòng phẩm',
      iconName: 'category',
      colorValue: 0xFF0F766E,
      isSystem: false,
    );
    await repository.saveCategory(category);
    expect(
      (await repository.watchCategories().first).map((item) => item.id),
      contains('custom-office'),
    );

    final now = DateTime(2026, 8, 20);
    await repository.saveInvoice(
      InvoiceEntity(
        id: 'invoice-custom-category',
        sellerName: 'Office Demo',
        currencyCode: 'VND',
        subtotalMinor: 100000,
        taxMinor: 10000,
        totalMinor: 110000,
        sourceType: InvoiceSourceType.manual,
        status: InvoiceStatus.confirmed,
        categoryId: category.id,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repository.saveBudget(
      const BudgetEntity(
        id: '2026-08-custom-office',
        monthKey: '2026-08',
        categoryId: 'custom-office',
        limitMinor: 500000,
      ),
    );
    await repository.saveMerchantRule('Office Demo', category.id);

    await repository.deleteCategory(category.id);

    expect(
      (await repository.watchCategories().first).map((item) => item.id),
      isNot(contains(category.id)),
    );
    expect(
      (await repository.findById('invoice-custom-category'))?.categoryId,
      'other',
    );
    expect(await repository.watchBudgets('2026-08').first, isEmpty);
    expect(await repository.watchMerchantRules().first, isEmpty);
  });

  test('queues reference data changes in the shared outbox', () async {
    await repository.saveCategory(
      const CategoryEntity(
        id: 'custom-sync',
        name: 'Đồng bộ',
        iconName: 'category',
        colorValue: 0xFF0F766E,
      ),
    );
    await repository.saveBudget(
      const BudgetEntity(
        id: '2026-08-custom-sync',
        monthKey: '2026-08',
        categoryId: 'custom-sync',
        limitMinor: 123000,
      ),
    );
    await repository.saveMerchantRule('Sync Shop', 'custom-sync');

    final rows = await database
        .customSelect(
          'SELECT aggregate_type, aggregate_id, operation '
          'FROM sync_outbox_events ORDER BY created_at, aggregate_type',
        )
        .get();

    expect(
      rows.map(
        (row) =>
            '${row.read<String>('aggregate_type')}: '
            '${row.read<String>('aggregate_id')}: '
            '${row.read<String>('operation')}',
      ),
      containsAll(<String>[
        'category: custom-sync: upsert',
        'budget: 2026-08-custom-sync: upsert',
        'merchant_rule: sync shop: upsert',
      ]),
    );
  });

  test('lists and deletes merchant rules', () async {
    await repository.saveMerchantRule('  Demo Store  ', 'food');

    final rules = await repository.watchMerchantRules().first;
    expect(rules, hasLength(1));
    expect(rules.single.normalizedMerchant, 'demo store');
    expect(rules.single.categoryId, 'food');

    await repository.deleteMerchantRule('Demo Store');
    expect(await repository.watchMerchantRules().first, isEmpty);
  });

  test('deletes user data but preserves system categories', () async {
    await repository.saveBudget(
      const BudgetEntity(
        id: '2026-08-food',
        monthKey: '2026-08',
        categoryId: 'food',
        limitMinor: 2000000,
      ),
    );

    await repository.deleteAllUserData();

    expect(await repository.watchInvoices().first, isEmpty);
    expect(await repository.watchBudgets('2026-08').first, isEmpty);
    expect(await repository.watchCategories().first, hasLength(8));
  });

  test('filters and paginates summaries in SQL', () async {
    await repository.saveInvoices([
      _invoice(
        id: 'a',
        seller: 'Cửa hàng Alpha',
        date: DateTime(2026, 8, 12),
        categoryId: 'food',
        notes: 'Hoàn tiền công tác',
        tags: const ['công việc'],
      ),
      _invoice(
        id: 'b',
        seller: 'Beta Market',
        date: DateTime(2026, 7, 12),
        categoryId: 'shopping',
      ),
      _invoice(
        id: 'c',
        seller: 'Alpha Transport',
        date: DateTime(2026, 8, 15),
        categoryId: 'transport',
        status: InvoiceStatus.needsReview,
      ),
    ]);

    final filtered = await repository
        .watchInvoiceSummaries(
          filter: const InvoiceFilter(
            query: 'công việc',
            monthKey: '2026-08',
            categoryId: 'food',
            status: InvoiceStatus.confirmed,
            sourceType: InvoiceSourceType.manual,
          ),
        )
        .first;
    expect(filtered.map((item) => item.id), ['a']);

    final firstPage = await repository.fetchInvoicePage(limit: 2);
    expect(firstPage.items, hasLength(2));
    expect(firstPage.hasMore, isTrue);
    final secondPage = await repository.fetchInvoicePage(
      limit: 2,
      cursor: firstPage.nextCursor,
    );
    expect(secondPage.items, hasLength(1));
    expect(
      {
        ...firstPage.items.map((item) => item.id),
      }.intersection({...secondPage.items.map((item) => item.id)}),
      isEmpty,
    );
  });

  test('aggregates dashboard in SQL and persists notes and tags', () async {
    await repository.saveInvoices([
      _invoice(
        id: 'aug-1',
        seller: 'Alpha',
        date: DateTime(2026, 8, 5),
        categoryId: 'food',
        total: 120000,
        notes: 'Ghi chú',
        tags: const ['team'],
      ),
      _invoice(
        id: 'aug-2',
        seller: 'Beta',
        date: DateTime(2026, 8, 8),
        categoryId: 'food',
        total: 80000,
      ),
      _invoice(
        id: 'jul-1',
        seller: 'Gamma',
        date: DateTime(2026, 7, 8),
        categoryId: 'transport',
        total: 50000,
      ),
    ]);
    await repository.saveBudget(
      const BudgetEntity(
        id: '2026-08-food',
        monthKey: '2026-08',
        categoryId: 'food',
        limitMinor: 400000,
      ),
    );

    final snapshot = await repository.watchDashboard('2026-08').first;
    final restored = await repository.findById('aug-1');
    expect(snapshot.totalMinor, 200000);
    expect(snapshot.invoiceCount, 2);
    expect(snapshot.previousMonthTotalMinor, 50000);
    expect(snapshot.categoryTotals['food'], 200000);
    expect(snapshot.dailyTotals, containsPair(5, 120000));
    expect(snapshot.budgetLimitMinor, 400000);
    expect(restored?.notes, 'Ghi chú');
    expect(restored?.tags, ['team']);
  });

  test('soft deletes invoices and records sync outbox events', () async {
    final invoice = _invoice(
      id: 'delete-me',
      seller: 'Demo',
      date: DateTime(2026, 8, 20),
      categoryId: 'other',
    );
    await repository.saveInvoice(invoice);
    await repository.deleteInvoice(invoice.id);

    expect(await repository.findById(invoice.id), isNull);
    expect(await repository.watchInvoiceSummaries().first, isEmpty);
    final raw = await database
        .customSelect(
          'SELECT deleted_at, sync_state, revision FROM invoices WHERE id = ?',
          variables: [Variable<String>(invoice.id)],
        )
        .getSingle();
    final outbox = await database
        .customSelect(
          'SELECT operation FROM sync_outbox_events '
          'WHERE aggregate_id = ? ORDER BY created_at',
          variables: [Variable<String>(invoice.id)],
        )
        .get();
    expect(raw.readNullable<DateTime>('deleted_at'), isNotNull);
    expect(raw.read<String>('sync_state'), InvoiceSyncState.pending.name);
    expect(raw.read<int>('revision'), 2);
    expect(outbox.map((row) => row.read<String>('operation')), ['delete']);

    await repository.saveInvoice(
      _invoice(
        id: 'reimported',
        seller: 'Demo',
        date: DateTime(2026, 8, 21),
        categoryId: 'other',
      ).copyWith(sourceHash: invoice.sourceHash),
    );
    expect(await repository.findById('reimported'), isNotNull);
  });
}

InvoiceEntity _invoice({
  required String id,
  required String seller,
  required DateTime date,
  required String categoryId,
  int total = 100000,
  String? notes,
  List<String> tags = const [],
  InvoiceStatus status = InvoiceStatus.confirmed,
}) {
  return InvoiceEntity(
    id: id,
    sellerName: seller,
    currencyCode: 'VND',
    subtotalMinor: total,
    taxMinor: 0,
    totalMinor: total,
    sourceType: InvoiceSourceType.manual,
    sourceHash: 'hash-$id',
    status: status,
    categoryId: categoryId,
    notes: notes,
    tags: tags,
    issuedAt: date,
    createdAt: date,
    updatedAt: date,
    confirmedAt: status == InvoiceStatus.confirmed ? date : null,
  );
}
