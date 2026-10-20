import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/database/app_database.dart';
import 'package:hoadon_insight/features/income/data/income_repository.dart';

void main() {
  test('v13 income data survives upgrade and gains editable content', () async {
    final directory = await Directory.systemTemp.createTemp(
      'finmi-note-migration-',
    );
    final file = File('${directory.path}/test.sqlite');
    var database = AppDatabase(NativeDatabase(file));
    try {
      await IncomeRepository(database).save(
        125000,
        source: IncomeSource.manual,
        receivedAt: DateTime(2026, 9, 15),
      );
      await database.customStatement('ALTER TABLE incomes DROP COLUMN note');
      await database.customStatement('PRAGMA user_version = 13');
      await database.close();
      database = AppDatabase(NativeDatabase(file));
      final repository = IncomeRepository(database);
      final old = (await repository.getAll()).single;
      expect(old.amountMinor, 125000);
      expect(old.receivedAt, DateTime(2026, 9, 15));
      expect(old.note, '');
      await repository.save(
        old.amountMinor,
        source: old.source,
        existing: old,
        note: 'Lương tháng 9',
      );
      expect((await repository.getAll()).single.note, 'Lương tháng 9');
    } finally {
      await database.close();
      await directory.delete(recursive: true);
    }
  });
}
