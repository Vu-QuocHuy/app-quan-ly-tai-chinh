import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/database/app_database.dart';

void main() {
  test('migrates v1 invoices to v2 and creates scale indexes', () async {
    final database = AppDatabase(
      NativeDatabase.memory(
        setup: (sqlite) {
          sqlite.execute('''
            CREATE TABLE categories (
              id TEXT NOT NULL PRIMARY KEY,
              name TEXT NOT NULL,
              icon_name TEXT NOT NULL,
              color_value INTEGER NOT NULL,
              is_system INTEGER NOT NULL DEFAULT 1
            )
          ''');
          sqlite.execute('''
            CREATE TABLE invoices (
              id TEXT NOT NULL PRIMARY KEY,
              seller_name TEXT NOT NULL,
              seller_tax_code TEXT NULL,
              invoice_number TEXT NULL,
              invoice_symbol TEXT NULL,
              issued_at INTEGER NULL,
              currency_code TEXT NOT NULL DEFAULT 'VND',
              subtotal_minor INTEGER NOT NULL DEFAULT 0,
              tax_minor INTEGER NOT NULL DEFAULT 0,
              total_minor INTEGER NOT NULL DEFAULT 0,
              source_type TEXT NOT NULL,
              source_hash TEXT NULL UNIQUE,
              status TEXT NOT NULL,
              category_id TEXT NULL REFERENCES categories(id) ON DELETE SET NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              confirmed_at INTEGER NULL
            )
          ''');
          sqlite.execute('''
            CREATE TABLE budgets (
              id TEXT NOT NULL PRIMARY KEY,
              month_key TEXT NOT NULL,
              category_id TEXT NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
              limit_minor INTEGER NOT NULL,
              UNIQUE(month_key, category_id)
            )
          ''');
          sqlite.execute(
            "INSERT INTO invoices (id, seller_name, currency_code, "
            "subtotal_minor, tax_minor, total_minor, source_type, status, "
            "created_at, updated_at) VALUES "
            "('legacy', 'Legacy Store', 'VND', 10, 0, 10, 'manual', "
            "'confirmed', 1788048000, 1788048000)",
          );
          sqlite.userVersion = 1;
        },
      ),
    );
    addTearDown(database.close);

    final legacy = await database
        .customSelect(
          'SELECT search_text, tags_json, sync_state, revision FROM invoices '
          "WHERE id = 'legacy'",
        )
        .getSingle();
    final indexes = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'index'")
        .get();

    expect(legacy.read<String>('search_text'), contains('legacy store'));
    expect(legacy.read<String>('tags_json'), '[]');
    expect(legacy.read<String>('sync_state'), 'localOnly');
    expect(legacy.read<int>('revision'), 1);
    expect(
      indexes.map((row) => row.read<String>('name')),
      containsAll([
        'idx_invoices_updated_id',
        'idx_invoices_status_issued',
        'idx_outbox_state_available',
        'idx_import_jobs_state_retry',
      ]),
    );
  });
}
