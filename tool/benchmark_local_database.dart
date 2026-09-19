import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/database/app_database.dart';
import 'package:hoadon_insight/features/invoices/data/drift_invoice_repository.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_filters.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  test('benchmarks local database search at scale', () async {
    for (final size in [10_000, 50_000, 100_000]) {
      await _benchmark(size);
    }
  });
}

Future<void> _benchmark(int size) async {
  final database = AppDatabase(NativeDatabase.memory());
  try {
    final now = DateTime.utc(2026, 9, 17);
    final insertTimer = Stopwatch()..start();
    final rows = List<InvoicesCompanion>.generate(size, (index) {
      final searchable = index % 10 == 0
          ? 'benchmark grocery'
          : 'merchant $index';
      return InvoicesCompanion.insert(
        id: 'benchmark-$index',
        sellerName: 'Merchant $index',
        currencyCode: const Value('VND'),
        totalMinor: Value(100_000 + index),
        sourceType: InvoiceSourceType.manual.name,
        status: InvoiceStatus.confirmed.name,
        searchText: Value(searchable),
        createdAt: now.subtract(Duration(seconds: index)),
        updatedAt: now.subtract(Duration(seconds: index)),
      );
    });
    await database.batch((batch) {
      batch.insertAll(database.invoices, rows);
    });
    insertTimer.stop();

    final repository = DriftInvoiceRepository(database);
    const filter = InvoiceFilter(query: 'benchmark grocery');
    await repository.fetchInvoicePage(filter: filter, limit: 50);
    final searchTimes = <int>[];
    for (var run = 0; run < 7; run++) {
      final searchTimer = Stopwatch()..start();
      final page = await repository.fetchInvoicePage(filter: filter, limit: 50);
      searchTimer.stop();
      searchTimes.add(searchTimer.elapsedMicroseconds);
      if (page.items.length != 50 || !page.hasMore) {
        throw StateError('Benchmark query returned an unexpected page.');
      }
    }
    searchTimes.sort();
    final p95Index = ((searchTimes.length * 95 + 99) ~/ 100) - 1;
    stdout.writeln(
      jsonEncode({
        'rows': size,
        'insert_ms': insertTimer.elapsedMilliseconds,
        'search_p95_ms': searchTimes[p95Index] / 1_000,
        'decision_threshold_ms': 150,
      }),
    );
  } finally {
    await database.close();
  }
}
