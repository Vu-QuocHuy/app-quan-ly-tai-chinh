import '../../../shared/widgets/finmi_page_header.dart';
import '../../../shared/widgets/finmi_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/localization/app_strings.dart';
import '../../../core/providers/app_providers.dart';
import '../../export/application/invoice_restore_service.dart';
import '../../export/data/supabase_backup_provider.dart';
import '../../invoices/domain/invoice_models.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../../shared/dialogs/confirm_dialog.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../app/theme/theme_mode_provider.dart';
import '../../../app/theme/finmi_appearance.dart';
import '../../../app/theme/app_theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final syncHealth = ref.watch(syncHealthProvider);
    final budgetAlerts = ref.watch(budgetAlertsEnabledProvider);
    final authUser = ref.watch(authUserProvider);
    final conflictsAsync = ref.watch(invoiceConflictsProvider);
    final conflictCount = conflictsAsync.valueOrNull?.length ?? 0;
    final featureFlags =
        ref.watch(featureFlagsProvider).value ?? FeatureFlags.defaults;
    final supabaseConfigured = ref.watch(supabaseClientProvider) != null;
    final themeMode = ref.watch(themeModeProvider);
    final selectedAppearance = ref.watch(finmiAppearanceProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final visibleAppearance = selectedAppearance.isDark == isDark
        ? selectedAppearance
        : FinmiAppearance.fromId(isDark ? 'midnight' : 'white');
    final tr = context.tr;
    final themeLabel = switch (themeMode) {
      ThemeMode.light => tr.isEn ? 'Light' : 'Sáng',
      ThemeMode.dark => tr.isEn ? 'Dark' : 'Tối',
      ThemeMode.system => tr.isEn ? 'System default' : 'Theo hệ thống',
    };
    final categories = categoriesAsync.value ?? const <CategoryEntity>[];

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          FinmiSliverHeader(title: tr.settingsTitle),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
            sliver: SliverList.list(
              children: [
                _Section(
                  title: tr.secAccountAndSync,
                  children: [
                    ListTile(
                      leading: Icon(
                        supabaseConfigured
                            ? Icons.cloud_sync_outlined
                            : Icons.cloud_off_outlined,
                      ),
                      title: Text(tr.accountTitle),
                      subtitle: Text(
                        !supabaseConfigured
                            ? (tr.isEn
                                  ? 'Account not configured.'
                                  : 'Tài khoản chưa được cấu hình.')
                            : authUser.when(
                                data: (user) =>
                                    user?.email ??
                                    (tr.isEn
                                        ? 'Not logged in'
                                        : 'Chưa đăng nhập'),
                                loading: () => tr.isEn
                                    ? 'Loading account…'
                                    : 'Đang tải tài khoản…',
                                error: (_, _) => tr.isEn
                                    ? 'Failed to load account info.'
                                    : 'Không tải được thông tin tài khoản.',
                              ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/settings/account'),
                    ),
                    syncHealth.when(
                      data: (health) => ListTile(
                        leading: Icon(
                          health.cloudConfigured
                              ? Icons.cloud_done_outlined
                              : Icons.cloud_off_outlined,
                        ),
                        title: Text(
                          tr.isEn ? 'Data synchronization' : 'Đồng bộ dữ liệu',
                          maxLines: 3,
                        ),
                        subtitle: Text(
                          !featureFlags.cloudSync
                              ? (tr.isEn
                                    ? 'Sync is currently paused.'
                                    : 'Đồng bộ hiện đang tạm tắt.')
                              : !health.cloudConfigured
                              ? (tr.isEn
                                    ? 'Log in to sync data to the cloud.'
                                    : 'Đăng nhập để đồng bộ dữ liệu lên cloud.')
                              : health.failedCount > 0
                              ? (tr.isEn
                                    ? '${health.failedCount} changes need retry.'
                                    : '${health.failedCount} thay đổi cần thử lại.')
                              : health.pendingCount > 0
                              ? (tr.isEn
                                    ? '${health.pendingCount} changes waiting to upload.'
                                    : '${health.pendingCount} thay đổi đang chờ gửi.')
                              : (tr.isEn
                                    ? 'Data is up to date.'
                                    : 'Dữ liệu đã được cập nhật.'),
                        ),
                        trailing:
                            featureFlags.cloudSync && health.cloudConfigured
                            ? const Icon(Icons.sync)
                            : null,
                        onTap: featureFlags.cloudSync && health.cloudConfigured
                            ? () => _syncNow(context, ref)
                            : null,
                      ),
                      loading: () => const _LoadingTile(),
                      error: (error, _) => _ErrorTile(
                        error: error,
                        label: tr.isEn
                            ? 'Cannot load sync status'
                            : 'Không đọc được trạng thái đồng bộ',
                        onRetry: () => ref.invalidate(syncHealthProvider),
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.cloud_download_outlined),
                      title: Text(
                        tr.isEn
                            ? 'Restore customizations'
                            : 'Khôi phục tùy chỉnh',
                        maxLines: 3,
                      ),
                      subtitle: Text(
                        tr.isEn
                            ? 'Fetch theme and alerts from cloud when switching devices.'
                            : 'Lấy giao diện và cảnh báo từ tài khoản khi đổi thiết bị.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/settings/cloud'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _Section(
                  title: tr.secCustomization,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.language_outlined),
                      title: Text(tr.languageTitle, maxLines: 3),
                      subtitle: Text(
                        ref.watch(appLocaleProvider).languageCode == 'en'
                            ? tr.english
                            : tr.vietnamese,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _chooseLanguage(context, ref),
                    ),
                    ListTile(
                      leading: const Icon(Icons.brightness_6_outlined),
                      title: Text(tr.appearanceTitle, maxLines: 3),
                      subtitle: Text('${visibleAppearance.name} · $themeLabel'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _chooseAppearance(context, ref),
                    ),
                    ListTile(
                      leading: const Icon(Icons.contrast_outlined),
                      title: Text(tr.themeModeTitle, maxLines: 3),
                      subtitle: Text(themeLabel),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _chooseThemeMode(context, ref),
                    ),
                    budgetAlerts.when(
                      data: (enabled) => SwitchListTile(
                        secondary: const Icon(
                          Icons.notifications_active_outlined,
                        ),
                        title: Text(tr.budgetAlertsTitle, maxLines: 3),
                        subtitle: Text(
                          tr.isEn
                              ? 'Show warnings when using 80% or exceeding budget.'
                              : 'Hiện cảnh báo khi dùng từ 80% hoặc vượt ngân sách.',
                        ),
                        value: enabled,
                        onChanged: (value) =>
                            _setBudgetAlerts(context, ref, value),
                      ),
                      loading: () => const _LoadingTile(),
                      error: (error, _) => _ErrorTile(
                        error: error,
                        label: tr.isEn
                            ? 'Cannot load alert settings'
                            : 'Không đọc được cài đặt thông báo',
                        onRetry: () =>
                            ref.invalidate(budgetAlertsEnabledProvider),
                      ),
                    ),
                  ],
                ),
                if (conflictCount > 0) ...[
                  const SizedBox(height: 12),
                  _Section(
                    title: tr.isEn ? 'Action required' : 'Cần xử lý',
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.warning_amber_outlined,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        title: Text(
                          tr.isEn ? 'Data conflicts' : 'Xung đột dữ liệu',
                          maxLines: 3,
                        ),
                        subtitle: Text(
                          tr.isEn
                              ? '$conflictCount receipts need your choice on which version to keep.'
                              : '$conflictCount hóa đơn cần bạn chọn bản giữ lại.',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/settings/conflicts'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                _Section(
                  title: tr.isEn ? 'Data' : 'Dữ liệu',
                  children: [
                    ExpansionTile(
                      leading: const Icon(Icons.backup_outlined),
                      title: Text(
                        tr.isEn ? 'Data restore' : 'Khôi phục dữ liệu',
                        maxLines: 3,
                      ),
                      subtitle: Text(
                        tr.isEn
                            ? 'Restore from file or cloud backup.'
                            : 'Khôi phục từ tệp hoặc backup cloud.',
                      ),
                      children: [
                        _BackupManagement(
                          onManageCloud:
                              supabaseConfigured &&
                                  authUser.asData?.value != null
                              ? () => _manageCloudBackups(
                                  context,
                                  ref,
                                  categories.map((item) => item.id),
                                )
                              : null,
                          onRestoreJson: () => _restore(
                            context,
                            ref,
                            categories.map((item) => item.id),
                          ),
                        ),
                        ListTile(
                          leading: Icon(
                            Icons.delete_outline,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          title: Text(
                            tr.isEn
                                ? 'Erase local data'
                                : 'Xóa dữ liệu trên thiết bị',
                            maxLines: 3,
                          ),
                          subtitle: Text(
                            tr.isEn
                                ? 'This action cannot be undone.'
                                : 'Thao tác này không thể hoàn tác.',
                          ),
                          onTap: () => _confirmDelete(context, ref),
                        ),
                      ],
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

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final isEn = context.tr.isEn;
    final confirmed = await showConfirmDialog(
      context,
      title: isEn ? 'Erase all data?' : 'Xóa toàn bộ dữ liệu?',
      message: isEn
          ? 'This action cannot be undone. Default categories will be kept.'
          : 'Thao tác này không thể hoàn tác. Danh mục mặc định vẫn được giữ lại.',
      confirmLabel: isEn ? 'Erase data' : 'Xóa dữ liệu',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(invoiceRepositoryProvider).deleteAllUserData();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEn
                ? 'All device data has been erased.'
                : 'Đã xóa toàn bộ dữ liệu trên thiết bị.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEn
                ? 'Cannot erase data: ${friendlyMessage(error)}'
                : 'Không thể xóa dữ liệu: ${friendlyMessage(error)}',
          ),
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
            SnackBar(
              content: Text(
                context.tr.isEn
                    ? 'Deleted cloud backup from account.'
                    : 'Đã xóa backup khỏi tài khoản.',
              ),
            ),
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
          existingIncomeIds: (await ref.read(incomeRepositoryProvider).getAll())
              .map((entry) => entry.id)
              .toSet(),
          existingPlanIds: (await ref.read(planRepositoryProvider).getAll())
              .map((item) => item.id)
              .toSet(),
          requestPassword: () => _showBackupPasswordDialog(context),
        );
        if (preview == null || !context.mounted) continue;
        final confirmed = await _showRestorePreview(context, preview);
        if (confirmed != true || !context.mounted) continue;
        await restoreService.restore(
          preview,
          repository,
          incomeRepository: ref.read(incomeRepositoryProvider),
          planRepository: ref.read(planRepositoryProvider),
        );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr.isEn
                  ? 'Restored ${preview.readyCount} items from cloud backup.'
                  : 'Đã khôi phục ${preview.readyCount} mục từ bản sao lưu trực tuyến.',
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
        incomeRepository: ref.read(incomeRepositoryProvider),
        planRepository: ref.read(planRepositoryProvider),
        categoryIds: categoryIds,
        requestPassword: () => _showBackupPasswordDialog(context),
      );
      if (preview == null || !context.mounted) return;
      final confirmed = await _showRestorePreview(context, preview);
      if (confirmed != true || !context.mounted) return;

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    context.tr.isEn
                        ? 'Restoring data…'
                        : 'Đang khôi phục dữ liệu…',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      progressVisible = true;
      await service.restore(
        preview,
        ref.read(invoiceRepositoryProvider),
        incomeRepository: ref.read(incomeRepositoryProvider),
        planRepository: ref.read(planRepositoryProvider),
      );
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      progressVisible = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr.isEn
                ? 'Restored ${preview.readyCount} items.'
                : 'Đã khôi phục ${preview.readyCount} mục.',
          ),
        ),
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
    final flags = ref.read(featureFlagsProvider).value ?? FeatureFlags.defaults;
    if (!flags.cloudSync) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đồng bộ đang tạm tắt theo cấu hình rollout.'),
        ),
      );
      return;
    }
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
    try {
      final notificationService = ref.read(budgetNotificationServiceProvider);
      if (enabled) {
        final granted = await notificationService.requestPermission();
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
      if (!enabled) {
        try {
          await notificationService.cancelBudgetNotifications();
        } on Object catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Đã tắt cảnh báo mới; không thể xóa thông báo cũ: '
                  '${friendlyMessage(error)}',
                ),
              ),
            );
          }
        }
      }
      ref.invalidate(budgetAlertsEnabledProvider);
      if (!context.mounted) return;
      await _syncCloudProfilePreferences(context, ref, enabled);
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Không thể cập nhật thông báo: ${friendlyMessage(error)}',
          ),
        ),
      );
    }
  }

  Future<void> _chooseAppearance(BuildContext context, WidgetRef ref) async {
    final chosen = ref.read(finmiAppearanceProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final current = chosen.isDark == isDark
        ? chosen
        : FinmiAppearance.fromId(isDark ? 'midnight' : 'white');
    final selected = await showModalBottomSheet<FinmiAppearance>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(
                context.tr.isEn ? 'Select Theme' : 'Chọn giao diện',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                context.tr.isEn
                    ? 'Colors change, your data and actions stay the same.'
                    : 'Màu sắc thay đổi, dữ liệu và thao tác được giữ nguyên.',
              ),
              const SizedBox(height: 16),
              for (final appearance in FinmiAppearance.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Theme(
                    data: AppTheme.forAppearance(appearance),
                    child: Builder(
                      builder: (context) => Material(
                        color: appearance.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: current.id == appearance.id
                                ? appearance.primary
                                : appearance.tokens.border,
                            width: 1.25,
                          ),
                        ),
                        child: ListTile(
                          leading: Container(
                            width: 32,
                            height: 40,
                            decoration: BoxDecoration(
                              color: appearance.tokens.heroBackground,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: appearance.tokens.border,
                              ),
                            ),
                          ),
                          title: Text(appearance.name),
                          subtitle: Text(appearance.description),
                          trailing: current.id == appearance.id
                              ? const Icon(Icons.check_circle_outline)
                              : null,
                          onTap: () => Navigator.pop(sheetContext, appearance),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    try {
      await ref.read(finmiAppearanceProvider.notifier).set(selected);
      if (!context.mounted) return;
      await _setThemeMode(
        context,
        ref,
        selected.isDark ? ThemeMode.dark : ThemeMode.light,
      );
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể lưu giao diện: ${friendlyMessage(error)}'),
          ),
        );
      }
    }
  }

  Future<void> _chooseThemeMode(BuildContext context, WidgetRef ref) async {
    final tr = context.tr;
    final current = ref.read(themeModeProvider);
    final selected = await showModalBottomSheet<ThemeMode>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tr.themeModeTitle,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
            ),
            for (final option in [
              (ThemeMode.system, tr.isEn ? 'System default' : 'Theo hệ thống'),
              (ThemeMode.light, tr.isEn ? 'Light' : 'Sáng'),
              (ThemeMode.dark, tr.isEn ? 'Dark' : 'Tối'),
            ])
              ListTile(
                title: Text(option.$2),
                selected: current == option.$1,
                trailing: current == option.$1 ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(sheetContext).pop(option.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null || selected == current || !context.mounted) return;
    await _setThemeMode(context, ref, selected);
  }

  Future<void> _chooseLanguage(BuildContext context, WidgetRef ref) async {
    final tr = context.tr;
    final current = ref.read(appLocaleProvider).languageCode;
    final selected = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  tr.chooseLanguage,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
            ),
            ListTile(
              title: Text(tr.vietnamese),
              selected: current == 'vi',
              trailing: current == 'vi' ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(sheetContext).pop('vi'),
            ),
            ListTile(
              title: Text(tr.english),
              selected: current == 'en',
              trailing: current == 'en' ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(sheetContext).pop('en'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null || selected == current) return;
    await ref.read(appLocaleProvider.notifier).setLocale(selected);
  }

  Future<void> _setThemeMode(
    BuildContext context,
    WidgetRef ref,
    ThemeMode mode,
  ) async {
    await ref.read(themeModeProvider.notifier).set(mode);
    if (!context.mounted) return;
    final enabled = await ref.read(budgetAlertPreferencesProvider).isEnabled();
    if (!context.mounted) return;
    await _syncCloudProfilePreferences(context, ref, enabled);
  }

  Future<void> _syncCloudProfilePreferences(
    BuildContext context,
    WidgetRef ref,
    bool alertsEnabled,
  ) async {
    final store = ref.read(profilePreferencesStoreProvider);
    if (store == null || !store.canSync) return;
    try {
      await store.save(
        themeMode: ref.read(themeModeProvider).name,
        budgetAlertsEnabled: alertsEnabled,
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã lưu trên thiết bị nhưng chưa đồng bộ cài đặt cloud: '
            '${friendlyMessage(error)}',
          ),
        ),
      );
    }
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
  final isEn = context.tr.isEn;
  return showDialog<_CloudBackupSelection>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.cloud_queue_outlined),
      title: Text(
        isEn ? 'Cloud Backups' : 'Bản sao lưu trực tuyến',
        maxLines: 3,
      ),
      content: SizedBox(
        width: 520,
        child: entries.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  isEn
                      ? 'No cloud backups found.'
                      : 'Tài khoản chưa có backup cloud.',
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
                          ? Text(isEn ? 'Encrypted backup' : 'Backup mã hóa')
                          : Text(details.join(' · ')),
                      trailing: Wrap(
                        spacing: 0,
                        children: [
                          IconButton(
                            tooltip: isEn ? 'Restore' : 'Khôi phục',
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
                            tooltip: isEn
                                ? 'Delete from cloud'
                                : 'Xóa khỏi cloud',
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
          child: Text(isEn ? 'Close' : 'Đóng'),
        ),
      ],
    ),
  );
}

