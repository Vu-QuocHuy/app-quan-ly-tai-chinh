import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/insights/domain/spending_insight_engine.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  test('forecasts current month and detects stable recurring expense', () {
    final invoices = [
      _invoice('jan', DateTime(2026, 1, 5), 200000),
      _invoice('feb', DateTime(2026, 2, 5), 205000),
      _invoice('mar', DateTime(2026, 3, 5), 195000),
      _invoice('aug', DateTime(2026, 8, 15), 1500000, seller: 'Khác'),
    ];

    final result = const SpendingInsightEngine().analyze(
      invoices: invoices,
      month: DateTime(2026, 8),
      now: DateTime(2026, 8, 15),
    );

    expect(result.currentTotalMinor, 1500000);
    expect(result.forecastTotalMinor, 3100000);
    expect(result.recurringExpenses, hasLength(1));
    expect(result.recurringExpenses.single.cadenceLabel, 'Hàng tháng');
    expect(result.recurringExpenses.single.merchant, 'Nhà mạng');
  });

  test('flags a current merchant amount above its historical baseline', () {
    final result = const SpendingInsightEngine().analyze(
      invoices: [
        _invoice('history-1', DateTime(2026, 1, 5), 200000),
        _invoice('history-2', DateTime(2026, 2, 5), 210000),
        _invoice('history-3', DateTime(2026, 3, 5), 190000),
        _invoice('spike', DateTime(2026, 8, 15), 900000),
      ],
      month: DateTime(2026, 8),
      now: DateTime(2026, 8, 15),
    );

    expect(result.anomalies, hasLength(1));
    expect(result.anomalies.single.invoiceId, 'spike');
    expect(result.anomalies.single.severity, SpendingAnomalySeverity.high);
    expect(result.anomalies.single.ratio, greaterThan(4));
  });
}

InvoiceEntity _invoice(
  String id,
  DateTime date,
  int total, {
  String seller = 'Nhà mạng',
}) {
  return InvoiceEntity(
    id: id,
    sellerName: seller,
    currencyCode: 'VND',
    subtotalMinor: total,
    taxMinor: 0,
    totalMinor: total,
    sourceType: InvoiceSourceType.manual,
    status: InvoiceStatus.confirmed,
    issuedAt: date,
    createdAt: date,
    updatedAt: date,
  );
}
