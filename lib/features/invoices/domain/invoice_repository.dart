import 'invoice_filters.dart';
import 'invoice_models.dart';

abstract interface class InvoiceRepository {
  Stream<List<InvoiceEntity>> watchInvoices();
  Stream<List<InvoiceEntity>> watchInvoiceSummaries({
    InvoiceFilter filter = const InvoiceFilter(),
    int? limit,
  });
  Future<InvoicePage> fetchInvoicePage({
    InvoiceFilter filter = const InvoiceFilter(),
    int limit = 50,
    InvoicePageCursor? cursor,
  });
  Stream<List<CategoryEntity>> watchCategories();
  Stream<List<MerchantRuleEntity>> watchMerchantRules();
  Stream<List<BudgetEntity>> watchBudgets(String monthKey);
  Stream<DashboardSnapshot> watchDashboard(String monthKey);
  Stream<SpendingInsights> watchSpendingInsights(String monthKey);
  Future<InvoiceEntity?> findById(String id);
  Future<InvoiceEntity?> findBySourceHash(String hash);
  Future<List<InvoiceEntity>> findDuplicateCandidates(InvoiceEntity candidate);
  Future<void> saveInvoice(InvoiceEntity invoice);
  Future<void> saveRemoteInvoice(InvoiceEntity invoice);
  Future<void> deleteRemoteInvoice(
    String id, {
    required int revision,
    required DateTime updatedAt,
    DateTime? deletedAt,
  });
  Future<void> saveRemoteCategory(CategoryEntity category);
  Future<void> deleteRemoteCategory(String id);
  Future<void> saveRemoteBudget(BudgetEntity budget);
  Future<void> deleteRemoteBudget(String id);
  Future<void> saveRemoteMerchantRule(MerchantRuleEntity rule);
  Future<void> deleteRemoteMerchantRule(String normalizedMerchant);
  Future<void> markInvoiceConflict(String id, {InvoiceEntity? remote});
  Stream<List<InvoiceConflictEntity>> watchInvoiceConflicts();
  Future<void> resolveInvoiceConflictKeepLocal(String id);
  Future<void> resolveInvoiceConflictUseRemote(String id);
  Future<void> saveInvoices(Iterable<InvoiceEntity> invoices);
  Future<void> deleteInvoice(String id);
  Future<void> deleteAllUserData();
  Future<void> saveCategory(CategoryEntity category);
  Future<void> deleteCategory(String id);
  Future<void> saveBudget(BudgetEntity budget);
  Future<void> deleteBudget(String id);
  Future<void> saveMerchantRule(String merchant, String categoryId);
  Future<void> deleteMerchantRule(String normalizedMerchant);
  Future<String?> categoryForMerchant(String merchant);
}