Future<bool?> _confirmCloudBackupDelete(
  BuildContext context,
  CloudBackupEntry entry,
) {
  final isEn = context.tr.isEn;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.delete_outline),
      title: Text(
        isEn ? 'Delete cloud backup?' : 'Xóa backup cloud?',
        maxLines: 3,
      ),
      content: Text(
        isEn
            ? '“${entry.fileName}” will be deleted from your account and cannot be recovered.'
            : '“${entry.fileName}” sẽ bị xóa khỏi tài khoản và không thể khôi phục.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(isEn ? 'Cancel' : 'Hủy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(isEn ? 'Delete backup' : 'Xóa backup'),
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
  final isEn = context.tr.isEn;
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.restore_page_outlined),
      title: Text(
        isEn ? 'Restore Preview' : 'Xem trước bản khôi phục',
        maxLines: 3,
      ),
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
                label: isEn ? 'Ready to restore' : 'Sẵn sàng khôi phục',
                value: preview.readyCount,
                icon: Icons.check_circle_outline,
              ),
              _RestoreStat(
                label: isEn ? 'Skipped (duplicate)' : 'Bỏ qua do trùng',
                value: preview.duplicateCount,
                icon: Icons.content_copy_outlined,
              ),
              _RestoreStat(
                label: isEn ? 'Invalid data' : 'Dữ liệu không hợp lệ',
                value: preview.invalidCount,
                icon: Icons.error_outline,
              ),
              if (preview.issues.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  isEn ? 'Details to review' : 'Chi tiết cần kiểm tra',
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
          child: Text(isEn ? 'Cancel' : 'Hủy'),
        ),
        FilledButton.icon(
          onPressed: preview.canRestore
              ? () => Navigator.pop(dialogContext, true)
              : null,
          icon: const Icon(Icons.restore),
          label: Text(
            isEn
                ? 'Restore ${preview.readyCount}'
                : 'Khôi phục ${preview.readyCount}',
          ),
        ),
      ],
    ),
  );
}

