import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/export/application/encrypted_backup_service.dart';
import 'package:hoadon_insight/features/export/application/invoice_export_service.dart';
import 'package:hoadon_insight/features/export/application/invoice_restore_service.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  final invoice = InvoiceEntity(
    id: 'invoice-restore',
    sellerName: 'Cửa hàng Restore',
    currencyCode: 'VND',
    subtotalMinor: 90000,
    taxMinor: 10000,
    totalMinor: 100000,
    sourceType: InvoiceSourceType.xml,
    sourceHash: 'restore-hash',
    status: InvoiceStatus.confirmed,
    categoryId: 'unknown-category',
    notes: 'Ghi chú cần giữ',
    tags: const ['công việc', 'Q3'],
    createdAt: DateTime(2026, 8, 30),
    updatedAt: DateTime(2026, 8, 30),
    lines: const [
      InvoiceLineEntity(
        id: 'line-restore',
        description: 'Dịch vụ',
        totalMinor: 100000,
      ),
    ],
  );

  test('previews valid invoices and maps unknown category to other', () {
    final preview = InvoiceRestoreParser.parse(
      InvoiceExportFormatter.toJson([invoice]),
      fileName: 'backup.json',
      categoryIds: const {'food', 'other'},
    );

    expect(preview.totalCount, 1);
    expect(preview.readyCount, 1);
    expect(preview.duplicateCount, 0);
    expect(preview.invoices.single.categoryId, 'other');
    expect(preview.invoices.single.notes, 'Ghi chú cần giữ');
    expect(preview.invoices.single.tags, ['công việc', 'Q3']);
    expect(preview.invoices.single.lines.single.id, 'line-restore');
  });

  test('skips duplicate ids and source hashes', () {
    final second = invoice.copyWith(
      sellerName: 'Trùng hash',
      sourceHash: invoice.sourceHash,
    );
    final payload =
        jsonDecode(InvoiceExportFormatter.toJson([invoice, second]))
            as Map<String, dynamic>;
    // Simulate a legacy export while exercising duplicate detection.
    payload.remove('checksumSha256');
    final entries = payload['invoices'] as List;
    (entries[1] as Map<String, dynamic>)['id'] = 'another-id';

    final preview = InvoiceRestoreParser.parse(
      jsonEncode(payload),
      fileName: 'backup.json',
      existingIds: const {'invoice-restore'},
    );
    expect(preview.readyCount, 1);
    expect(preview.duplicateCount, 1);
  });

  test('reports invalid entries without rejecting the complete backup', () {
    final payload =
        jsonDecode(InvoiceExportFormatter.toJson([invoice]))
            as Map<String, dynamic>;
    // Simulate a legacy export while exercising per-entry validation.
    payload.remove('checksumSha256');
    (payload['invoices'] as List).add({'id': 'broken'});

    final preview = InvoiceRestoreParser.parse(
      jsonEncode(payload),
      fileName: 'backup.json',
    );
    expect(preview.readyCount, 1);
    expect(preview.invalidCount, 1);
    expect(preview.issues.single, contains('sellerName'));
  });

  test('rejects unsupported backup formats', () {
    expect(
      () => InvoiceRestoreParser.parse(
        '{"format":"unknown","version":1,"invoices":[]}',
        fileName: 'backup.json',
      ),
      throwsFormatException,
    );
  });

  test('rejects a backup with a changed checksum', () {
    final payload =
        jsonDecode(InvoiceExportFormatter.toJson([invoice]))
            as Map<String, dynamic>;
    (payload['invoices'] as List).first['totalMinor'] = 999;

    expect(
      () => InvoiceRestoreParser.parse(
        jsonEncode(payload),
        fileName: 'tampered.json',
      ),
      throwsFormatException,
    );
  });

  test('previews encrypted cloud bytes after requesting password', () async {
    final plaintext = InvoiceExportFormatter.toJson([invoice]);
    final encrypted = await const EncryptedBackupService().encrypt(
      plaintext,
      'mat-khau-an-toan',
    );

    final preview = await const InvoiceRestoreService().previewBytes(
      bytes: Uint8List.fromList(utf8.encode(encrypted)),
      fileName: 'cloud.hdbak',
      categoryIds: const {'other'},
      requestPassword: () async => 'mat-khau-an-toan',
    );

    expect(preview, isNotNull);
    expect(preview!.readyCount, 1);
    expect(preview.fileName, 'cloud.hdbak');
    expect(preview.invoices.single.categoryId, 'other');
  });

  test('rejects empty and malformed cloud backup bytes', () async {
    final service = const InvoiceRestoreService();

    await expectLater(
      service.previewBytes(bytes: Uint8List(0), fileName: 'empty.hdbak'),
      throwsFormatException,
    );
    await expectLater(
      service.previewBytes(
        bytes: Uint8List.fromList(const [0xFF, 0xFE]),
        fileName: 'invalid.hdbak',
      ),
      throwsFormatException,
    );
  });
}
