import '../../invoices/domain/invoice_filters.dart';
import '../../invoices/domain/invoice_models.dart';
import '../../invoices/domain/invoice_repository.dart';

class LocalChatTools {
  const LocalChatTools(this._repository);

  final InvoiceRepository _repository;

  Future<DashboardSnapshot> monthSummary(String monthKey) {
    return _repository.watchDashboard(monthKey).first;
  }

  Future<({DashboardSnapshot dashboard, List<BudgetEntity> budgets})>
  budgetStatus(String monthKey) async {
    final dashboardFuture = monthSummary(monthKey);
    final budgetsFuture = _repository.watchBudgets(monthKey).first;
    return (dashboard: await dashboardFuture, budgets: await budgetsFuture);
  }

  Future<SpendingInsights> spendingInsights(String monthKey) {
    return _repository.watchSpendingInsights(monthKey).first;
  }

  Future<List<CategoryEntity>> categories() {
    return _repository.watchCategories().first;
  }

  Future<InvoicePage> recentTransactions({int limit = 10}) {
    return _repository.fetchInvoicePage(limit: limit);
  }

  Future<InvoicePage> searchTransactions({
    required InvoiceFilter filter,
    int limit = 10,
  }) {
    return _repository.fetchInvoicePage(filter: filter, limit: limit);
  }
}
