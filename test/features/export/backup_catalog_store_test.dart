import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hoadon_insight/features/export/data/backup_catalog_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'lưu lịch sử theo thứ tự mới nhất và giới hạn retention metadata',
    () async {
      final store = const BackupCatalogStore(maxRecords: 2);
      final older = DateTime(2026, 8, 1);
      final newer = DateTime(2026, 8, 2);

      await store.record(
        BackupRecord(
          type: BackupRecordType.json,
          fileName: 'old.json',
          createdAt: older,
        ),
      );
      await store.record(
        BackupRecord(
          type: BackupRecordType.encrypted,
          fileName: 'new.hdbak',
          createdAt: newer,
        ),
      );
      await store.record(
        BackupRecord(
          type: BackupRecordType.pdf,
          fileName: 'report.pdf',
          createdAt: DateTime(2026, 8, 3),
        ),
      );

      final records = await store.load();

      expect(records, hasLength(2));
      expect(records.first.fileName, 'report.pdf');
      expect(records.last.fileName, 'new.hdbak');
    },
  );

  test('bỏ qua metadata hỏng nhưng vẫn giữ dòng hợp lệ', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      BackupCatalogStore.storageKey,
      jsonEncode([
        BackupRecord(
          type: BackupRecordType.csv,
          fileName: 'data.csv',
          createdAt: DateTime(2026, 8, 1),
        ).toJson(),
        {'type': 'unknown', 'fileName': 'broken', 'createdAt': 'invalid'},
      ]),
    );

    final records = await const BackupCatalogStore().load();

    expect(records, hasLength(1));
    expect(records.single.type, BackupRecordType.csv);
  });

  test('prune xóa metadata quá hạn nhưng không đụng file người dùng', () async {
    final store = const BackupCatalogStore();
    await store.record(
      BackupRecord(
        type: BackupRecordType.json,
        fileName: 'old.json',
        createdAt: DateTime.now().subtract(const Duration(days: 120)),
      ),
    );
    await store.record(
      BackupRecord(
        type: BackupRecordType.encrypted,
        fileName: 'current.hdbak',
        createdAt: DateTime.now(),
      ),
    );

    await store.prune(retention: const Duration(days: 90));

    final records = await store.load();
    expect(records, hasLength(1));
    expect(records.single.fileName, 'current.hdbak');
  });

  test('keeps backup metadata isolated by account scope', () async {
    const userOne = BackupCatalogStore(scope: 'user-1');
    const userTwo = BackupCatalogStore(scope: 'user-2');

    await userOne.record(
      BackupRecord(
        type: BackupRecordType.encrypted,
        fileName: 'private.hdbak',
        createdAt: DateTime(2026, 8, 1),
      ),
    );

    expect(await userTwo.load(), isEmpty);
    expect((await userOne.load()).single.fileName, 'private.hdbak');
  });

  test(
    'clearAll removes scoped metadata without touching legacy or another account',
    () async {
      const legacy = BackupCatalogStore();
      const userOne = BackupCatalogStore(scope: 'user-1');
      const userTwo = BackupCatalogStore(scope: 'user-2');
      final record = BackupRecord(
        type: BackupRecordType.encrypted,
        fileName: 'private.hdbak',
        createdAt: DateTime(2026, 8, 1),
      );

      await legacy.record(record);
      await userOne.record(record);
      await userTwo.record(record);
      await userOne.clearAll();

      expect((await legacy.load()).single.fileName, 'private.hdbak');
      expect(await userOne.load(), isEmpty);
      expect((await userTwo.load()).single.fileName, 'private.hdbak');

      await userOne.clearAll(includeLegacy: true);
      expect(await legacy.load(), isEmpty);
    },
  );
}
