import '../../invoices/domain/invoice_models.dart';

class SpendingInsightEngine {
  const SpendingInsightEngine();

  SpendingInsights analyze({
    required Iterable<InvoiceEntity> invoices,
    required DateTime month,
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final monthStart = DateTime(month.year, month.month);
    final nextMonth = DateTime(month.year, month.month + 1);
    final confirmed = invoices
        .where(
          (invoice) =>
              invoice.status == InvoiceStatus.confirmed && !invoice.isDeleted,
        )
        .toList(growable: false);
    final currentTotal = confirmed
        .where((invoice) {
          final date = invoice.issuedAt ?? invoice.createdAt;
          return !date.isBefore(monthStart) && date.isBefore(nextMonth);
        })
        .fold<int>(0, (sum, invoice) => sum + invoice.totalMinor);

    final isCurrentMonth =
        reference.year == month.year && reference.month == month.month;
    final daysInMonth = nextMonth.subtract(const Duration(days: 1)).day;
    final elapsedDays = isCurrentMonth
        ? reference.day.clamp(1, daysInMonth)
        : daysInMonth;
    final forecast = isCurrentMonth
        ? (currentTotal / elapsedDays * daysInMonth).round()
        : currentTotal;

    return SpendingInsights(
      monthKey: '${month.year}-${month.month.toString().padLeft(2, '0')}',
      forecastTotalMinor: forecast,
      currentTotalMinor: currentTotal,
      recurringExpenses: _recurring(confirmed),
      anomalies: _anomalies(confirmed, month),
    );
  }

  List<SpendingAnomaly> _anomalies(
    List<InvoiceEntity> invoices,
    DateTime month,
  ) {
    final monthStart = DateTime(month.year, month.month);
    final nextMonth = DateTime(month.year, month.month + 1);
    final historical = <String, List<InvoiceEntity>>{};
    final current = invoices.where((invoice) {
      final date = invoice.issuedAt ?? invoice.createdAt;
      return !date.isBefore(monthStart) && date.isBefore(nextMonth);
    });
    for (final invoice in invoices) {
      final date = invoice.issuedAt ?? invoice.createdAt;
      if (date.isBefore(monthStart)) {
        historical.putIfAbsent(_merchantKey(invoice), () => []).add(invoice);
      }
    }

    final result = <SpendingAnomaly>[];
    for (final invoice in current) {
      final history = historical[_merchantKey(invoice)];
      if (history == null || history.length < 3) continue;
      final average =
          history.fold<int>(0, (sum, item) => sum + item.totalMinor) /
          history.length;
      if (average <= 0) continue;
      final ratio = invoice.totalMinor / average;
      if (ratio < 1.8 || invoice.totalMinor - average < 100000) continue;
      result.add(
        SpendingAnomaly(
          invoiceId: invoice.id,
          merchant: invoice.sellerName,
          amountMinor: invoice.totalMinor,
          baselineMinor: average.round(),
          ratio: ratio,
          severity: ratio >= 3
              ? SpendingAnomalySeverity.high
              : SpendingAnomalySeverity.warning,
        ),
      );
    }
    result.sort((left, right) => right.ratio.compareTo(left.ratio));
    return result.take(5).toList(growable: false);
  }

  String _merchantKey(InvoiceEntity invoice) =>
      invoice.sellerName.trim().toLowerCase();

  List<RecurringExpenseInsight> _recurring(List<InvoiceEntity> invoices) {
    final grouped = <String, List<InvoiceEntity>>{};
    for (final invoice in invoices) {
      final merchant = invoice.sellerName.trim().toLowerCase();
      if (merchant.isEmpty) continue;
      grouped.putIfAbsent(merchant, () => []).add(invoice);
    }

    final result = <RecurringExpenseInsight>[];
    for (final entry in grouped.entries) {
      final items = entry.value
        ..sort(
          (left, right) => (left.issuedAt ?? left.createdAt).compareTo(
            right.issuedAt ?? right.createdAt,
          ),
        );
      if (items.length < 3) continue;
      final intervals = <int>[];
      for (var index = 1; index < items.length; index++) {
        intervals.add(
          (items[index].issuedAt ?? items[index].createdAt)
              .difference(
                items[index - 1].issuedAt ?? items[index - 1].createdAt,
              )
              .inDays
              .abs(),
        );
      }
      final averageInterval =
          intervals.fold<int>(0, (sum, value) => sum + value) /
          intervals.length;
      final averageAmount =
          items.fold<int>(0, (sum, item) => sum + item.totalMinor) /
          items.length;
      final maxAmountDelta = items
          .map((item) => (item.totalMinor - averageAmount).abs())
          .fold<double>(0, (max, value) => value > max ? value : max);
      final intervalTolerance = averageInterval * 0.4 + 2;
      final stableInterval = intervals.every(
        (value) => (value - averageInterval).abs() <= intervalTolerance,
      );
      final stableAmount = averageAmount <= 0
          ? false
          : maxAmountDelta / averageAmount <= 0.3;
      if (!stableInterval || !stableAmount) continue;

      final cadence = switch (averageInterval) {
        >= 5 && <= 10 => 'Hàng tuần',
        >= 20 && <= 40 => 'Hàng tháng',
        >= 70 && <= 110 => 'Hàng quý',
        _ => 'Định kỳ',
      };
      result.add(
        RecurringExpenseInsight(
          merchant: items.first.sellerName,
          occurrences: items.length,
          averageMinor: averageAmount.round(),
          averageIntervalDays: averageInterval,
          cadenceLabel: cadence,
        ),
      );
    }
    result.sort(
      (left, right) => right.averageMinor.compareTo(left.averageMinor),
    );
    return result;
  }
}
