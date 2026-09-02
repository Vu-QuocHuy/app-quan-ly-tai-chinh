import 'package:flutter/foundation.dart';

import '../../../core/utils/month_utils.dart';
import '../../../core/utils/string_normalizer.dart';
import 'invoice_models.dart';

@immutable
class InvoiceFilter {
  const InvoiceFilter({
    this.query = '',
    this.monthKey,
    this.categoryId,
    this.status,
    this.sourceType,
    this.minTotalMinor,
    this.maxTotalMinor,
  });

  final String query;
  final String? monthKey;
  final String? categoryId;
  final InvoiceStatus? status;
  final InvoiceSourceType? sourceType;
  final int? minTotalMinor;
  final int? maxTotalMinor;

  bool get hasActiveFilters =>
      query.trim().isNotEmpty ||
      monthKey != null ||
      categoryId != null ||
      status != null ||
      sourceType != null ||
      minTotalMinor != null ||
      maxTotalMinor != null;

  List<InvoiceEntity> apply(Iterable<InvoiceEntity> invoices) {
    return invoices.where(matches).toList(growable: false);
  }

  bool matches(InvoiceEntity invoice) {
    final normalizedQuery = StringNormalizer.merchant(query);
    if (normalizedQuery.isNotEmpty) {
      final searchable = StringNormalizer.merchant(
        [
          invoice.sellerName,
          invoice.sellerTaxCode,
          invoice.invoiceNumber,
          invoice.invoiceSymbol,
          invoice.notes,
          ...invoice.tags,
        ].whereType<String>().join(' '),
      );
      if (!searchable.contains(normalizedQuery)) return false;
    }
    if (monthKey != null) {
      final date = invoice.issuedAt ?? invoice.createdAt;
      if (MonthUtils.key(date) != monthKey) return false;
    }
    if (categoryId != null && invoice.categoryId != categoryId) return false;
    if (status != null && invoice.status != status) return false;
    if (sourceType != null && invoice.sourceType != sourceType) return false;
    if (minTotalMinor != null && invoice.totalMinor < minTotalMinor!) {
      return false;
    }
    if (maxTotalMinor != null && invoice.totalMinor > maxTotalMinor!) {
      return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvoiceFilter &&
          query == other.query &&
          monthKey == other.monthKey &&
          categoryId == other.categoryId &&
          status == other.status &&
          sourceType == other.sourceType &&
          minTotalMinor == other.minTotalMinor &&
          maxTotalMinor == other.maxTotalMinor;

  @override
  int get hashCode => Object.hash(
    query,
    monthKey,
    categoryId,
    status,
    sourceType,
    minTotalMinor,
    maxTotalMinor,
  );
}

@immutable
class InvoiceListQuery {
  const InvoiceListQuery({required this.filter, this.limit = 50});

  final InvoiceFilter filter;
  final int limit;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvoiceListQuery &&
          filter == other.filter &&
          limit == other.limit;

  @override
  int get hashCode => Object.hash(filter, limit);
}

@immutable
class InvoicePageCursor {
  const InvoicePageCursor({required this.updatedAt, required this.id});

  final DateTime updatedAt;
  final String id;
}

@immutable
class InvoicePage {
  const InvoicePage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  final List<InvoiceEntity> items;
  final bool hasMore;
  final InvoicePageCursor? nextCursor;
}
