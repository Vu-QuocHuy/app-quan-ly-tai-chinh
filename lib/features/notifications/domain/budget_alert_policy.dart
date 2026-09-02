import '../../invoices/domain/invoice_models.dart';

enum BudgetAlertLevel { none, approaching, exceeded }

class BudgetAlertDecision {
  const BudgetAlertDecision({
    required this.level,
    required this.monthKey,
    required this.spentMinor,
    required this.limitMinor,
  });

  final BudgetAlertLevel level;
  final String monthKey;
  final int spentMinor;
  final int limitMinor;

  bool get shouldNotify => level != BudgetAlertLevel.none;
  String get deduplicationKey => '$monthKey:${level.name}';
}

class BudgetAlertPolicy {
  const BudgetAlertPolicy({this.approachingThreshold = 0.8});

  final double approachingThreshold;

  BudgetAlertDecision evaluate(DashboardSnapshot snapshot) {
    final progress = snapshot.budgetProgress;
    final level = snapshot.budgetLimitMinor <= 0
        ? BudgetAlertLevel.none
        : progress > 1
        ? BudgetAlertLevel.exceeded
        : progress >= approachingThreshold
        ? BudgetAlertLevel.approaching
        : BudgetAlertLevel.none;
    return BudgetAlertDecision(
      level: level,
      monthKey: snapshot.monthKey,
      spentMinor: snapshot.totalMinor,
      limitMinor: snapshot.budgetLimitMinor,
    );
  }
}