Future<String?> _showBackupPasswordDialog(BuildContext context) async {
  final isEn = context.tr.isEn;
  final passwordController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  try {
    return await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.lock_outline),
        title: Text(
          isEn ? 'Unlock Encrypted Backup' : 'Mở backup mã hóa',
          maxLines: 3,
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FinmiTextField(
                controller: passwordController,
                autofocus: true,
                obscureText: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: isEn ? 'Backup password' : 'Mật khẩu backup',
                  hintText: isEn ? 'At least 8 characters' : 'Ít nhất 8 ký tự',
                  prefixIcon: const Icon(Icons.key_outlined),
                ),
                validator: (value) {
                  if (value == null || value.length < 8) {
                    return isEn
                        ? 'Password must have at least 8 characters'
                        : 'Mật khẩu phải có ít nhất 8 ký tự';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(isEn ? 'Cancel' : 'Hủy'),
          ),
          FilledButton.icon(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(dialogContext, passwordController.text);
              }
            },
            icon: const Icon(Icons.lock_open),
            label: Text(isEn ? 'Unlock' : 'Mở backup'),
          ),
        ],
      ),
    );
  } finally {
    passwordController.dispose();
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

String _backupDate(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year} $hour:$minute';
}

class _BackupManagement extends StatelessWidget {
  const _BackupManagement({
    required this.onManageCloud,
    required this.onRestoreJson,
  });

