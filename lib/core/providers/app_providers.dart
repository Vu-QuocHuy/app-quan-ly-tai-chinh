import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/data/supabase_auth_service.dart';
import '../../features/chat/data/chat_api_client.dart';
import '../../features/chat/data/chat_history_store.dart';
import '../../features/chat/domain/local_chat_assistant.dart';
import '../../features/export/data/backup_catalog_store.dart';
import '../../features/groups/data/group_service.dart';
import '../../features/groups/domain/group_models.dart';
import '../../features/sharing/data/shared_bill_service.dart';
import '../../features/sharing/domain/shared_bill_models.dart';
import '../../features/ingestion/application/import_coordinator.dart';
import '../../features/ingestion/data/ai_extraction_client.dart';
import '../../features/ingestion/data/ai_extraction_job_client.dart';
import '../../features/ingestion/data/drift_import_job_store.dart';
import '../../features/ingestion/data/heuristic_text_extractor.dart';
import '../../features/ingestion/data/ocr_service.dart';
import '../../features/ingestion/data/pdf_text_service.dart';
import '../../features/ingestion/data/pending_import_store.dart';
import '../../features/ingestion/data/xml_invoice_extractor.dart';
import '../../features/ingestion/domain/import_job.dart';
import '../../features/invoices/data/drift_invoice_repository.dart';
import '../../features/invoices/domain/invoice_filters.dart';
import '../../features/invoices/domain/invoice_models.dart';
import '../../features/invoices/domain/invoice_repository.dart';
import '../../features/notifications/data/budget_alert_preferences.dart';
import '../../features/notifications/data/budget_notification_service.dart';
import '../../features/insights/data/anomaly_feedback_store.dart';
import '../../features/sync/application/sync_engine.dart';
import '../../features/sync/application/sync_coordinator.dart';
import '../../features/sync/application/sync_pull_coordinator.dart';
import '../../features/sync/data/drift_sync_outbox_store.dart';
import '../../features/sync/data/drift_sync_cursor_store.dart';
import '../../features/sync/data/supabase_sync_gateway.dart';
import '../../features/sync/domain/sync_gateway.dart';
import '../../features/sync/domain/sync_models.dart';
import '../config/feature_flags.dart';
import '../database/app_database.dart';
import '../database/local_database_scope.dart';
import '../security/supabase_bootstrap.dart';
import '../utils/month_utils.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final cloudConfigured = ref.watch(supabaseClientProvider) != null;
  final userId = ref.watch(authUserProvider).value?.id;
  final database = AppDatabase(
    null,
    LocalDatabaseScope.databaseName(
      userId: userId,
      cloudConfigured: cloudConfigured,
    ),
  );
  ref.onDispose(database.close);
  return database;
});

final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  return SupabaseBootstrap.clientOrNull;
});

final supabaseAuthServiceProvider = Provider<SupabaseAuthService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SupabaseAuthService(client);
});

final authUserProvider = StreamProvider<User?>((ref) async* {
  final service = ref.watch(supabaseAuthServiceProvider);
  if (service == null) {
    yield null;
    return;
  }
  final currentUser = service.currentUser;
  await LocalDatabaseScope.bindUser(currentUser?.id);
  yield currentUser;
  await for (final user in service.watchUser().skip(1)) {
    await LocalDatabaseScope.bindUser(user?.id);
    yield user;
  }
});

final authIdentitiesProvider = FutureProvider.autoDispose<List<UserIdentity>>((
  ref,
) async {
  final user = ref.watch(authUserProvider).value;
  final service = ref.watch(supabaseAuthServiceProvider);
  if (user == null || service == null) return const [];
  return service.getUserIdentities();
});

final featureFlagsProvider = FutureProvider<FeatureFlags>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final user = ref.watch(authUserProvider).value;
  return RemoteConfigService(client).load(userId: user?.id);
});

final invoiceRepositoryProvider = Provider<InvoiceRepository>((ref) {
  return DriftInvoiceRepository(ref.watch(databaseProvider));
});

final chatHistoryStoreProvider = Provider<ChatHistoryStore>((ref) {
  final userId = ref.watch(authUserProvider).value?.id;
  return ChatHistoryStore(scope: userId);
});

final expenseGroupServiceProvider = Provider<ExpenseGroupService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : ExpenseGroupService(client);
});

final sharedBillServiceProvider = Provider<SharedBillService?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? null : SharedBillService(client);
});

final directBillSharesProvider =
    FutureProvider.autoDispose<List<DirectBillShare>>((ref) {
      final service = ref.watch(sharedBillServiceProvider);
      return service?.listDirectShares() ?? const [];
    });

