import '../../income/data/income_repository.dart';
import '../../invoices/domain/invoice_models.dart';

/// Local calendar boundaries. The end is exclusive, also across DST changes.
class TransactionPeriod {
  TransactionPeriod.day(DateTime date)
    : start = DateTime(date.year, date.month, date.day),
      end = DateTime(date.year, date.month, date.day + 1);
  TransactionPeriod.month(DateTime date)
    : start = DateTime(date.year, date.month),
      end = DateTime(date.year, date.month + 1);
  TransactionPeriod.year(int year)
    : start = DateTime(year),
      end = DateTime(year + 1);
  final DateTime start;
  final DateTime end;
  bool contains(DateTime value) {
    final date = value.toLocal();
    return !date.isBefore(start) && date.isBefore(end);
  }
}

class PeriodTransactions {
  PeriodTransactions({
    required this.period,
    required Iterable<IncomeEntry> incomes,
    required Iterable<InvoiceEntity> expenses,
  }) : incomes = List.unmodifiable(
         incomes.where((e) => period.contains(e.receivedAt)),
       ),
       expenses = List.unmodifiable(
         expenses.where(
           (e) =>
               !e.isDeleted &&
               e.status == InvoiceStatus.confirmed &&
               period.contains(e.issuedAt ?? e.createdAt),
         ),
       );
  final TransactionPeriod period;
  final List<IncomeEntry> incomes;
  final List<InvoiceEntity> expenses;
  int get income => incomes.fold(0, (total, e) => total + e.amountMinor);
  int get expense => expenses.fold(0, (total, e) => total + e.totalMinor);
  int get net => income - expense;
  Map<String, int> categories(bool income) {
    final result = <String, int>{};
    void add(String id, int value) =>
        result.update(id, (v) => v + value, ifAbsent: () => value);
    if (income) {
      for (final entry in incomes) {
        add(entry.categoryId, entry.amountMinor);
      }
    } else {
      for (final entry in expenses) {
        add(entry.categoryId ?? 'other', entry.totalMinor);
      }
    }
    return result;
  }

  Map<int, int> get dailyExpenses {
    final result = <int, int>{};
    for (final e in expenses) {
      final day = (e.issuedAt ?? e.createdAt).toLocal().day;
      result.update(day, (v) => v + e.totalMinor, ifAbsent: () => e.totalMinor);
    }
    return result;
  }
}
