import 'package:flutter/foundation.dart';

enum InvoiceSourceType { xml, pdfText, imageOcr, manual }

enum InvoiceStatus {
  queued,
  extracting,
  validating,
  needsReview,
  confirmed,
  failed,
}

enum InvoiceSyncState { localOnly, pending, synced, conflict }

@immutable
class InvoiceLineEntity {
  const InvoiceLineEntity({
    required this.id,
    required this.description,
    required this.totalMinor,
    this.quantity,
    this.unitPriceMinor,
    this.categoryId,
  });

  final String id;
  final String description;
  final double? quantity;
  final int? unitPriceMinor;
  final int totalMinor;
  final String? categoryId;

  InvoiceLineEntity copyWith({String? categoryId}) => InvoiceLineEntity(
    id: id,
    description: description,
    quantity: quantity,
    unitPriceMinor: unitPriceMinor,
    totalMinor: totalMinor,
    categoryId: categoryId ?? this.categoryId,
  );
}

@immutable
class FieldEvidenceEntity {
  const FieldEvidenceEntity({
    required this.id,
    required this.fieldName,
    required this.normalizedValue,
    required this.source,
    required this.confidence,
    this.rawValue,
    this.correctedByUser = false,
  });

  final String id;
  final String fieldName;
  final String? rawValue;
  final String normalizedValue;
  final InvoiceSourceType source;
  final double confidence;
  final bool correctedByUser;
}

@immutable
class InvoiceEntity {
  const InvoiceEntity({
    required this.id,
    required this.sellerName,
    required this.currencyCode,
    required this.subtotalMinor,
    required this.taxMinor,
    required this.totalMinor,
    required this.sourceType,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.cloudId,
    this.invoiceSymbol,
    this.issuedAt,
    this.sourceHash,
    this.categoryId,
    this.notes,
    this.tags = const [],
    this.confirmedAt,
    this.syncState = InvoiceSyncState.localOnly,
    this.revision = 1,
    this.deletedAt,
    this.lines = const [],
    this.evidence = const [],
    this.discountMinor = 0,
  });

  final String id;
  final String? cloudId;
  final String sellerName;
  final String? invoiceSymbol;
  final DateTime? issuedAt;
  final String currencyCode;
  final int subtotalMinor;
  final int taxMinor;

  /// Tổng giảm giá riêng ở cấp hóa đơn; giữ 0 khi hóa đơn không in khoản này.
  final int discountMinor;
  final int totalMinor;
  final InvoiceSourceType sourceType;
  final String? sourceHash;
  final InvoiceStatus status;
  final String? categoryId;
  final String? notes;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? confirmedAt;
  final InvoiceSyncState syncState;
  final int revision;
  final DateTime? deletedAt;
  final List<InvoiceLineEntity> lines;
  final List<FieldEvidenceEntity> evidence;

  bool get requiresReview => status == InvoiceStatus.needsReview;
  bool get isDeleted => deletedAt != null;

  InvoiceEntity copyWith({
    String? sellerName,
    String? cloudId,
    String? invoiceSymbol,
    DateTime? issuedAt,
    String? currencyCode,
    int? subtotalMinor,
    int? taxMinor,
    int? discountMinor,
    int? totalMinor,
    InvoiceSourceType? sourceType,
    String? sourceHash,
    InvoiceStatus? status,
    String? categoryId,
    String? notes,
    bool clearNotes = false,
    List<String>? tags,
    DateTime? updatedAt,
    DateTime? confirmedAt,
    InvoiceSyncState? syncState,
    int? revision,
    DateTime? deletedAt,
    List<InvoiceLineEntity>? lines,
    List<FieldEvidenceEntity>? evidence,
  }) {
    return InvoiceEntity(
      id: id,
      cloudId: cloudId ?? this.cloudId,
      sellerName: sellerName ?? this.sellerName,
      invoiceSymbol: invoiceSymbol ?? this.invoiceSymbol,
      issuedAt: issuedAt ?? this.issuedAt,
      currencyCode: currencyCode ?? this.currencyCode,
      subtotalMinor: subtotalMinor ?? this.subtotalMinor,
      taxMinor: taxMinor ?? this.taxMinor,
      discountMinor: discountMinor ?? this.discountMinor,
      totalMinor: totalMinor ?? this.totalMinor,
      sourceType: sourceType ?? this.sourceType,
      sourceHash: sourceHash ?? this.sourceHash,
      status: status ?? this.status,
      categoryId: categoryId ?? this.categoryId,
      notes: clearNotes ? null : notes ?? this.notes,
      tags: tags ?? this.tags,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      syncState: syncState ?? this.syncState,
      revision: revision ?? this.revision,
      deletedAt: deletedAt ?? this.deletedAt,
      lines: lines ?? this.lines,
      evidence: evidence ?? this.evidence,
    );
  }
}

