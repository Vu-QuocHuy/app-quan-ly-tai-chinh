import '../../features/income/presentation/transaction_entry_sheet.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/localization/app_strings.dart';
import '../../core/config/feature_flags.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers/app_providers.dart';
import '../../features/ingestion/application/import_coordinator.dart';
import '../../features/ingestion/application/import_queue.dart';
import '../../features/ingestion/data/pending_import_store.dart';
import '../../features/ingestion/domain/import_job.dart';
import '../../features/ingestion/domain/quick_transaction_parser.dart';
import '../../features/ingestion/presentation/import_source_sheet.dart';
import '../../features/income/presentation/income_entry_sheet.dart';
import '../../features/auth/presentation/complete_profile_dialog.dart';
import '../../features/payments/application/qr_payment_providers.dart';
import '../../features/notifications/data/budget_notification_service.dart';
import '../../shared/dialogs/confirm_dialog.dart';
import '../../shared/errors/error_presenter.dart';
import '../../shared/widgets/reading_pane.dart';
import '../theme/app_tokens.dart';
import '../../shared/widgets/finmi_brand.dart';
import '../../shared/widgets/finmi_assistant_button.dart';
import 'finmi_actions.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  static const _autoSyncInterval = Duration(minutes: 15);

  bool _isImporting = false;
  bool _isSyncing = false;
  bool _initialSyncComplete = false;
  bool _initialSyncStarted = false;
  String? _initialSyncLoadingFor;
  String? _initialSyncUserId;
  String? _initialSyncError;
  bool _syncRequestedWhileRunning = false;
  int _importIndex = 0;
  int _importTotal = 0;
  String? _importFileName;
  final _importQueue = ImportQueueController();
  Timer? _retryTimer;
  Timer? _autoSyncTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  DateTime? _lastAutoSyncAt;

  PendingImportStore get _pendingImportStore =>
      ref.read(pendingImportStoreProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      _onConnectivityChanged,
    );
    _startAutoSyncTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _autoSyncTimer?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startAutoSyncTimer();
      if (_initialSyncComplete) {
        unawaited(_syncCloud());
        unawaited(_processDueRecurringIncomes());
      } else if (_initialSyncStarted) {
        unawaited(_loadInitialData());
      }
      if (!kIsWeb) unawaited(_resumePendingImports());
    } else {
      _autoSyncTimer?.cancel();
      _autoSyncTimer = null;
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (!results.any((result) => result != ConnectivityResult.none)) return;
    ref.read(sharedGroupRefreshSignalProvider.notifier).state++;
    if (_initialSyncComplete) {
      _requestAutoSync();
    } else if (_initialSyncUserId != null) {
      unawaited(_loadInitialData());
    }
  }

  void _startAutoSyncTimer() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(
      _autoSyncInterval,
      (_) => _requestAutoSync(),
    );
  }

  Future<void> _syncCloud() async {
    if (!mounted || !_initialSyncComplete) return;
    if (_isSyncing) {
      _syncRequestedWhileRunning = true;
      return;
    }
    final flags = ref.read(featureFlagsProvider).value ?? FeatureFlags.defaults;
    if (!flags.cloudSync) return;
    _isSyncing = true;
    try {
      do {
        _syncRequestedWhileRunning = false;
        await ref.read(syncCoordinatorProvider).runOnce(batchSize: 100);
      } while (_syncRequestedWhileRunning && mounted);
    } on Object {
      // Manual sync exposes errors in the account screen. Resume sync is
      // best-effort so it never interrupts importing or offline usage.
    } finally {
      _isSyncing = false;
      if (_syncRequestedWhileRunning && mounted) {
        _syncRequestedWhileRunning = false;
        unawaited(_syncCloud());
      }
    }
  }

  Future<void> _loadInitialData() async {
    final userId = _initialSyncUserId;
    if (userId == null || _initialSyncLoadingFor == userId) return;
    _initialSyncLoadingFor = userId;
    setState(() => _initialSyncError = null);
    final flags = ref.read(featureFlagsProvider).value ?? FeatureFlags.defaults;
    if (ref.read(supabaseClientProvider) == null || !flags.cloudSync) {
      _initialSyncLoadingFor = null;
      if (mounted) {
        setState(() => _initialSyncComplete = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(showCompleteProfileDialogIfNeeded(context, ref));
          }
        });
      }
      return;
    }
    try {
      // A normal sync can stop after ten pages per data type.
      while (true) {
        if (!mounted || userId != _initialSyncUserId) return;
        final result = await ref
            .read(syncCoordinatorProvider)
            .runOnce(batchSize: 100);
        if (!result.upload.configured || !result.upload.signedIn) {
          throw StateError('Chưa có phiên đăng nhập để tải dữ liệu.');
        }
        if (!result.hasMore) {
          if (!mounted || userId != _initialSyncUserId) return;
          setState(() => _initialSyncComplete = true);
          unawaited(_processDueRecurringIncomes());
          if (!kIsWeb) unawaited(_resumePendingImports());
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              unawaited(showCompleteProfileDialogIfNeeded(context, ref));
            }
          });
          return;
        }
      }
    } on Object catch (error) {
      if (mounted && userId == _initialSyncUserId) {
        setState(() => _initialSyncError = friendlyMessage(error));
      }
    } finally {
      if (_initialSyncLoadingFor == userId) _initialSyncLoadingFor = null;
    }
  }

  Future<void> _processDueRecurringIncomes() async {
    try {
      final created = await ref.read(recurringIncomeProcessorProvider).runDue();
      if (created > 0 && mounted) {
        _showMessage('Đã tự ghi $created khoản thu cố định đến hạn.');
      }
    } on Object catch (error) {
      if (mounted) {
        _showMessage(
          'Không thể tự ghi khoản thu định kỳ: ${friendlyMessage(error)}',
          isError: true,
        );
      }
    }
  }

  void _requestAutoSync() {
    if (!mounted) return;
    if (_isSyncing) {
      _syncRequestedWhileRunning = true;
      return;
    }
    final now = DateTime.now();
    final previous = _lastAutoSyncAt;
    if (previous != null &&
        now.difference(previous) < const Duration(seconds: 15)) {
      return;
    }
    _lastAutoSyncAt = now;
    unawaited(_syncCloud());
  }

  List<NavigationDestination> _getDestinations(BuildContext context) {
    final tr = context.tr;
    return [
      NavigationDestination(
        icon: const Icon(CupertinoIcons.house),
        selectedIcon: const Icon(CupertinoIcons.house_fill),
        label: tr.navOverview,
      ),
      NavigationDestination(
        icon: const Icon(CupertinoIcons.chart_pie),
        selectedIcon: const Icon(CupertinoIcons.chart_pie_fill),
        label: tr.navBudgets,
      ),
      NavigationDestination(
        icon: const Icon(CupertinoIcons.group),
        selectedIcon: const Icon(CupertinoIcons.group_solid),
        label: tr.navGroups,
      ),
      NavigationDestination(
        icon: const Icon(CupertinoIcons.gear_alt),
        selectedIcon: const Icon(CupertinoIcons.gear_alt_fill),
        label: tr.navSettings,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final signedInUser = ref.watch(authUserProvider).valueOrNull;
    final userId =
        signedInUser?.id ??
        (ref.watch(supabaseClientProvider) == null ? 'local' : null);
    if (_initialSyncUserId != userId) {
      _initialSyncUserId = userId;
      _initialSyncStarted = false;
      _initialSyncComplete = false;
      _initialSyncError = null;
    }
    if (userId != null && !_initialSyncStarted) {
      _initialSyncStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadInitialData());
      });
    }
    if (userId == null && !_initialSyncComplete) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_initialSyncError == null)
                  const CircularProgressIndicator(),
                const SizedBox(height: AppSpacing.md),
                Text(
                  _initialSyncError == null
                      ? 'Đang tải đầy đủ dữ liệu tài khoản…'
                      : 'Chưa tải được dữ liệu tài khoản: $_initialSyncError',
                  textAlign: TextAlign.center,
                ),
                if (_initialSyncError != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: _loadInitialData,
                    child: const Text('Thử tải lại'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }
    ref.listen(plansProvider, (previous, next) {
      final plans = next.asData?.value;
      if (plans != null) {
        unawaited(_processDueRecurringIncomes());
        unawaited(
          BudgetNotificationService.instance
              .schedulePlanReminders(plans)
              .catchError((Object _) {}),
        );
      }
    });
    ref.listen(syncHealthProvider, (previous, next) {
      final health = next.asData?.value;
      if (health != null && health.pendingCount > 0) _requestAutoSync();
    });
    ref.listen(importRetrySignalProvider, (previous, next) {
      if (!_isImporting) unawaited(_resumePendingImports());
    });
    final width = MediaQuery.sizeOf(context).width;
    final pendingQrPayment = ref.watch(pendingQrPaymentDraftProvider);
    final hasActiveModal = ref.watch(hasActiveModalProvider).hasModal;
    final hideAssistant =
        ref.watch(hideFloatingAssistantProvider) || hasActiveModal;
    final useRail = AppBreakpoints.useRail(width);
    final largeText = MediaQuery.textScalerOf(context).scale(12) / 12 >= 1.3;
    final wrapNavigation = largeText || width < 360;
    final content = FinmiActions(
      openSource: (source) => _openSource(source),
      scanReceipt: () => _openSource(ImportSource.scan, receipt: true),
      child: widget.navigationShell,
    );
    final scheme = Theme.of(context).colorScheme;
    final tr = context.tr;
    final invoiceAction = _isImporting ? _cancelImport : _showImportSources;
    final invoiceActionTooltip = _isImporting
        ? _importFileName == null
              ? tr.navCancelImport
              : 'Đang xử lý $_importFileName · Nhấn để hủy'
        : tr.navTransaction;
    final invoiceActionIcon = _isImporting
        ? const Icon(Icons.stop_circle_outlined)
        : const Icon(Icons.add_rounded);
    final invoiceActionLabel = _isImporting
        ? '${tr.cancel} $_importIndex/$_importTotal'
        : tr.navTransaction;
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                if (!_initialSyncComplete && _initialSyncError == null)
                  const LinearProgressIndicator(minHeight: 2),
                if (_initialSyncError != null)
                  MaterialBanner(
                    content: Text(
                      'Chưa tải được dữ liệu tài khoản: $_initialSyncError',
                    ),
                    actions: [
                      TextButton(
                        onPressed: _loadInitialData,
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                if (pendingQrPayment.valueOrNull != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      AppSpacing.sm,
                      AppSpacing.gutter,
                      0,
                    ),
                    child: Material(
                      color: scheme.tertiaryContainer,
                      shape: AppShapes.card,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.pending_actions_outlined,
                                  color: scheme.onTertiaryContainer,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Có khoản thanh toán QR đang chờ xác nhận. Chưa ghi vào chi tiêu.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: scheme.onTertiaryContainer,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton(
                                onPressed: () => context.push('/qr-payment'),
                                child: const Text('Tiếp tục'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Row(
                    children: [
                      if (useRail)
                        NavigationRail(
                          backgroundColor: scheme.surfaceContainerLow,
                          groupAlignment: -0.85,
                          minWidth: 84,
                          selectedIndex: widget.navigationShell.currentIndex,
                          onDestinationSelected: _goBranch,
                          labelType: NavigationRailLabelType.all,
                          leading: const Padding(
                            padding: EdgeInsets.only(bottom: 24),
                            child: FinmiBrand(width: 76),
                          ),
                          destinations: _getDestinations(context)
                              .map(
                                (item) => NavigationRailDestination(
                                  icon: item.icon,
                                  selectedIcon: item.selectedIcon,
                                  label: Text(item.label),
                                ),
                              )
                              .toList(growable: false),
                        ),
                      if (useRail)
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: scheme.outlineVariant,
                        ),
                      // Dashboard dùng thêm chiều ngang cho biểu đồ; các trang đọc
                      // và chỉnh sửa vẫn giữ bề rộng dễ quét.
                      Expanded(
                        child: useRail
                            ? ReadingPane(
                                maxWidth:
                                    widget.navigationShell.currentIndex == 0
                                    ? AppBreakpoints.twoColumnWidth
                                    : AppBreakpoints.readingWidth,
                                child: content,
                              )
                            : content,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!hideAssistant && (!wrapNavigation || useRail))
            Positioned(
              right: AppSpacing.gutter,
              bottom: _isImporting ? 96 : AppSpacing.lg,
              child: const FinmiAssistantButton(),
            ),
        ],
      ),
      bottomNavigationBar: useRail
          ? null
          : SafeArea(
              top: false,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  border: Border(
                    top: BorderSide(color: scheme.outlineVariant, width: 1.25),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final scale =
                          MediaQuery.textScalerOf(context).scale(12) / 12;
                      final destinations = <Widget>[
                        _bottomDestination(context, 0),
                        _bottomDestination(context, 1),
                        Expanded(
                          child: Semantics(
                            button: true,
                            label: _isImporting
                                ? tr.navCancelImport
                                : tr.navScanTooltip,
                            child: InkWell(
                              onTap: _isImporting
                                  ? _cancelImport
                                  : () => _openSource(ImportSource.scan),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                  vertical: 4,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: scheme.primary,
                                        borderRadius: AppShapes.controlRadius,
                                      ),
                                      child: Icon(
                                        _isImporting
                                            ? Icons.stop_circle_outlined
                                            : Icons.qr_code_scanner_rounded,
                                        color: scheme.onPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        _bottomDestination(context, 2),
                        _bottomDestination(context, 3),
                      ];
                      if (wrapNavigation) {
                        final columns = scale >= 1.8 ? 2 : 3;
                        return Wrap(
                          children: [
                            for (final item in [
                              ...destinations,
                              if (!hideAssistant)
                                const Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.all(6),
                                    child: FinmiAssistantButton(),
                                  ),
                                ),
                            ])
                              SizedBox(
                                width: constraints.maxWidth / columns,
                                child: Row(children: [item]),
                              ),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: destinations,
                      );
                    },
                  ),
                ),
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _isImporting
          ? FloatingActionButton.extended(
              onPressed: invoiceAction,
              tooltip: invoiceActionTooltip,
              icon: invoiceActionIcon,
              label: Text(invoiceActionLabel),
            )
          : null,
    );
  }

  Widget _bottomDestination(BuildContext context, int index) {
    final destination = _getDestinations(context)[index];
    final selected = widget.navigationShell.currentIndex == index;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        child: Semantics(
          button: true,
          selected: selected,
          label: destination.label,
          excludeSemantics: true,
          onTap: () => _goBranch(index),
          child: Material(
            color: selected ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () => _goBranch(index),
              borderRadius: BorderRadius.circular(10),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 62),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 7,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconTheme(
                        data: IconThemeData(
                          size: 20,
                          color: selected
                              ? scheme.onPrimary
                              : scheme.onSurface.withValues(alpha: 0.78),
                        ),
                        child: destination.icon,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        destination.label,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11.5,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: selected
                              ? scheme.onPrimary
                              : scheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _goBranch(int index) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  Future<void> _showImportSources() async {
    await showTransactionEntry(context);
  }

  Future<void> _openSource(ImportSource source, {bool receipt = false}) async {
    if (_isImporting) {
      _showMessage('Đang đọc hóa đơn. Vui lòng đợi hoặc hủy tác vụ hiện tại.');
      return;
    }
    switch (source) {
      case ImportSource.quick:
        await _showQuickEntry();
      case ImportSource.income:
        await showModalBottomSheet<bool>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          useRootNavigator: true,
          builder: (context) => const IncomeEntrySheet(),
        );
      case ImportSource.scan:
        if (mounted) {
          context.push(
            receipt ? '/qr-payment?tab=receipt' : '/qr-payment',
            extra: (XFile image) => _importImageFile(image),
          );
        }
      case ImportSource.manual:
        final draft = ref.read(importCoordinatorProvider).createManualDraft();
        if (mounted) context.push('/review', extra: draft);
      case ImportSource.history:
        if (mounted) context.push('/invoices');
    }
  }

  Future<void> _showQuickEntry() async {
    final controller = TextEditingController();
    String? error;
    final transaction = await showDialog<QuickTransaction>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Nhập nhanh giao dịch'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 300,
            decoration: InputDecoration(
              hintText: 'Ví dụ: ăn trưa 35k hôm qua',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  Navigator.pop(
                    dialogContext,
                    QuickTransactionParser.parse(controller.text),
                  );
                } on FormatException catch (exception) {
                  update(() => error = exception.message);
                }
              },
              child: const Text('Kiểm tra'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (transaction == null || !mounted) return;
    final categories = transaction.isIncome
        ? ref.read(incomeCategoriesProvider).valueOrNull
        : ref.read(categoriesProvider).valueOrNull;
    final categoryId = categories
        ?.where(
          (category) => transaction.title.toLowerCase().contains(
            category.name.toLowerCase(),
          ),
        )
        .firstOrNull
        ?.id;
    if (transaction.isIncome) {
      await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        useRootNavigator: true,
        builder: (context) => IncomeEntrySheet(
          initialAmountMinor: transaction.amountMinor,
          initialDate: transaction.date,
          initialCategoryId: categoryId,
        ),
      );
    } else {
      final draft = ref.read(importCoordinatorProvider).createManualDraft();
      if (mounted) {
        context.push(
          '/review',
          extra: draft.copyWith(
            sellerName: transaction.title,
            subtotalMinor: transaction.amountMinor,
            totalMinor: transaction.amountMinor,
            issuedAt: transaction.date,
            categoryId: categoryId,
          ),
        );
      }
    }
  }

  Future<void> _importImageFile(XFile image) async {
    final imageLength = await image.length();
    if (imageLength <= 0 || imageLength > AppConstants.maxImportBytes) {
      _showMessage('Ảnh phải có kích thước từ 1 đến 15 MB.');
      return;
    }
    final bytes = await image.readAsBytes();
    if (bytes.isEmpty || bytes.length > AppConstants.maxImportBytes) {
      _showMessage('Không thể đọc ảnh đã chọn.');
      return;
    }
    if (kIsWeb) {
      final coordinator = ref.read(importCoordinatorProvider);
      await _runImportBatch(
        fileNames: [image.name],
        operation: (_) => coordinator.importImage(
          bytes: bytes,
          fileName: image.name,
          imagePath: image.name,
        ),
      );
      return;
    }
    final pending = await _pendingImportStore.enqueue(
      bytes: bytes,
      fileName: image.name,
      kind: PendingImportKind.image,
    );
    await ref.read(importJobStoreProvider).ensureQueued(pending);
    await _runImportBatch(
      fileNames: [pending.fileName],
      operation: (_) => _processPendingImport(pending),
      onCompleted: (_) => _completePendingImport(pending),
      onDeferred: (_) => _deferPendingImport(pending),
    );
  }

  Future<ImportOutcome> _processPendingImport(PendingImport item) async {
    final jobs = ref.read(importJobStoreProvider);
    if (!await jobs.markRunning(item.id)) {
      throw StateError('Tác vụ chưa đến thời điểm thử lại.');
    }
    try {
      final bytes = await _pendingImportStore.readBytes(item);
      final coordinator = ref.read(importCoordinatorProvider);
      final outcome = item.kind == PendingImportKind.image
          ? await coordinator.importImage(
              bytes: bytes,
              fileName: item.fileName,
              imagePath: await _pendingImportStore.filePath(item),
            )
          : await coordinator.importFile(
              bytes: bytes,
              fileName: item.fileName,
              localPath: await _pendingImportStore.filePath(item),
            );
      await jobs.markAwaitingReview(item.id);
      return outcome;
    } on Object catch (error) {
      await jobs.markFailed(item.id, error);
      _schedulePendingResume();
      rethrow;
    }
  }

  Future<void> _resumePendingImports() async {
    await Future<void>.delayed(Duration.zero);
    if (kIsWeb || !mounted || _isImporting) return;
    try {
      final stored = await _pendingImportStore.list();
      final jobs = ref.read(importJobStoreProvider);
      final pending = <PendingImport>[];
      for (final item in stored) {
        final job = await jobs.find(item.id);
        if (job?.state == ImportJobState.succeeded) {
          await _pendingImportStore.remove(item);
          continue;
        }
        await jobs.ensureQueued(item);
        if (await jobs.isRunnable(item.id)) pending.add(item);
      }
      if (pending.isEmpty || !mounted) {
        _schedulePendingResume();
        return;
      }
      _showMessage(
        'Đang tiếp tục ${pending.length} file import chưa hoàn tất.',
      );
      await _runImportBatch(
        fileNames: pending.map((item) => item.fileName).toList(growable: false),
        operation: (index) => _processPendingImport(pending[index]),
        onCompleted: (index) => _completePendingImport(pending[index]),
        onDeferred: (index) => _deferPendingImport(pending[index]),
      );
      _schedulePendingResume();
    } on Object catch (error) {
      if (mounted) {
        _showMessage('Không thể tiếp tục import: ${friendlyMessage(error)}');
      }
    }
  }

  void _schedulePendingResume() {
    _retryTimer?.cancel();
    unawaited(() async {
      final delay = await ref
          .read(importJobStoreProvider)
          .delayUntilNextRetry();
      if (!mounted || delay == null) return;
      _retryTimer = Timer(delay, () => unawaited(_resumePendingImports()));
    }());
  }

  Future<void> _runImportBatch({
    required List<String> fileNames,
    required Future<ImportOutcome> Function(int index) operation,
    Future<void> Function(int index)? onCompleted,
    Future<void> Function(int index)? onDeferred,
  }) async {
    if (fileNames.isEmpty || !mounted) return;
    final jobs = List<ImportQueueJob>.generate(
      fileNames.length,
      (index) => ImportQueueJob(
        fileName: fileNames[index],
        operation: () => operation(index),
        onCompleted: onCompleted == null ? null : () => onCompleted(index),
        onDeferred: onDeferred == null ? null : () => onDeferred(index),
      ),
      growable: false,
    );
    setState(() {
      _isImporting = true;
      _importIndex = 0;
      _importTotal = fileNames.length;
      _importFileName = null;
    });
    try {
      final summary = await _importQueue.run(
        jobs: jobs,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _importIndex = progress.currentIndex;
            _importFileName = progress.currentFileName;
          });
        },
        onOutcome: (_, outcome) => _openImportOutcome(outcome),
        onFailure: (failure) {
          if (mounted) {
            _showMessage(
              '${failure.job.fileName}: ${friendlyMessage(failure.error)}',
              isError: true,
            );
          }
        },
      );
      if (mounted && summary.cancelled) {
        _showMessage(
          'Đã hủy import; các file chưa chạy vẫn có thể tiếp tục sau.',
        );
      } else if (mounted && summary.deferred > 0) {
        _showMessage(
          'Đã giữ ${summary.deferred} hóa đơn chờ bạn xác nhận.'
          '${summary.failed > 0 ? ' Có file lỗi cần thử lại.' : ''}',
        );
      } else if (mounted && summary.total > 1) {
        _showMessage(
          summary.failed == 0
              ? 'Đã xử lý ${summary.succeeded}/${summary.total} file.'
              : 'Đã xử lý ${summary.succeeded}/${summary.total} file; có file lỗi cần thử lại.',
        );
      }
    } on Object catch (error) {
      if (mounted) _showMessage(friendlyMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _importFileName = null;
        });
      }
    }
  }

  Future<void> _cancelImport() async {
    if (!_isImporting) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Hủy xử lý hóa đơn?',
      message:
          'Tệp đang xử lý sẽ hoàn tất trước khi dừng. Các tệp còn lại vẫn '
          'được giữ để tiếp tục sau.',
      confirmLabel: 'Hủy xử lý',
      cancelLabel: 'Tiếp tục xử lý',
      destructive: true,
    );
    if (!confirmed || !mounted || !_isImporting) return;
    _importQueue.cancel();
    _showMessage('Đang hủy sau khi hoàn tất file hiện tại…');
  }

  Future<ImportQueueDecision> _openImportOutcome(ImportOutcome outcome) async {
    if (!mounted) return ImportQueueDecision.deferred;
    if (outcome.exactDuplicate != null) {
      _showMessage('Hóa đơn này đã có trong danh sách.');
      await context.push('/invoices/${outcome.exactDuplicate!.id}');
      return ImportQueueDecision.completed;
    }
    if (outcome.likelyDuplicate != null) {
      _showMessage('Có một hóa đơn tương tự. Hãy kiểm tra trước khi lưu.');
    }
    if (outcome.result.adapterName == 'offline-text-fallback') {
      _showMessage(
        'Đã dùng bộ trích xuất offline. Hãy kiểm tra kỹ các trường trước khi lưu.',
      );
    }
    final saved = await context.push<bool>(
      '/review',
      extra: outcome.result.invoice,
    );
    if (saved == true) await _saveSourceImage(outcome);
    return saved == true
        ? ImportQueueDecision.completed
        : ImportQueueDecision.deferred;
  }

  Future<void> _saveSourceImage(ImportOutcome outcome) async {
    final bytes = outcome.sourceImageBytes;
    final fileName = outcome.sourceImageFileName;
    if (bytes == null || fileName == null) return;

    Object? localError;
    try {
      await ref
          .read(databaseProvider)
          .saveInvoiceOriginalImage(
            invoiceId: outcome.result.invoice.id,
            fileName: fileName,
            imageBytes: bytes,
          );
    } on Object catch (error) {
      localError = error;
    }

    Object? cloudError;
    final flags = ref.read(featureFlagsProvider).value ?? FeatureFlags.defaults;
    if (flags.cloudSync) {
      try {
        final store = ref.read(invoiceAttachmentStoreProvider);
        if (store == null) throw StateError('Supabase chưa được cấu hình.');
        await ref.read(syncCoordinatorProvider).runOnce(batchSize: 100);
        await store.upload(
          invoiceId: outcome.result.invoice.id,
          fileName: fileName,
          bytes: bytes,
        );
        ref.invalidate(invoiceAttachmentsProvider(outcome.result.invoice.id));
      } on Object catch (error) {
        cloudError = error;
      }
    }

    if (!mounted) return;
    if (localError != null) {
      _showMessage(
        'Hóa đơn đã lưu, nhưng ảnh gốc chưa lưu được trên thiết bị: '
        '${friendlyMessage(localError)}.',
        isError: true,
      );
    } else if (cloudError != null) {
      _showMessage(
        'Ảnh gốc đã lưu trên thiết bị, nhưng chưa đồng bộ lên cloud: '
        '${friendlyMessage(cloudError)}. Bạn có thể thử lại trong mục Chứng từ gốc.',
        isError: true,
      );
    }
  }

  Future<void> _completePendingImport(PendingImport item) async {
    final jobs = ref.read(importJobStoreProvider);
    await jobs.markSucceeded(item.id);
    try {
      await _pendingImportStore.remove(item);
    } on Object {
      _schedulePendingResume();
    }
  }

  Future<void> _deferPendingImport(PendingImport item) {
    return ref.read(importJobStoreProvider).markAwaitingReview(item.id);
  }

  void _showMessage(String message, {bool isError = false}) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
          content: Row(
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.info_outline,
                size: 18,
                color: isError ? scheme.onError : scheme.onInverseSurface,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: isError ? scheme.error : null,
        ),
      );
  }
}
