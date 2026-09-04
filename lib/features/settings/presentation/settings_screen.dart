import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/month_utils.dart';
import '../../export/application/invoice_export_service.dart';
import '../../export/application/invoice_restore_service.dart';
import '../../export/data/backup_catalog_store.dart';
import '../../export/data/supabase_backup_provider.dart';
import '../../invoices/domain/invoice_models.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../../shared/dialogs/confirm_dialog.dart';
import '../../../shared/widgets/app_error_state.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final rulesAsync = ref.watch(merchantRulesProvider);
    final syncHealth = ref.watch(syncHealthProvider);
    final budgetAlerts = ref.watch(budgetAlertsEnabledProvider);
    final backupRecords = ref.watch(backupRecordsProvider);
    final authUser = ref.watch(authUserProvider);
    final supabaseConfigured = ref.watch(supabaseClientProvider) != null;
    final categories = categoriesAsync.value ?? const <CategoryEntity>[];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(title: Text('Cài đặt')),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
            sliver: SliverList.list(
              children: [
                _Section(
                  title: 'Dữ liệu và quyền riêng tư',
                  children: [
                    const ListTile(
                      leading: Icon(Icons.phone_android_outlined),
                      title: Text('Local-first'),
                      subtitle: Text(
                        'Dữ liệu hóa đơn được lưu trên thiết bị. Chỉ text OCR/PDF được gửi đi khi Edge Function AI được bật.',
                      ),
                    ),
                    ListTile(
                      leading: Icon(
                        supabaseConfigured
                            ? Icons.cloud_sync_outlined
                            : Icons.cloud_off_outlined,
                      ),
                      title: const Text('Tài khoản và đồng bộ'),
                      subtitle: Text(
                        !supabaseConfigured
                            ? 'Supabase chưa được bật trong cấu hình build.'
                            : authUser.when(
                                data: (user) => user?.email ?? 'Chưa đăng nhập',
                                loading: () => 'Đang kiểm tra phiên đăng nhập…',
                                error: (_, _) =>
                                    'Không đọc được phiên đăng nhập.',
                              ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/settings/account'),
                    ),
                    ListTile(
                      leading: Icon(
                        Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: const Text('Xóa toàn bộ dữ liệu'),
                      subtitle: const Text(
                        'Xóa hóa đơn, ngân sách và quy tắc phân loại trên thiết bị.',
                      ),
                      onTap: () => _confirmDelete(context, ref),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'Thông báo',
                  children: [
                    budgetAlerts.when(
                      data: (enabled) => SwitchListTile(
                        secondary: const Icon(
                          Icons.notifications_active_outlined,
                        ),
                        title: const Text('Cảnh báo ngân sách'),
                        subtitle: const Text(
                          'Hiện cảnh báo khi dùng từ 80% hoặc vượt ngân sách.',
                        ),
                        value: enabled,
                        onChanged: (value) =>
                            _setBudgetAlerts(context, ref, value),
                      ),
                      loading: () => const _LoadingTile(),
                      error: (error, _) => _ErrorTile(
                        error: error,
                        label: 'Không đọc được cài đặt thông báo',
                        onRetry: () =>
                            ref.invalidate(budgetAlertsEnabledProvider),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'Phân loại tự động',
                  children: [
                    rulesAsync.when(
                      data: (rules) => _MerchantRuleManagement(
                        rules: rules,
                        categories: categories,
                        onDelete: (rule) =>
                            _confirmDeleteRule(context, ref, rule),
                      ),
                      loading: () => const _LoadingTile(),
                      error: (error, _) => _ErrorTile(
                        error: error,
                        label: 'Không tải được quy tắc phân loại',
                        onRetry: () => ref.invalidate(merchantRulesProvider),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'Sao lưu và khôi phục',
                  children: [
                    backupRecords.when(
                      data: (records) => _BackupStatusTile(records: records),
                      loading: () => const _LoadingTile(),
                      error: (error, _) => _ErrorTile(
                        error: error,
                        label: 'Không đọc được lịch sử backup',
                        onRetry: () => ref.invalidate(backupRecordsProvider),
                      ),
                    ),
                    _ExportManagement(
                      onExportJson: () => _export(context, ref, json: true),
                      onExportCsv: () => _export(context, ref, json: false),
                      onExportEncrypted: () => _exportEncrypted(context, ref),
                      onBackupCloud:
                          supabaseConfigured && authUser.asData?.value != null
                          ? () => _backupCloud(context, ref)
                          : null,
                      onManageCloud:
                          supabaseConfigured && authUser.asData?.value != null
                          ? () => _manageCloudBackups(
                              context,
                              ref,
                              categories.map((item) => item.id),
                            )
                          : null,
                      onExportPdf: () => _exportPdf(context, ref),
                      onRestoreJson: () => _restore(
                        context,
                        ref,
                        categories.map((item) => item.id),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'Xử lý thông minh',
                  children: [
                    const ListTile(
                      leading: Icon(Icons.auto_awesome_outlined),
                      title: Text('AI extraction'),
                      subtitle: Text(
                        'Tự động dùng Supabase Edge Function khi đã đăng nhập; nếu không, app dùng fallback offline.',
                      ),
                    ),
                    const ListTile(
                      leading: Icon(Icons.qr_code_scanner),
                      title: Text('QR lookup'),
                      subtitle: Text(
                        'Đã đọc QR từ camera; tra cứu provider vẫn cần backend allowlist.',
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.chat_bubble_outline),
                      title: const Text('Trợ lý chi tiêu'),
                      subtitle: const Text(
                        'Hỏi dữ liệu local; Gemini và tỷ giá bên ngoài dùng backend khi được bật.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/chat'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'Vận hành',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.history_outlined),
                      title: const Text('Lịch sử nhập hóa đơn'),
                      subtitle: const Text(
                        'Theo dõi lỗi, số lần chạy và thử lại tác vụ bị lỗi.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/settings/import-jobs'),
                    ),
                    syncHealth.when(
                      data: (health) => ListTile(
                        leading: Icon(
                          health.cloudConfigured
                              ? Icons.cloud_done_outlined
                              : Icons.cloud_off_outlined,
                        ),
                        title: const Text('Đồng bộ đám mây'),
                        subtitle: Text(
                          health.cloudConfigured
                              ? '${health.pendingCount} thay đổi đang chờ · ${health.failedCount} lỗi'
                              : '${health.pendingCount} thay đổi đã lưu trong outbox; cần cấu hình tài khoản và cloud gateway để gửi.',
                        ),
                        trailing: health.cloudConfigured
                            ? const Icon(Icons.sync)
                            : null,
                        onTap: health.cloudConfigured
                            ? () => _syncNow(context, ref)
                            : null,
                      ),
                      loading: () => const _LoadingTile(),
                      error: (error, _) => _ErrorTile(
                        error: error,
                        label: 'Không đọc được trạng thái đồng bộ',
                        onRetry: () => ref.invalidate(syncHealthProvider),
                      ),
                    ),
                    ref
                        .watch(invoiceConflictsProvider)
                        .when(
                          data: (conflicts) => ListTile(
                            leading: Icon(
                              conflicts.isEmpty
                                  ? Icons.check_circle_outline
                                  : Icons.warning_amber_outlined,
                              color: conflicts.isEmpty
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.error,
                            ),
                            title: const Text('Xung đột dữ liệu'),
                            subtitle: Text(
                              conflicts.isEmpty
                                  ? 'Không có hóa đơn cần xử lý.'
                                  : '${conflicts.length} hóa đơn cần bạn chọn bản giữ lại.',
                            ),
                            trailing: conflicts.isEmpty
                                ? null
                                : const Icon(Icons.chevron_right),
                            onTap: conflicts.isEmpty
                                ? null
                                : () => context.push('/settings/conflicts'),
                          ),
                          loading: () => const _LoadingTile(),
                          error: (error, _) => _ErrorTile(
                            error: error,
                            label: 'Không đọc được xung đột',
                            onRetry: () =>
                                ref.invalidate(invoiceConflictsProvider),
                          ),
                        ),
                  ],
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'Ứng dụng',
                  children: [
                    const ListTile(
                      leading: Icon(Icons.info_outline),
                      title: Text('Quản lý Tài chính'),
                      subtitle: Text('MVP 0.1.0 · Flutter'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.tune),
                      title: const Text('Môi trường'),
                      subtitle: Text(AppEnvironment.current.label),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteRule(
    BuildContext context,
    WidgetRef ref,
    MerchantRuleEntity rule,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Xóa quy tắc phân loại?',
      message:
          'Lần sau hóa đơn từ “${rule.normalizedMerchant}” sẽ không được tự '
          'động gán danh mục.',
      confirmLabel: 'Xóa quy tắc',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref
          .read(invoiceRepositoryProvider)
          .deleteMerchantRule(rule.normalizedMerchant);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã xóa quy tắc phân loại.')),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể xóa quy tắc: ${friendlyMessage(error)}'),
        ),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Xóa toàn bộ dữ liệu?',
      message:
          'Thao tác này không thể hoàn tác. Danh mục mặc định vẫn được giữ lại.',
      confirmLabel: 'Xóa dữ liệu',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(invoiceRepositoryProvider).deleteAllUserData();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã xóa toàn bộ dữ liệu trên thiết bị.')),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể xóa dữ liệu: ${friendlyMessage(error)}'),
        ),
      );
    }
  }

  Future<void> _export(
    BuildContext context,
    WidgetRef ref, {
    required bool json,
  }) async {
    try {
      final invoices = await ref
          .read(invoiceRepositoryProvider)
          .watchInvoices()
          .first;
      final uri = json
          ? await const InvoiceExportService().exportJson(invoices)
          : await const InvoiceExportService().exportCsv(invoices);
      if (uri == null) return;
      await _recordBackup(
        ref,
        json ? BackupRecordType.json : BackupRecordType.csv,
        uri,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã xuất ${invoices.length} hóa đơn.')),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể xuất dữ liệu: ${friendlyMessage(error)}'),
        ),
      );
    }
  }

  Future<void> _exportEncrypted(BuildContext context, WidgetRef ref) async {
    final password = await _showBackupPasswordDialog(
      context,
      confirmation: true,
    );
    if (password == null || !context.mounted) return;

    try {
      final invoices = await ref
          .read(invoiceRepositoryProvider)
          .watchInvoices()
          .first;
      final uri = await const InvoiceExportService().exportEncryptedJson(
        invoices,
        password,
      );
      if (uri == null) return;
      await _recordBackup(ref, BackupRecordType.encrypted, uri);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã xuất backup mã hóa ${invoices.length} hóa đơn.'),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Không thể xuất backup mã hóa: ${friendlyMessage(error)}',
          ),
        ),
      );
    }
  }

  Future<void> _backupCloud(BuildContext context, WidgetRef ref) async {
    final password = await _showBackupPasswordDialog(
      context,
      confirmation: true,
    );
    if (password == null || !context.mounted) return;
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    try {
      final provider = SupabaseBackupProvider(client);
      final invoices = await ref
          .read(invoiceRepositoryProvider)
          .watchInvoices()
          .first;
      final uri = await InvoiceExportService(
        provider: provider,
      ).exportEncryptedJson(invoices, password);
      if (uri == null || !context.mounted) return;
      await _recordBackup(ref, BackupRecordType.encrypted, uri);
      try {
        await provider.prune();
      } on Object {
        // Retention is best-effort and must not invalidate a successful upload.
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã sao lưu mã hóa ${invoices.length} hóa đơn lên Supabase.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể sao lưu cloud: ${friendlyMessage(error)}'),
        ),
      );
    }
  }

  Future<void> _manageCloudBackups(
    BuildContext context,
    WidgetRef ref,
    Iterable<String> categoryIds,
  ) async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;
    final provider = SupabaseBackupProvider(client);
    const restoreService = InvoiceRestoreService();

    try {
      while (context.mounted) {
        final entries = await provider.list();
        if (!context.mounted) return;
        final selection = await _showCloudBackupDialog(context, entries);
        if (selection == null || !context.mounted) return;

        if (selection.action == _CloudBackupAction.delete) {
          final confirmed = await _confirmCloudBackupDelete(
            context,
            selection.entry,
          );
          if (confirmed != true || !context.mounted) continue;
          await provider.delete(selection.entry);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã xóa backup khỏi Supabase.')),
          );
          continue;
        }

        final repository = ref.read(invoiceRepositoryProvider);
        final existing = await repository.watchInvoiceSummaries().first;
        final preview = await restoreService.previewBytes(
          bytes: await provider.download(selection.entry),
          fileName: selection.entry.fileName,
          existingIds: existing.map((invoice) => invoice.id).toSet(),
          existingSourceHashes: existing
              .map((invoice) => invoice.sourceHash)
              .whereType<String>()
              .toSet(),
          categoryIds: categoryIds.toSet(),
          requestPassword: () => _showBackupPasswordDialog(context),
        );
        if (preview == null || !context.mounted) continue;
        final confirmed = await _showRestorePreview(context, preview);
        if (confirmed != true || !context.mounted) continue;
        await restoreService.restore(preview, repository);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Đã khôi phục ${preview.readyCount} hóa đơn từ Supabase.',
            ),
          ),
        );
        return;
      }
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Không thể quản lý backup cloud: ${friendlyMessage(error)}',
          ),
        ),
      );
    }
  }

  Future<void> _exportPdf(BuildContext context, WidgetRef ref) async {
    try {
      final repository = ref.read(invoiceRepositoryProvider);
      final monthKey = MonthUtils.key(ref.read(selectedMonthProvider));
      final invoices = await repository.watchInvoices().first;
      final dashboard = await repository.watchDashboard(monthKey).first;
      final categories = await repository.watchCategories().first;
      final uri = await const InvoiceExportService().exportPdf(
        invoices: invoices,
        dashboard: dashboard,
        categories: categories,
      );
      if (uri == null) return;
      await _recordBackup(ref, BackupRecordType.pdf, uri);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã tạo báo cáo PDF cho ${invoices.length} hóa đơn.'),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể tạo báo cáo PDF: ${friendlyMessage(error)}'),
        ),
      );
    }
  }

  Future<void> _recordBackup(
    WidgetRef ref,
    BackupRecordType type,
    Uri uri,
  ) async {
    final fileName = uri.pathSegments.isEmpty
        ? 'Tệp đã lưu'
        : uri.pathSegments.last;
    try {
      final store = ref.read(backupCatalogStoreProvider);
      await store.record(
        BackupRecord(type: type, fileName: fileName, createdAt: DateTime.now()),
      );
      await store.prune();
      ref.invalidate(backupRecordsProvider);
    } on Object {
      // Metadata history must never turn a successful export into an error.
    }
  }

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    Iterable<String> categoryIds,
  ) async {
    const service = InvoiceRestoreService();
    var progressVisible = false;
    try {
      final preview = await service.pickAndPreview(
        repository: ref.read(invoiceRepositoryProvider),
        categoryIds: categoryIds,
        requestPassword: () => _showBackupPasswordDialog(context),
      );
      if (preview == null || !context.mounted) return;
      final confirmed = await _showRestorePreview(context, preview);
      if (confirmed != true || !context.mounted) return;

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Expanded(child: Text('Đang khôi phục dữ liệu…')),
              ],
            ),
          ),
        ),
      );
      progressVisible = true;
      await service.restore(preview, ref.read(invoiceRepositoryProvider));
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      progressVisible = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã khôi phục ${preview.readyCount} hóa đơn.')),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      if (progressVisible) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Không thể khôi phục dữ liệu: ${friendlyMessage(error)}',
          ),
        ),
      );
    }
  }

  Future<void> _syncNow(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(syncOutboxStoreProvider).retryFailed();
      final result = await ref.read(syncEngineProvider).runOnce();
      if (!context.mounted) return;
      final message = !result.configured
          ? 'Cloud sync chưa được cấu hình.'
          : !result.signedIn
          ? 'Hãy đăng nhập trước khi đồng bộ.'
          : 'Đã đồng bộ ${result.pushed} thay đổi; ${result.failed} lỗi.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể đồng bộ: ${friendlyMessage(error)}')),
      );
    }
  }

  Future<void> _setBudgetAlerts(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    if (enabled) {
      final granted = await ref
          .read(budgetNotificationServiceProvider)
          .requestPermission();
      if (!granted) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Chưa được cấp quyền thông báo. Hãy bật quyền trong cài đặt hệ thống.',
            ),
          ),
        );
        return;
      }
    }
    await ref.read(budgetAlertPreferencesProvider).setEnabled(enabled);
    ref.invalidate(budgetAlertsEnabledProvider);
  }
}

