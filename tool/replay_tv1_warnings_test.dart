import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/constants/app_constants.dart';
import 'package:hoadon_insight/features/ingestion/data/ai_extraction_client.dart';
import 'package:hoadon_insight/features/ingestion/domain/extraction.dart';
import 'package:hoadon_insight/features/ingestion/domain/invoice_validator.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  test('replays TV1 OCR results and measures total warnings', () {
    final directory = Directory('artifacts/tv1');
    final gold = {
      for (final row in _rows(File('${directory.path}/sample.jsonl')))
        row['image_id']: row['total_key'],
    };
    final files = directory
        .listSync()
        .whereType<File>()
        .where((file) => RegExp(r'/b1_.*\.jsonl$').hasMatch(file.path))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final predictions = <Object?, Map<String, dynamic>>{};
    for (final file in files) {
      for (final row in _rows(file)) {
        final id = row['image_id'];
        if (gold.containsKey(id) && row['invoice'] is Map<String, dynamic>) {
          predictions.putIfAbsent(id, () => row['invoice'] as Map<String, dynamic>);
        }
      }
    }
    expect(predictions.keys, unorderedEquals(gold.keys));
    final parser = AiExtractionClient(enabled: false);
    final input = ExtractionInput(
      bytes: Uint8List(0),
      fileName: 'replay.jpg',
      sourceType: InvoiceSourceType.imageOcr,
    );
    bool warns(Map<String, dynamic> invoice) {
      final value = parser.parseResponse({
        'invoice': invoice,
        'evidence': [
          {'field': 'totalMinor', 'value': '${invoice['totalMinor']}', 'confidence': 0.75},
        ],
      }, input).invoice;
      return const InvoiceValidator()
          .applyRuleConfidence(value)
          .evidence
          .single
          .confidence < 0.75;
    }

    var correct = 0;
    var falseAlarms = 0;
    var actualErrorsDetected = 0;
    var injectedCases = 0;
    var injectedDetected = 0;
    for (final entry in predictions.entries) {
      final invoice = entry.value;
      final total = invoice['totalMinor'] as int;
      final flagged = warns(invoice);
      if (total.toString() != gold[entry.key]) {
        if (flagged) actualErrorsDetected++;
        continue;
      }
      correct++;
      if (flagged) {
        falseAlarms++;
        continue;
      }
      injectedCases++;
      final altered = {...invoice, 'totalMinor': total + 10 * AppConstants.moneyToleranceMinor};
      if (warns(altered)) injectedDetected++;
    }
    expect(injectedCases, greaterThan(0));
    // The replay script reports its result on stdout on purpose.
    // ignore: avoid_print
    print(jsonEncode({
      'correct_total': correct,
      'warnings_on_correct_total': falseAlarms,
      'actual_wrong_total': predictions.length - correct,
      'actual_errors_detected': actualErrorsDetected,
      'injected_cases': injectedCases,
      'injected_detected': injectedDetected,
    }));
  });
}

Iterable<Map<String, dynamic>> _rows(File file) => file
    .readAsLinesSync()
    .where((line) => line.trim().isNotEmpty)
    .map((line) => jsonDecode(line) as Map<String, dynamic>);
