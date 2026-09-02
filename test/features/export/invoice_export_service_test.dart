import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/export/application/invoice_export_service.dart';
import 'package:hoadon_insight/features/export/domain/backup_provider.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  final invoice = InvoiceEntity(
    id: 'invoice-1',
    sellerName: 'Cửa hàng, Một',
    sellerTaxCode: '0123',
    invoiceNumber: 'HD-01',
    invoiceSymbol: 'AA/26E',
    issuedAt: DateTime(2026, 8, 30),
    currencyCode: 'VND',
    subtotalMinor: 100000,
    taxMinor: 10000,
    totalMinor: 110000,
    sourceType: InvoiceSourceType.xml,
    sourceHash: 'hash',
    status: InvoiceStatus.confirmed,
    categoryId: 'food',
    createdAt: DateTime(2026, 8, 30),
    updatedAt: DateTime(2026, 8, 30),
    lines: const [
      InvoiceLineEntity(
        id: 'line-1',
        description: 'Cà phê "đặc biệt"',
        totalMinor: 110000,
      ),
    ],
  );

  test('exports complete invoice data as JSON', () {
    final decoded =
        jsonDecode(InvoiceExportFormatter.toJson([invoice]))
            as Map<String, dynamic>;
    final exported = (decoded['invoices'] as List).single as Map;

    expect(decoded['format'], 'hoadon-insight.invoice-export');
    expect(decoded['checksumSha256'], hasLength(64));
    expect(exported['sellerName'], 'Cửa hàng, Một');
    expect((exported['lines'] as List).length, 1);
    expect((exported['evidence'] as List), isEmpty);
  });

  test('escapes CSV cells and includes the invoice summary', () {
    final csv = InvoiceExportFormatter.toCsv([invoice]);

    expect(csv, startsWith('\uFEFFid,seller_name'));
    expect(csv, contains('"Cửa hàng, Một"'));
    expect(csv, contains('Cà phê'));
    expect(csv, contains('invoice-1'));
    expect(csv, contains(',1,"'));
  });

  test('builds a local PDF report with summary and invoice rows', () {
    final bytes = InvoiceReportPdfFormatter.toPdf(
      invoices: [invoice],
      dashboard: const DashboardSnapshot(
        monthKey: '2026-08',
        totalMinor: 110000,
        invoiceCount: 1,
        categoryTotals: {'food': 110000},
        dailyTotals: {30: 110000},
        budgetLimitMinor: 200000,
        previousMonthTotalMinor: 90000,
      ),
      categories: const [
        CategoryEntity(
          id: 'food',
          name: 'Ăn uống',
          iconName: 'restaurant',
          colorValue: 0xFF0F766E,
        ),
      ],
    );
    final raw = latin1.decode(bytes);

    expect(raw, startsWith('%PDF-1.4'));
    expect(raw, contains('BAO CAO CHI TIEU THAM KHAO'));
    expect(raw, contains('Cua hang, Mot'));
    expect(raw, contains('110.000'));
    expect(raw, contains('VND'));
    expect(raw, endsWith('%%EOF\n'));
  });

  test('routes file artifacts through the backup provider boundary', () async {
    final provider = _FakeBackupProvider();

    await InvoiceExportService(provider: provider).exportJson([invoice]);

    expect(provider.lastArtifact?.type, BackupArtifactType.json);
    expect(provider.lastArtifact?.extension, 'json');
    expect(provider.lastArtifact?.bytes, isNotEmpty);
  });
}

class _FakeBackupProvider implements BackupProvider {
  BackupArtifact? lastArtifact;

  @override
  String get id => 'test';

  @override
  bool get isConfigured => true;

  @override
  Future<Uri?> save(BackupArtifact artifact) async {
    lastArtifact = artifact;
    return Uri.parse('memory://backup');
  }
}