enum _CloudBackupAction { restore, delete }

class _CloudBackupSelection {
  const _CloudBackupSelection(this.action, this.entry);

  final _CloudBackupAction action;
  final CloudBackupEntry entry;
}

Future<_CloudBackupSelection?> _showCloudBackupDialog(
  BuildContext context,
  List<CloudBackupEntry> entries,
) {
  return showDialog<_CloudBackupSelection>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.cloud_queue_outlined),
      title: const Text('Backup trên Supabase'),
      content: SizedBox(
        width: 520,
        child: entries.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Tài khoản chưa có backup cloud. Hãy tạo một backup mã hóa trước.',
                  textAlign: TextAlign.center,
                ),
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final entry = entries[index];
                    final details = <String>[
                      if (entry.createdAt != null)
                        _backupDate(entry.createdAt!),
                      if (entry.sizeBytes != null)
                        _formatFileSize(entry.sizeBytes!),
                    ];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.lock_outline),
                      title: Text(
                        entry.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: details.isEmpty
                          ? const Text('Backup mã hóa')
                          : Text(details.join(' · ')),
                      trailing: Wrap(
                        spacing: 0,
                        children: [
                          IconButton(
                            tooltip: 'Khôi phục',
                            onPressed: () => Navigator.pop(
                              dialogContext,
                              _CloudBackupSelection(
                                _CloudBackupAction.restore,
                                entry,
                              ),
                            ),
                            icon: const Icon(Icons.restore),
                          ),
                          IconButton(
                            tooltip: 'Xóa khỏi cloud',
                            onPressed: () => Navigator.pop(
                              dialogContext,
                              _CloudBackupSelection(
                                _CloudBackupAction.delete,
                                entry,
                              ),
                            ),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Đóng'),
        ),
      ],
    ),
  );
}

