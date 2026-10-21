import '../../invoices/domain/invoice_models.dart';

enum BudgetAlertLevel { none, approaching, exceeded }

class BudgetAlertDecision {
  const BudgetAlertDecision({
    required this.level,
    required this.monthKey,
    this.categories = const [],
  });

  final BudgetAlertLevel level;
  final String monthKey;

  /// Danh mục gây ra cảnh báo ở [level], vượt/gần chạm nhiều nhất trước.
  final List<CategoryBudgetStatus> categories;

  bool get shouldNotify => level != BudgetAlertLevel.none;

  /// Đổi khi có thêm danh mục chạm ngưỡng để người dùng được báo lại.
  String get deduplicationKey {
    final ids = categories.map((item) => item.categoryId).toList()..sort();
    return '$monthKey:${level.name}:${ids.join(',')}';
  }
}

/// Chỉ cảnh báo theo từng danh mục có hạn mức; không cảnh báo theo tổng tháng.
class BudgetAlertPolicy {
  const BudgetAlertPolicy({this.approachingThreshold = 0.8});

  final double approachingThreshold;

  BudgetAlertDecision evaluate(DashboardSnapshot snapshot) {
    final exceeded = snapshot.overBudgetCategories;
    if (exceeded.isNotEmpty) {
      return BudgetAlertDecision(
        level: BudgetAlertLevel.exceeded,
        monthKey: snapshot.monthKey,
        categories: exceeded,
      );
    }
    final approaching =
        snapshot.categoryBudgets
            .where((item) => item.progress >= approachingThreshold)
            .toList()
          ..sort((a, b) => b.progress.compareTo(a.progress));
    return BudgetAlertDecision(
      level: approaching.isEmpty
          ? BudgetAlertLevel.none
          : BudgetAlertLevel.approaching,
      monthKey: snapshot.monthKey,
      categories: approaching,
    );
  }
}