  final VoidCallback? onManageCloud;
  final VoidCallback onRestoreJson;

  @override
  Widget build(BuildContext context) {
    final isEn = context.tr.isEn;
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.cloud_queue_outlined),
          title: Text(
            isEn ? 'Manage Backups' : 'Quản lý bản sao lưu',
            maxLines: 3,
          ),
          subtitle: Text(
            onManageCloud == null
                ? (isEn
                      ? 'Sign in to view and restore cloud backups.'
                      : 'Đăng nhập để xem và khôi phục backup cloud.')
                : (isEn
                      ? 'View, restore or delete encrypted account backups.'
                      : 'Xem, khôi phục hoặc xóa các backup mã hóa của tài khoản.'),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: onManageCloud,
        ),
        ListTile(
          leading: const Icon(Icons.restore_page_outlined),
          title: Text(
            isEn
                ? 'Restore JSON or encrypted backup'
                : 'Khôi phục JSON hoặc backup mã hóa',
            maxLines: 3,
          ),
          subtitle: Text(
            isEn
                ? 'Supports legacy JSON and .hdbak; preview, skip duplicates before writing.'
                : 'Hỗ trợ JSON cũ và .hdbak; xem trước, bỏ qua bản trùng rồi mới ghi dữ liệu.',
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
    final isEn = context.tr.isEn;
    return ListTile(
      leading: const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      title: Text(isEn ? 'Loading…' : 'Đang tải…', maxLines: 3),
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
        for (final child in children)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(child: child),
          ),
      ],
    );
  }
}
