import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/dashboard/domain/transaction_period.dart';
import 'package:hoadon_insight/features/income/data/income_repository.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  test('local boundaries include leap days and exclude next month/year', () {
    final february = TransactionPeriod.month(DateTime(2024, 2));
    expect(february.contains(DateTime(2024, 2, 29, 23, 59)), isTrue);
    expect(february.contains(DateTime(2024, 3, 1)), isFalse);
    final year = TransactionPeriod.year(2026);
    expect(year.contains(DateTime(2026, 12, 31, 23, 59)), isTrue);
    expect(year.contains(DateTime(2027)), isFalse);
  });
  test(
    'net totals exclude drafts/deleted expenses and follow transaction date',
    () {
      final date = DateTime(2026, 9, 1);
      InvoiceEntity expense(
        String id,
        InvoiceStatus status, {
        DateTime? issuedAt,
        DateTime? deletedAt,
      }) => InvoiceEntity(
        id: id,
        sellerName: id,
        currencyCode: 'VND',
        subtotalMinor: 40000,
        taxMinor: 0,
        totalMinor: 40000,
        sourceType: InvoiceSourceType.manual,
        status: status,
        createdAt: date,
        updatedAt: date,
        issuedAt: issuedAt,
        deletedAt: deletedAt,
        categoryId: 'food',
      );
      final data = PeriodTransactions(
        period: TransactionPeriod.day(date),
        incomes: [
          IncomeEntry(
            id: 'salary',
            amountMinor: 100000,
            source: IncomeSource.manual,
            receivedAt: date,
            updatedAt: date,
          ),
        ],
        expenses: [
          expense('saved', InvoiceStatus.confirmed),
          expense('draft', InvoiceStatus.needsReview),
          expense('deleted', InvoiceStatus.confirmed, deletedAt: date),
          expense(
            'next',
            InvoiceStatus.confirmed,
            issuedAt: DateTime(2026, 9, 2),
          ),
        ],
      );
      expect(data.net, 60000);
      expect(data.categories(false), {'food': 40000});
      expect(data.dailyExpenses, {1: 40000});
    },
  );
}