Future<bool?> _confirmCloudBackupDelete(
  BuildContext context,
  CloudBackupEntry entry,
) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.delete_outline),
      title: const Text('Xóa backup cloud?'),
      content: Text(
        '“${entry.fileName}” sẽ bị xóa khỏi Supabase và không thể khôi phục.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Hủy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Xóa backup'),
        ),
      ],
    ),
  );
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

Future<bool?> _showRestorePreview(
  BuildContext context,
  InvoiceRestorePreview preview,
) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.restore_page_outlined),
      title: const Text('Xem trước bản khôi phục'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 420),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                preview.fileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 16),
              _RestoreStat(
                label: 'Sẵn sàng khôi phục',
                value: preview.readyCount,
                icon: Icons.check_circle_outline,
              ),
              _RestoreStat(
                label: 'Bỏ qua do trùng',
                value: preview.duplicateCount,
                icon: Icons.content_copy_outlined,
              ),
              _RestoreStat(
                label: 'Dữ liệu không hợp lệ',
                value: preview.invalidCount,
                icon: Icons.error_outline,
              ),
              if (preview.issues.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Chi tiết cần kiểm tra',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                ...preview.issues.map(
                  (issue) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $issue'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Hủy'),
        ),
        FilledButton.icon(
          onPressed: preview.canRestore
              ? () => Navigator.pop(dialogContext, true)
              : null,
          icon: const Icon(Icons.restore),
          label: Text('Khôi phục ${preview.readyCount}'),
        ),
      ],
    ),
  );
}

