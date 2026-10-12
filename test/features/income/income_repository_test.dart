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

      await repository.save(
        125000,
        source: IncomeSource.fixed,
        categoryId: 'income_salary',
      );
      final saved = (await repository.getAll()).single;
      expect(saved.source, IncomeSource.fixed);
      expect(saved.categoryId, 'income_salary');

      final event = await database
          .select(database.syncOutboxEvents)
          .getSingle();
      final payload = jsonDecode(event.payloadJson!) as Map<String, dynamic>;
      expect(payload['source'], 'fixed');
      expect(payload['categoryId'], 'income_salary');
      final legacyPayload = Map<String, dynamic>.from(payload)
        ..remove('source')
        ..remove('categoryId');
      expect(
        IncomeEntry.fromPayload(legacyPayload).source,
        IncomeSource.unclassified,
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