final expenseGroupsProvider = FutureProvider.autoDispose<List<ExpenseGroup>>((
  ref,
) {
  final service = ref.watch(expenseGroupServiceProvider);
  return service?.listGroups() ?? const [];
});

final backupCatalogStoreProvider = Provider<BackupCatalogStore>((ref) {
  final userId = ref.watch(authUserProvider).value?.id;
  return BackupCatalogStore(scope: userId);
});

final backupRecordsProvider = FutureProvider<List<BackupRecord>>((ref) {
  return ref.watch(backupCatalogStoreProvider).load();
});

final localChatAssistantProvider = Provider<LocalChatAssistant>((ref) {
  return LocalChatAssistant(ref.watch(invoiceRepositoryProvider));
});

final chatApiClientProvider = Provider<ChatApiClient>((ref) {
  ref.watch(authUserProvider);
  final client = ref.watch(supabaseClientProvider);
  return ChatApiClient(supabaseClient: client);
});

final aiExtractionClientProvider = Provider<AiExtractionClient>((ref) {
  ref.watch(authUserProvider);
  final client = ref.watch(supabaseClientProvider);
  final flags = ref.watch(featureFlagsProvider).value ?? FeatureFlags.defaults;
  return AiExtractionClient(supabaseClient: client, enabled: flags.onlineAi);
});

final aiExtractionJobClientProvider = Provider<AiExtractionJobClient>((ref) {
  ref.watch(authUserProvider);
  final flags = ref.watch(featureFlagsProvider).value ?? FeatureFlags.defaults;
  return AiExtractionJobClient(
    supabaseClient: ref.watch(supabaseClientProvider),
    enabled: flags.onlineAi,
  );
});

final importCoordinatorProvider = Provider<ImportCoordinator>((ref) {
  return ImportCoordinator(
    repository: ref.watch(invoiceRepositoryProvider),
    xmlExtractor: XmlInvoiceExtractor(),
    ocrService: OcrService(),
    pdfTextService: const PdfTextService(),
    aiExtractor: ref.watch(aiExtractionClientProvider),
    heuristicExtractor: HeuristicTextExtractor(),
  );
});

final importJobStoreProvider = Provider<DriftImportJobStore>((ref) {
  return DriftImportJobStore(ref.watch(databaseProvider));
});

final pendingImportStoreProvider = Provider<PendingImportStore>((ref) {
  final userId = ref.watch(authUserProvider).value?.id;
  return PendingImportStore(scope: userId);
});

final importJobsProvider = StreamProvider<List<ImportJobEntity>>((ref) {
  return ref.watch(importJobStoreProvider).watchRecent();
});

final importRetrySignalProvider = StateProvider<int>((ref) => 0);

final syncGatewayProvider = Provider<SyncGateway>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? const DisabledSyncGateway()
      : SupabaseSyncGateway(client);
});

final syncIdentityProvider = Provider<SyncIdentityProvider>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? const DisabledSyncIdentityProvider()
      : SupabaseSyncIdentityProvider(client);
});

final syncOutboxStoreProvider = Provider<DriftSyncOutboxStore>((ref) {
  return DriftSyncOutboxStore(ref.watch(databaseProvider));
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine(
    store: ref.watch(syncOutboxStoreProvider),
    identity: ref.watch(syncIdentityProvider),
    gateway: ref.watch(syncGatewayProvider),
  );
});

final syncPullGatewayProvider = Provider<SyncPullGateway?>((ref) {
  final gateway = ref.watch(syncGatewayProvider);
  if (gateway is SyncPullGateway) return gateway as SyncPullGateway;
  return null;
});

final syncCursorStoreProvider = Provider<DriftSyncCursorStore>((ref) {
  return DriftSyncCursorStore(ref.watch(databaseProvider));
});

final syncPullCoordinatorProvider = Provider<SyncPullCoordinator?>((ref) {
  final gateway = ref.watch(syncPullGatewayProvider);
  if (gateway == null) return null;
  return SyncPullCoordinator(
    repository: ref.watch(invoiceRepositoryProvider),
    cursors: ref.watch(syncCursorStoreProvider),
    gateway: gateway,
  );
});

final referenceSyncPullCoordinatorsProvider =
    Provider<List<SyncPullCoordinator>>((ref) {
      final gateway = ref.watch(syncPullGatewayProvider);
      if (gateway == null) return const [];
      final repository = ref.watch(invoiceRepositoryProvider);
      final cursors = ref.watch(syncCursorStoreProvider);
      return [
        for (final aggregateType in const [
          'category',
          'budget',
          'merchant_rule',
        ])
          SyncPullCoordinator(
            repository: repository,
            cursors: cursors,
            gateway: gateway,
            aggregateType: aggregateType,
          ),
      ];
    });