Future<String?> _showBackupPasswordDialog(
  BuildContext context, {
  bool confirmation = false,
}) async {
  final passwordController = TextEditingController();
  final confirmationController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  try {
    return await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.lock_outline),
        title: Text(confirmation ? 'Tạo backup mã hóa' : 'Mở backup mã hóa'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: passwordController,
                autofocus: true,
                obscureText: true,
                textInputAction: confirmation
                    ? TextInputAction.next
                    : TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Mật khẩu backup',
                  hintText: 'Ít nhất 8 ký tự',
                  prefixIcon: Icon(Icons.key_outlined),
                ),
                validator: (value) {
                  if (value == null || value.length < 8) {
                    return 'Mật khẩu phải có ít nhất 8 ký tự';
                  }
                  return null;
                },
              ),
              if (confirmation) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmationController,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Nhập lại mật khẩu',
                    prefixIcon: Icon(Icons.verified_user_outlined),
                  ),
                  validator: (value) {
                    if (value != passwordController.text) {
                      return 'Mật khẩu xác nhận không khớp';
                    }
                    return null;
                  },
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton.icon(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, passwordController.text);
              }
            },
            icon: Icon(confirmation ? Icons.lock_outline : Icons.lock_open),
            label: Text(confirmation ? 'Mã hóa và xuất' : 'Mở backup'),
          ),
        ],
      ),
    );
  } finally {
    passwordController.dispose();
    confirmationController.dispose();
  }
}

