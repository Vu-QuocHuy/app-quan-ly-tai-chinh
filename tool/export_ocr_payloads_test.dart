import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/ingestion/data/receipt_image_optimizer.dart';

void main() {
  test('export exact app OCR payloads for a fixed benchmark sample', () async {
    final samplePath = Platform.environment['FINMI_BENCH_SAMPLE'];
    final outputPath = Platform.environment['FINMI_BENCH_PAYLOAD_DIR'];
    if (samplePath == null || outputPath == null) {
      throw StateError('Set FINMI_BENCH_SAMPLE and FINMI_BENCH_PAYLOAD_DIR.');
    }
    final output = Directory(outputPath)..createSync(recursive: true);
    final rows = File(samplePath).readAsLinesSync().where((line) => line.trim().isNotEmpty);
    final manifest = File('${output.path}/payload_manifest.jsonl').openWrite();
    var index = 0;
    for (final line in rows) {
      final row = jsonDecode(line) as Map<String, dynamic>;
      final source = File(row['image_path'] as String);
      final sourceBytes = await source.readAsBytes();
      if (sha256.convert(sourceBytes).toString() != row['source_sha256']) {
        throw StateError("Source image changed: ${row['image_id']}");
      }
      final extension = source.path.split('.').last.toLowerCase();
      final mimeType = switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
      final payload = await optimizeReceiptImageForOcr(
        sourceBytes, mimeType: mimeType,
      );
      final target = File('${output.path}/${index++}.payload');
      await target.writeAsBytes(payload.bytes);
      manifest.writeln(jsonEncode({
        'image_id': row['image_id'],
        'payload_path': target.absolute.path,
        'mime_type': payload.mimeType,
      }));
    }
    await manifest.close();
  });
}