final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  return SyncCoordinator(
    upload: ref.watch(syncEngineProvider),
    identity: ref.watch(syncIdentityProvider),
    download: ref.watch(syncPullCoordinatorProvider),
    referenceDownloads: ref.watch(referenceSyncPullCoordinatorsProvider),
  );
});

final syncHealthProvider = StreamProvider<SyncHealth>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return ref
      .watch(syncOutboxStoreProvider)
      .watchHealth(cloudConfigured: engine.isConfigured);
});

final invoicesProvider = StreamProvider<List<InvoiceEntity>>((ref) {
  return ref.watch(invoiceRepositoryProvider).watchInvoices();
});

final invoiceConflictsProvider = StreamProvider<List<InvoiceConflictEntity>>((
  ref,
) {
  return ref.watch(invoiceRepositoryProvider).watchInvoiceConflicts();
});

final invoiceSummariesProvider = StreamProvider<List<InvoiceEntity>>((ref) {
  return ref.watch(invoiceRepositoryProvider).watchInvoiceSummaries();
});

// autoDispose: family này được key theo (filter, limit). Mỗi lần người dùng gõ
// vào ô tìm kiếm hoặc bấm "Tải thêm" là một key mới, và không có autoDispose
// thì mọi stream cũ vẫn sống — giữ nguyên subscription drift cho từng tổ hợp
// bộ lọc trong suốt phiên.
final filteredInvoiceSummariesProvider = StreamProvider.autoDispose
    .family<List<InvoiceEntity>, InvoiceListQuery>((ref, query) {
      return ref
          .watch(invoiceRepositoryProvider)
          .watchInvoiceSummaries(filter: query.filter, limit: query.limit);
    });

/// Chi tiết một hóa đơn theo id.
///
/// Trước đây màn Chi tiết gọi `findById` trong `FutureBuilder` dựng ngay trong
/// `build()`: mỗi lần `categoriesProvider` phát là một Future MỚI, nên
/// `connectionState` về `waiting` và cả trang nháy về spinner. Nó cũng không có
/// nhánh lỗi, nên lỗi DB tạm thời bị trình bày thành "Không tìm thấy hóa đơn"
/// — tức là báo mất dữ liệu.
final invoiceDetailProvider = FutureProvider.autoDispose
    .family<InvoiceEntity?, String>((ref, id) {
      return ref.watch(invoiceRepositoryProvider).findById(id);
    });

final categoriesProvider = StreamProvider<List<CategoryEntity>>((ref) {
  return ref.watch(invoiceRepositoryProvider).watchCategories();
});

final merchantRulesProvider = StreamProvider<List<MerchantRuleEntity>>((ref) {
  return ref.watch(invoiceRepositoryProvider).watchMerchantRules();
});

final selectedMonthProvider = StateProvider<DateTime>((ref) {
  return MonthUtils.normalize(DateTime.now());
});

String currentMonthKey() {
  return MonthUtils.key(DateTime.now());
}

final budgetsProvider = StreamProvider<List<BudgetEntity>>((ref) {
  final month = ref.watch(selectedMonthProvider);
  return ref
      .watch(invoiceRepositoryProvider)
      .watchBudgets(MonthUtils.key(month));
});

final dashboardProvider = StreamProvider<DashboardSnapshot>((ref) {
  final month = ref.watch(selectedMonthProvider);
  return ref
      .watch(invoiceRepositoryProvider)
      .watchDashboard(MonthUtils.key(month));
});

final spendingInsightsProvider = StreamProvider<SpendingInsights>((ref) {
  final month = ref.watch(selectedMonthProvider);
  return ref
      .watch(invoiceRepositoryProvider)
      .watchSpendingInsights(MonthUtils.key(month));
});

final anomalyFeedbackStoreProvider = Provider<AnomalyFeedbackStore>((ref) {
  final userId = ref.watch(authUserProvider).value?.id;
  return AnomalyFeedbackStore(scope: userId);
});

final dismissedAnomalyIdsProvider = FutureProvider<Set<String>>((ref) {
  return ref.watch(anomalyFeedbackStoreProvider).loadDismissedIds();
});

final budgetAlertPreferencesProvider = Provider<BudgetAlertPreferences>((ref) {
  final userId = ref.watch(authUserProvider).value?.id;
  return BudgetAlertPreferences(scope: userId);
});

final budgetNotificationServiceProvider = Provider<BudgetNotificationService>(
  (ref) => BudgetNotificationService(
    preferences: ref.watch(budgetAlertPreferencesProvider),
  ),
);

final budgetAlertsEnabledProvider = FutureProvider<bool>((ref) {
  return ref.watch(budgetAlertPreferencesProvider).isEnabled();
});