class _RestoreStat extends StatelessWidget {
  const _RestoreStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon),
      title: Text(label),
      trailing: Text('$value', style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _MerchantRuleManagement extends StatelessWidget {
  const _MerchantRuleManagement({
    required this.rules,
    required this.categories,
    required this.onDelete,
  });

  final List<MerchantRuleEntity> rules;
  final List<CategoryEntity> categories;
  final ValueChanged<MerchantRuleEntity> onDelete;

  @override
  Widget build(BuildContext context) {
    if (rules.isEmpty) {
      return const ListTile(
        leading: Icon(Icons.auto_fix_high_outlined),
        title: Text('Chưa có quy tắc nào'),
        subtitle: Text(
          'Sau khi xác nhận hóa đơn, lựa chọn danh mục sẽ được ghi nhớ theo merchant.',
        ),
      );
    }

    return Column(
      children: [
        const ListTile(
          leading: Icon(Icons.auto_fix_high_outlined),
          title: Text('Quy tắc đã ghi nhớ'),
          subtitle: Text('Áp dụng tự động cho các hóa đơn mới.'),
        ),
        ...rules.map((rule) {
          final category = _findCategory(categories, rule.categoryId);
          return ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: Text(rule.normalizedMerchant),
            subtitle: Text(
              'Tự động gán: ${category?.name ?? 'Danh mục không còn tồn tại'}',
            ),
            trailing: IconButton(
              tooltip: 'Xóa quy tắc',
              onPressed: () => onDelete(rule),
              icon: const Icon(Icons.delete_outline),
            ),
          );
        }),
      ],
    );
  }
}

