import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../constants/app_constants.dart';

part 'app_database.g.dart';

@DataClassName('InvoiceRow')
class Invoices extends Table {
  TextColumn get id => text()();
  TextColumn get cloudId => text().nullable()();
  TextColumn get sellerName => text()();
  TextColumn get invoiceSymbol => text().nullable()();
  DateTimeColumn get issuedAt => dateTime().nullable()();
  TextColumn get currencyCode =>
      text().withDefault(const Constant(AppConstants.defaultCurrency))();
  IntColumn get subtotalMinor => integer().withDefault(const Constant(0))();
  IntColumn get taxMinor => integer().withDefault(const Constant(0))();
  IntColumn get discountMinor => integer().withDefault(const Constant(0))();
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
  TextColumn get categoryId => text().nullable().references(
    Categories,
    #id,
    onDelete: KeyAction.setNull,
  )();

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
  AppDatabase([QueryExecutor? executor, String databaseName = 'hoadon_insight'])
    : super(
        executor ??
            driftDatabase(
              name: databaseName,
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.js'),
              ),
            ),
      );

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await migrator.createAll();
      await batch((batch) {
        batch.insertAllOnConflictUpdate(categories, _defaultCategories);
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
      if (from < 5) {
        final invoiceLinesTable = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'invoice_lines'",
        ).getSingleOrNull();
        if (invoiceLinesTable == null) {
          await migrator.createTable(invoiceLines);
        } else {
          await migrator.addColumn(invoiceLines, invoiceLines.categoryId);
        }
      }
      if (from < 6) {
        await migrator.addColumn(invoices, invoices.discountMinor);
      }
      if (from < 7) {
        final invoiceColumns = (await customSelect(
          'PRAGMA table_info(invoices)',
        ).get()).map((row) => row.read<String>('name')).toSet();
        final retiredColumns = const [
          'seller_tax_code',
          'invoice_number',
        ].where(invoiceColumns.contains);
        var cleanedSearchText = 'search_text';
        for (final column in retiredColumns) {
          cleanedSearchText =
              "replace($cleanedSearchText, lower(ifnull($column, '')), '')";
        }
        if (cleanedSearchText != 'search_text') {
          await customStatement(
            'UPDATE invoices SET search_text = trim($cleanedSearchText)',
          );
        }
        await _removeLegacyInvoiceIdentifiersFromJson(
          table: 'sync_outbox_events',
          rowId: 'id',
          jsonColumn: 'payload_json',
        );
        await _removeLegacyInvoiceIdentifiersFromJson(
          table: 'invoice_conflicts',
          rowId: 'invoice_id',
          jsonColumn: 'remote_payload_json',
        );
        final evidenceTable = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'field_evidences'",
        ).getSingleOrNull();
        if (evidenceTable != null) {
          await customStatement('''
            DELETE FROM field_evidences
            WHERE field_name IN (
              'sellerTaxCode', 'invoiceNumber', 'seller_tax_code', 'invoice_number'
            )
          ''');
        }
        for (final column in retiredColumns) {
          await customStatement('ALTER TABLE invoices DROP COLUMN $column');
        }
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await _createIndexes();
    },
  );

  Future<void> _removeLegacyInvoiceIdentifiersFromJson({
    required String table,
    required String rowId,
    required String jsonColumn,
  }) async {
    final rows = await customSelect(
      'SELECT $rowId, $jsonColumn FROM $table WHERE $jsonColumn IS NOT NULL',
    ).get();
    for (final row in rows) {
      final raw = row.read<String>(jsonColumn);
      Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        continue;
      }
      if (decoded is! Map<String, dynamic>) continue;
      decoded
        ..remove('sellerTaxCode')
        ..remove('invoiceNumber')
        ..remove('seller_tax_code')
        ..remove('invoice_number');
      final evidence = decoded['evidence'];
      if (evidence is List) {
        decoded['evidence'] = evidence
            .where((item) {
              if (item is! Map) return true;
              return !const {
                'sellerTaxCode',
                'invoiceNumber',
                'seller_tax_code',
                'invoice_number',
              }.contains(item['fieldName'] ?? item['field_name']);
            })
            .toList(growable: false);
      }
      await customStatement(
        'UPDATE $table SET $jsonColumn = ? WHERE $rowId = ?',
        [jsonEncode(decoded), row.read<String>(rowId)],
      );
    }
  }

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
