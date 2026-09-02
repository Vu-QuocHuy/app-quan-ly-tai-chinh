import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../constants/app_constants.dart';

part 'app_database.g.dart';

@DataClassName('InvoiceRow')
class Invoices extends Table {
  TextColumn get id => text()();
  TextColumn get cloudId => text().nullable()();
  TextColumn get sellerName => text()();
  TextColumn get sellerTaxCode => text().nullable()();
  TextColumn get invoiceNumber => text().nullable()();
  TextColumn get invoiceSymbol => text().nullable()();
  DateTimeColumn get issuedAt => dateTime().nullable()();
  TextColumn get currencyCode =>
      text().withDefault(const Constant(AppConstants.defaultCurrency))();
  IntColumn get subtotalMinor => integer().withDefault(const Constant(0))();
  IntColumn get taxMinor => integer().withDefault(const Constant(0))();
  IntColumn get totalMinor => integer().withDefault(const Constant(0))();
  TextColumn get sourceType => text()();
  TextColumn get sourceHash => text().nullable()();
  TextColumn get status => text()();
  TextColumn get searchText => text().withDefault(const Constant(''))();
  TextColumn get notes => text().nullable()();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  TextColumn get categoryId => text().nullable().references(
    Categories,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get confirmedAt => dateTime().nullable()();
  TextColumn get syncState => text().withDefault(const Constant('localOnly'))();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {sourceHash},
  ];
}

