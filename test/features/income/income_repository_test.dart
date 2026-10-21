import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/database/app_database.dart';
import 'package:hoadon_insight/features/income/data/income_repository.dart';

void main() {
  test(
    'saves income category and reads legacy payloads as unclassified',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = IncomeRepository(database);

      await database.customStatement('''
        INSERT INTO categories (id, name, icon_name, color_value, kind)
        VALUES ('income_salary', 'Lương', 'payments', 4280640491, 'income')
      ''');

      await repository.save(
        125000,
        source: IncomeSource.fixed,
        categoryId: 'income_salary',
        note: 'Lương tháng 9',
        receivedAt: DateTime(2026, 9, 15),
      );
      final saved = (await repository.getAll()).single;
      expect(saved.source, IncomeSource.fixed);
      expect(saved.categoryId, 'income_salary');
      expect(saved.note, 'Lương tháng 9');
      expect(saved.receivedAt, DateTime(2026, 9, 15));

      final event = await database
          .select(database.syncOutboxEvents)
          .getSingle();
      final payload = jsonDecode(event.payloadJson!) as Map<String, dynamic>;
      expect(payload['source'], 'fixed');
      expect(payload['categoryId'], 'income_salary');
      expect(payload['note'], 'Lương tháng 9');
      final legacyPayload = Map<String, dynamic>.from(payload)
        ..remove('source')
        ..remove('note')
        ..remove('categoryId');
      expect(
        IncomeEntry.fromPayload(legacyPayload).source,
        IncomeSource.unclassified,
      );
      expect(IncomeEntry.fromPayload(legacyPayload).note, '');
      await repository.save(130000, source: saved.source, existing: saved);
      final edited = (await repository.getAll()).single;
      expect(edited.note, saved.note);
      expect(edited.receivedAt, saved.receivedAt);
      expect(
        () => IncomeEntry.fromPayload({...payload, 'note': 42}),
        throwsFormatException,
      );
      expect(
        IncomeEntry.fromPayload(legacyPayload).categoryId,
        IncomeEntry.unclassifiedCategoryId,
      );
      expect(
        () => IncomeEntry.fromPayload({...payload, 'source': 'unknown'}),
        throwsFormatException,
      );
      expect(
        () => IncomeEntry.fromPayload({...payload, 'categoryId': ''}),
        throwsFormatException,
      );
    },
  );
}