class _BackupStatusTile extends StatelessWidget {
  const _BackupStatusTile({required this.records});

  final List<BackupRecord> records;

  @override
  Widget build(BuildContext context) {
    final last = records.isEmpty ? null : records.first;
    return ListTile(
      leading: Icon(
        last == null ? Icons.backup_outlined : Icons.verified_outlined,
        color: last == null
            ? Theme.of(context).colorScheme.onSurfaceVariant
            : Theme.of(context).colorScheme.primary,
      ),
      title: Text(last == null ? 'Chưa có lịch sử backup' : 'Backup gần nhất'),
      subtitle: Text(
        last == null
            ? 'Metadata xuất file được lưu local để theo dõi lần sao lưu gần nhất.'
            : '${last.label}: ${last.fileName}\n${_backupDate(last.createdAt)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: records.isEmpty ? null : Text('${records.length}/20'),
    );
  }
}

String _backupDate(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year} $hour:$minute';
}

class _ExportManagement extends StatelessWidget {
  const _ExportManagement({
    required this.onExportJson,
    required this.onExportCsv,
    required this.onExportEncrypted,
    required this.onBackupCloud,
    required this.onManageCloud,
    required this.onExportPdf,
    required this.onRestoreJson,
  });

  final VoidCallback onExportJson;
  final VoidCallback onExportCsv;
  final VoidCallback onExportEncrypted;
  final VoidCallback? onBackupCloud;
  final VoidCallback? onManageCloud;
  final VoidCallback onExportPdf;
  final VoidCallback onRestoreJson;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.data_object_outlined),
          title: const Text('Xuất JSON đầy đủ'),
          subtitle: const Text(
            'Bao gồm hóa đơn, dòng hàng và bằng chứng dữ liệu.',
          ),
          trailing: const Icon(Icons.download_outlined),
          onTap: onExportJson,
        ),
        ListTile(
          leading: const Icon(Icons.table_chart_outlined),
          title: const Text('Xuất CSV'),
          subtitle: const Text('Phù hợp để mở bằng Excel hoặc Google Sheets.'),
          trailing: const Icon(Icons.download_outlined),
          onTap: onExportCsv,
        ),
        ListTile(
          leading: const Icon(Icons.enhanced_encryption_outlined),
          title: const Text('Xuất backup mã hóa'),
          subtitle: const Text(
            'Mã hóa toàn bộ dữ liệu bằng mật khẩu trước khi lưu tệp .hdbak.',
          ),
          trailing: const Icon(Icons.download_outlined),
          onTap: onExportEncrypted,
        ),
        ListTile(
          leading: const Icon(Icons.cloud_upload_outlined),
          title: const Text('Sao lưu backup mã hóa lên Supabase'),
          subtitle: Text(
            onBackupCloud == null
                ? 'Đăng nhập Supabase để bật backup cloud riêng tư.'
                : 'Chỉ tải lên tệp .hdbak đã mã hóa, không tải plaintext hóa đơn.',
          ),
          trailing: const Icon(Icons.cloud_upload_outlined),
          onTap: onBackupCloud,
        ),
        ListTile(
          leading: const Icon(Icons.cloud_queue_outlined),
          title: const Text('Quản lý backup Supabase'),
          subtitle: Text(
            onManageCloud == null
                ? 'Đăng nhập để xem và khôi phục backup cloud.'
                : 'Xem, khôi phục hoặc xóa các backup mã hóa của tài khoản.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: onManageCloud,
        ),
        ListTile(
          leading: const Icon(Icons.picture_as_pdf_outlined),
          title: const Text('Xuất báo cáo PDF'),
          subtitle: const Text(
            'Tổng quan tháng, danh mục và danh sách hóa đơn tham khảo.',
          ),
          trailing: const Icon(Icons.download_outlined),
          onTap: onExportPdf,
        ),
        ListTile(
          leading: const Icon(Icons.restore_page_outlined),
          title: const Text('Khôi phục JSON hoặc backup mã hóa'),
          subtitle: const Text(
            'Hỗ trợ JSON cũ và .hdbak; xem trước, bỏ qua bản trùng rồi mới ghi dữ liệu.',
          ),
          trailing: const Icon(Icons.upload_file_outlined),
          onTap: onRestoreJson,
        ),
      ],
    );
  }
}

class _LoadingTile extends StatelessWidget {
  const _LoadingTile();

  @override
  Widget build(BuildContext context) {
    return const ListTile(
      leading: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      title: Text('Đang tải…'),
    );
  }
}

class _ErrorTile extends StatelessWidget {
  const _ErrorTile({required this.error, required this.label, this.onRetry});

  final Object error;
  final String label;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    // Trước đây tile này chỉ in một câu và KHÔNG có hành động nào — năm ngõ cụt
    // trong màn Cài đặt.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: AppErrorState(
        error: error,
        title: label,
        compact: true,
        onRetry: onRetry,
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Card(child: Column(children: children)),
      ],
    );
  }
}

CategoryEntity? _findCategory(
  List<CategoryEntity> categories,
  String categoryId,
) {
  for (final category in categories) {
    if (category.id == categoryId) return category;
  }
  return null;
}
