import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/constants/app_constants.dart';
import 'package:hoadon_insight/features/ingestion/data/pending_import_store.dart';

void main() {
  test('rejects malformed and path-traversal manifest entries', () {
    final valid = PendingImport.tryParse({
      'id': 'job-1',
      'fileName': 'invoice.xml',
      'diskName': 'stored.bin',
      'kind': 'document',
    });

    expect(valid, isNotNull);
    expect(
      PendingImport.tryParse({
        'id': 'job-2',
        'fileName': 'invoice.xml',
        'diskName': '../outside.bin',
        'kind': 'document',
      }),
      isNull,
    );
    expect(
      PendingImport.tryParse({
        'id': 'job-3',
        'fileName': 'invoice.xml',
        'diskName': 'C:outside.bin',
        'kind': 'document',
      }),
      isNull,
    );
    expect(
      PendingImport.tryParse({
        'id': 'job-4',
        'fileName': 'invoice.xml',
        'diskName': 'manifest.json',
        'kind': 'document',
      }),
      isNull,
    );
    expect(PendingImport.tryParse({'id': 'job-5'}), isNull);
    expect(
      PendingImport.tryParse({
        'id': 'job-6',
        'fileName': '../invoice.xml',
        'diskName': 'stored.bin',
        'kind': 'document',
      }),
      isNull,
    );
  });

  test('rejects invalid enqueue input before creating queue files', () async {
    final root = await Directory.systemTemp.createTemp('pending-import-test-');
    addTearDown(() => root.delete(recursive: true));
    final store = PendingImportStore(directoryProvider: () async => root);

    await expectLater(
      store.enqueue(
        bytes: Uint8List(AppConstants.maxImportBytes + 1),
        fileName: 'invoice.xml',
        kind: PendingImportKind.document,
      ),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      store.enqueue(
        bytes: Uint8List.fromList([1]),
        fileName: '../invoice.xml',
        kind: PendingImportKind.document,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await root.list().toList(), isEmpty);
  });

  test('rejects an empty queued file before reading it', () async {
    final root = await Directory.systemTemp.createTemp('pending-import-test-');
    addTearDown(() => root.delete(recursive: true));
    final store = PendingImportStore(directoryProvider: () async => root);
    final item = const PendingImport(
      id: 'job-1',
      fileName: 'invoice.xml',
      diskName: 'stored.bin',
      kind: PendingImportKind.document,
    );
    final path = await store.filePath(item);
    await File(path).writeAsBytes(const []);

    await expectLater(
      store.readBytes(item),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'clearAll keeps another account and clears legacy only when requested',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'pending-import-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      const firstScope = '22222222-2222-4222-8222-222222222222';
      const secondScope = '33333333-3333-4333-8333-333333333333';
      final legacy = PendingImportStore(directoryProvider: () async => root);
      final first = PendingImportStore(
        scope: firstScope,
        directoryProvider: () async => root,
      );
      final second = PendingImportStore(
        scope: secondScope,
        directoryProvider: () async => root,
      );

      Future<void> enqueue(PendingImportStore store) async {
        await store.enqueue(
          bytes: Uint8List.fromList([1]),
          fileName: 'invoice.xml',
          kind: PendingImportKind.document,
        );
      }

      await enqueue(legacy);
      await enqueue(first);
      await enqueue(second);
      await first.clearAll();

      expect(await legacy.list(), hasLength(1));
      expect(await first.list(), isEmpty);
      expect(await second.list(), hasLength(1));

      await first.clearAll(includeLegacy: true);
      expect(await legacy.list(), isEmpty);
    },
  );
}