@DataClassName('InvoiceLineRow')
class InvoiceLines extends Table {
  TextColumn get id => text()();
  TextColumn get invoiceId =>
      text().references(Invoices, #id, onDelete: KeyAction.cascade)();
  TextColumn get description => text()();
  RealColumn get quantity => real().nullable()();
  IntColumn get unitPriceMinor => integer().nullable()();
  RealColumn get taxRate => real().nullable()();
  IntColumn get totalMinor => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('FieldEvidenceRow')
class FieldEvidences extends Table {
  TextColumn get id => text()();
  TextColumn get invoiceId =>
      text().references(Invoices, #id, onDelete: KeyAction.cascade)();
  TextColumn get fieldName => text()();
  TextColumn get rawValue => text().nullable()();
  TextColumn get normalizedValue => text()();
  TextColumn get sourceType => text()();
  RealColumn get confidence => real()();
  BoolColumn get correctedByUser =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CategoryRow')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get iconName => text()();
  IntColumn get colorValue => integer()();
  BoolColumn get isSystem => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MerchantRuleRow')
class MerchantRules extends Table {
  TextColumn get id => text()();
  TextColumn get normalizedMerchant => text().unique()();
  TextColumn get categoryId =>
      text().references(Categories, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('BudgetRow')
class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get monthKey => text()();
  TextColumn get categoryId =>
      text().references(Categories, #id, onDelete: KeyAction.cascade)();
  IntColumn get limitMinor => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {monthKey, categoryId},
  ];
}

@DataClassName('InvoiceConflictRow')
class InvoiceConflicts extends Table {
  TextColumn get invoiceId =>
      text().references(Invoices, #id, onDelete: KeyAction.cascade)();
  TextColumn get remotePayloadJson => text()();
  IntColumn get remoteRevision => integer()();
  DateTimeColumn get detectedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {invoiceId};
}

@DataClassName('ExtractionAttemptRow')
class ExtractionAttempts extends Table {
  TextColumn get id => text()();
  TextColumn get invoiceId =>
      text().references(Invoices, #id, onDelete: KeyAction.cascade)();
  TextColumn get adapterName => text()();
  TextColumn get adapterVersion => text()();
  TextColumn get state => text()();
  TextColumn get errorCode => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get finishedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SyncOutboxEventRow')
class SyncOutboxEvents extends Table {
  TextColumn get id => text()();
  TextColumn get aggregateType => text()();
  TextColumn get aggregateId => text()();
  TextColumn get operation => text()();
  TextColumn get payloadJson => text().nullable()();
  IntColumn get revision => integer()();
  TextColumn get state => text().withDefault(const Constant('pending'))();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get availableAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('SyncCursorRow')
class SyncCursors extends Table {
  TextColumn get userId => text()();
  TextColumn get aggregateType => text()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  TextColumn get updatedId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId, aggregateType};
}

@DataClassName('ImportJobRow')
class ImportJobs extends Table {
  TextColumn get id => text()();
  TextColumn get fileName => text()();
  TextColumn get kind => text()();
  TextColumn get state => text().withDefault(const Constant('queued'))();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  IntColumn get maxAttempts => integer().withDefault(const Constant(3))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Invoices,
    InvoiceLines,
    FieldEvidences,
    Categories,
    MerchantRules,
    Budgets,
    ExtractionAttempts,
    SyncOutboxEvents,
    SyncCursors,
    ImportJobs,
    InvoiceConflicts,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'hoadon_insight'));

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await batch((batch) {
        batch.insertAll(categories, _defaultCategories);
      });
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.addColumn(invoices, invoices.cloudId);
        await migrator.addColumn(invoices, invoices.searchText);
        await migrator.addColumn(invoices, invoices.notes);
        await migrator.addColumn(invoices, invoices.tagsJson);
        await migrator.addColumn(invoices, invoices.syncState);
        await migrator.addColumn(invoices, invoices.revision);
        await migrator.addColumn(invoices, invoices.deletedAt);
        await migrator.createTable(syncOutboxEvents);
        await migrator.createTable(importJobs);
        await customStatement('''
          UPDATE invoices
          SET search_text = lower(trim(
            seller_name || ' ' ||
            ifnull(seller_tax_code, '') || ' ' ||
            ifnull(invoice_number, '') || ' ' ||
            ifnull(invoice_symbol, '')
          ))
        ''');
      }
      if (from < 3) {
        await migrator.createTable(syncCursors);
      }
      if (from < 4) {
        await migrator.createTable(invoiceConflicts);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await _createIndexes();
    },
  );

  Future<void> _createIndexes() async {
    const statements = [
      'CREATE INDEX IF NOT EXISTS idx_invoices_updated_id ON invoices (updated_at DESC, id DESC)',
      'CREATE INDEX IF NOT EXISTS idx_invoices_issued_at ON invoices (issued_at DESC)',
      'CREATE INDEX IF NOT EXISTS idx_invoices_status_issued ON invoices (status, issued_at DESC)',
      'CREATE INDEX IF NOT EXISTS idx_invoices_category ON invoices (category_id)',
      'CREATE INDEX IF NOT EXISTS idx_invoices_source_hash ON invoices (source_hash)',
      'CREATE INDEX IF NOT EXISTS idx_invoices_deleted_at ON invoices (deleted_at)',
      'CREATE INDEX IF NOT EXISTS idx_budgets_month ON budgets (month_key)',
      'CREATE INDEX IF NOT EXISTS idx_outbox_state_available ON sync_outbox_events (state, available_at)',
      'CREATE INDEX IF NOT EXISTS idx_import_jobs_state_retry ON import_jobs (state, next_retry_at)',
      'CREATE INDEX IF NOT EXISTS idx_invoice_conflicts_detected_at ON invoice_conflicts (detected_at DESC)',
    ];
    for (final statement in statements) {
      await customStatement(statement);
    }
  }

  static final _defaultCategories = [
    CategoriesCompanion.insert(
      id: 'food',
      name: 'Ăn uống',
      iconName: 'restaurant',
      colorValue: 0xFFEA580C,
    ),
    CategoriesCompanion.insert(
      id: 'transport',
      name: 'Di chuyển',
      iconName: 'directions_car',
      colorValue: 0xFF2563EB,
    ),
    CategoriesCompanion.insert(
      id: 'shopping',
      name: 'Mua sắm',
      iconName: 'shopping_bag',
      colorValue: 0xFF7C3AED,
    ),
    CategoriesCompanion.insert(
      id: 'utilities',
      name: 'Tiện ích',
      iconName: 'bolt',
      colorValue: 0xFFCA8A04,
    ),
    CategoriesCompanion.insert(
      id: 'health',
      name: 'Y tế',
      iconName: 'health_and_safety',
      colorValue: 0xFFDC2626,
    ),
    CategoriesCompanion.insert(
      id: 'education',
      name: 'Giáo dục',
      iconName: 'school',
      colorValue: 0xFF0891B2,
    ),
    CategoriesCompanion.insert(
      id: 'entertainment',
      name: 'Giải trí',
      iconName: 'movie',
      colorValue: 0xFFDB2777,
    ),
    CategoriesCompanion.insert(
      id: 'other',
      name: 'Khác',
      iconName: 'category',
      colorValue: 0xFF64748B,
    ),
  ];
}