@immutable
class InvoiceConflictEntity {
  const InvoiceConflictEntity({
    required this.local,
    required this.remote,
    required this.detectedAt,
  });

  final InvoiceEntity local;
  final InvoiceEntity remote;
  final DateTime detectedAt;
}

enum CategoryKind {
  expense,
  income;

  static CategoryKind fromValue(Object? value) {
    if (value == null || value == 'expense') return CategoryKind.expense;
    if (value == 'income') return CategoryKind.income;
    throw const FormatException('Loại danh mục không hợp lệ.');
  }
}

const unclassifiedIncomeCategoryId = 'income_uncategorized';

@immutable
class CategoryEntity {
  const CategoryEntity({
    required this.id,
    required this.name,
    required this.iconName,
    required this.colorValue,
    this.isSystem = true,
    this.kind = CategoryKind.expense,
  });

  final String id;
  final String name;
  final String iconName;
  final int colorValue;
  final bool isSystem;
  final CategoryKind kind;
}

@immutable
class MerchantRuleEntity {
  const MerchantRuleEntity({
    required this.normalizedMerchant,
    required this.categoryId,
    required this.updatedAt,
  });

  final String normalizedMerchant;
  final String categoryId;
  final DateTime updatedAt;
}

@immutable
class BudgetEntity {
  const BudgetEntity({
    required this.id,
    required this.monthKey,
    required this.categoryId,
    required this.limitMinor,
  });

  final String id;
  final String monthKey;
  final String categoryId;
  final int limitMinor;
}

@immutable
class CategoryBudgetStatus {
  const CategoryBudgetStatus({
    required this.categoryId,
    required this.categoryName,
    required this.limitMinor,
    required this.spentMinor,
  });

  final String categoryId;
  final String categoryName;
  final int limitMinor;
  final int spentMinor;

  bool get isOver => limitMinor > 0 && spentMinor > limitMinor;
  int get overMinor => isOver ? spentMinor - limitMinor : 0;
  double get progress => limitMinor <= 0 ? 0 : spentMinor / limitMinor;
}

@immutable
class DashboardSnapshot {
  const DashboardSnapshot({
    required this.monthKey,
    required this.totalMinor,
    required this.invoiceCount,
    required this.categoryTotals,
    required this.dailyTotals,
    required this.budgetLimitMinor,
    this.previousMonthTotalMinor = 0,
    this.categoryBudgets = const [],
  });

  final String monthKey;
  final int totalMinor;
  final int invoiceCount;
  final Map<String, int> categoryTotals;
  final Map<int, int> dailyTotals;
  final int budgetLimitMinor;
  final int previousMonthTotalMinor;

  /// Danh mục có hạn mức > 0 trong tháng; danh mục không có ở đây là không
  /// giới hạn.
  final List<CategoryBudgetStatus> categoryBudgets;

  double get budgetProgress =>
      budgetLimitMinor <= 0 ? 0 : totalMinor / budgetLimitMinor;

  /// Danh mục vượt hạn mức, vượt nhiều nhất trước.
  List<CategoryBudgetStatus> get overBudgetCategories =>
      categoryBudgets.where((item) => item.isOver).toList()
        ..sort((a, b) => b.overMinor.compareTo(a.overMinor));

  double? get monthOverMonthChange => previousMonthTotalMinor <= 0
      ? null
      : (totalMinor - previousMonthTotalMinor) / previousMonthTotalMinor;
}

@immutable
class RecurringExpenseInsight {
  const RecurringExpenseInsight({
    required this.merchant,
    required this.occurrences,
    required this.averageMinor,
    required this.averageIntervalDays,
    required this.cadenceLabel,
  });

  final String merchant;
  final int occurrences;
  final int averageMinor;
  final double averageIntervalDays;
  final String cadenceLabel;
}

@immutable
class SpendingInsights {
  const SpendingInsights({
    required this.monthKey,
    required this.forecastTotalMinor,
    required this.currentTotalMinor,
    required this.recurringExpenses,
    this.anomalies = const [],
  });

  final String monthKey;
  final int forecastTotalMinor;
  final int currentTotalMinor;
  final List<RecurringExpenseInsight> recurringExpenses;
  final List<SpendingAnomaly> anomalies;
}

enum SpendingAnomalySeverity { warning, high }

@immutable
class SpendingAnomaly {
  const SpendingAnomaly({
    required this.invoiceId,
    required this.merchant,
    required this.amountMinor,
    required this.baselineMinor,
    required this.ratio,
    required this.severity,
  });

  final String invoiceId;
  final String merchant;
  final int amountMinor;
  final int baselineMinor;
  final double ratio;
  final SpendingAnomalySeverity severity;

  String get explanation =>
      'Cao hơn khoảng ${ratio.toStringAsFixed(1)} lần mức trung bình trước đây';
}
