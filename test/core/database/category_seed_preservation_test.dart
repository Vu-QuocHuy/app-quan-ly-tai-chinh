import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/database/app_database.dart';

void main() {
  test(
    'reopening preserves edited categories and seeds missing defaults',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'finmi-category-seed-',
      );
      final file = File('${directory.path}/database.sqlite');
      AppDatabase? database;
      try {
        database = AppDatabase(NativeDatabase(file));
        await database.customSelect('SELECT id FROM categories').get();
        await database.customStatement(
          "UPDATE categories SET name = 'Tên đã sửa', color_value = 123 WHERE id = 'food'",
        );
        await database.customStatement(
          "DELETE FROM categories WHERE id = 'income_salary'",
        );
        await database.close();

        database = AppDatabase(NativeDatabase(file));
        final edited = await database
            .customSelect(
              "SELECT name, color_value FROM categories WHERE id = 'food'",
            )
            .getSingle();
        expect(edited.read<String>('name'), 'Tên đã sửa');
        expect(edited.read<int>('color_value'), 123);
        final missing = await database
            .customSelect(
              "SELECT kind FROM categories WHERE id = 'income_salary'",
            )
            .getSingle();
        expect(missing.read<String>('kind'), 'income');
      } finally {
        await database?.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
