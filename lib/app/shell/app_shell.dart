import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/feature_flags.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers/app_providers.dart';
import '../../features/ingestion/application/import_coordinator.dart';
import '../../features/ingestion/application/import_queue.dart';
import '../../features/ingestion/data/pending_import_store.dart';
import '../../features/ingestion/domain/import_job.dart';
import '../../features/ingestion/presentation/import_source_sheet.dart';
import '../../shared/errors/error_presenter.dart';
import '../../shared/widgets/reading_pane.dart';
import '../theme/app_tokens.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  bool _isImporting = false;
  bool _isSyncing = false;
  bool _syncRequestedWhileRunning = false;
  int _importIndex = 0;
  int _importTotal = 0;
  String? _importFileName;
  final _importQueue = ImportQueueController();
  Timer? _retryTimer;
  DateTime? _lastAutoSyncAt;

  PendingImportStore get _pendingImportStore =>
      ref.read(pendingImportStoreProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb) unawaited(_resumePendingImports());
    unawaited(_syncCloud());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncCloud());
      if (!kIsWeb) unawaited(_resumePendingImports());
    }
  }

  Future<void> _syncCloud() async {
    if (!mounted) return;
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

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.space_dashboard_outlined),
      selectedIcon: Icon(Icons.space_dashboard),
      label: 'Tổng quan',
    ),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long),
      label: 'Hóa đơn',
    ),
    NavigationDestination(
      icon: Icon(Icons.savings_outlined),
      selectedIcon: Icon(Icons.savings),
      label: 'Ngân sách',
    ),
    NavigationDestination(
      icon: Icon(Icons.group_outlined),
      selectedIcon: Icon(Icons.group),
      label: 'Nhóm',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Cài đặt',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    ref.listen(syncHealthProvider, (previous, next) {
      final health = next.asData?.value;
      if (health != null && health.pendingCount > 0) _requestAutoSync();
    });
    ref.listen(importRetrySignalProvider, (previous, next) {
      if (!_isImporting) unawaited(_resumePendingImports());
    });
    final width = MediaQuery.sizeOf(context).width;
    final useRail = AppBreakpoints.useRail(width);
    final content = widget.navigationShell;
    final scheme = Theme.of(context).colorScheme;
    final showInvoiceAction = widget.navigationShell.currentIndex == 1;
    return Scaffold(
      body: SafeArea(
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
                leading: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                  child: Tooltip(
                    message: 'Quản lý Tài chính',
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: scheme.primary,
                        shape: AppShapes.control,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Icon(
                          Icons.account_balance_wallet_outlined,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
                destinations: _destinations
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
            // Khi rail xuất hiện, nội dung được ràng vào bề rộng đọc và canh
            // giữa thay vì kéo dài hết cửa sổ.
            Expanded(child: useRail ? ReadingPane(child: content) : content),
          ],
        ),
      ),
      bottomNavigationBar: useRail
          ? null
          : NavigationBar(
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              selectedIndex: widget.navigationShell.currentIndex,
              onDestinationSelected: _goBranch,
              destinations: _destinations,
            ),
      floatingActionButton: showInvoiceAction
          ? FloatingActionButton.extended(
              onPressed: _isImporting ? _cancelImport : _showImportSources,
              tooltip: _isImporting && _importFileName != null
                  ? 'Đang xử lý $_importFileName · Nhấn để hủy'
                  : 'Thêm hóa đơn',
              icon: _isImporting
                  ? const Icon(Icons.stop_circle_outlined)
                  : const Icon(Icons.add_a_photo_outlined),
              label: Text(
                _isImporting
                    ? 'Hủy $_importIndex/$_importTotal'
                    : 'Thêm hóa đơn',
              ),
            )
          : null,
    );
  }

  void _goBranch(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  Future<void> _showImportSources() async {
    final source = await showModalBottomSheet<ImportSource>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => const ImportSourceSheet(),
    );
    if (source == null || !mounted) return;
    switch (source) {
      case ImportSource.xmlOrPdf:
        await _pickDocument();
      case ImportSource.camera:
        await _pickImage(ImageSource.camera);
      case ImportSource.gallery:
        await _pickImage(ImageSource.gallery);
      case ImportSource.manual:
        final draft = ref.read(importCoordinatorProvider).createManualDraft();
        if (mounted) context.push('/review', extra: draft);
    }
  }

  Future<void> _pickDocument() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xml', 'pdf'],
    );
    if (files.isEmpty) return;
    if (kIsWeb) {
      final inputs = <({String fileName, Uint8List bytes})>[];
      for (final file in files) {
        final fileLength = await file.length();
        if (fileLength <= 0 || fileLength > AppConstants.maxImportBytes) {
          _showMessage('${file.name}: File phải có kích thước từ 1 đến 15 MB.');
          continue;
        }
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty || bytes.length > AppConstants.maxImportBytes) {
          _showMessage('${file.name}: Không thể đọc file đã chọn.');
          continue;
        }
        inputs.add((fileName: file.name, bytes: bytes));
      }
      if (inputs.isEmpty) return;
      final coordinator = ref.read(importCoordinatorProvider);
      await _runImportBatch(
        fileNames: inputs
            .map((input) => input.fileName)
            .toList(growable: false),
        operation: (index) {
          final input = inputs[index];
          return coordinator.importFile(
            bytes: input.bytes,
            fileName: input.fileName,
          );
        },
      );
      return;
    }
    final pending = <PendingImport>[];
    for (final file in files) {
      final fileLength = await file.length();
      if (fileLength <= 0 || fileLength > AppConstants.maxImportBytes) {
        _showMessage('${file.name}: File phải có kích thước từ 1 đến 15 MB.');
        continue;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || bytes.length > AppConstants.maxImportBytes) {
        _showMessage('${file.name}: Không thể đọc file đã chọn.');
        continue;
      }
      final item = await _pendingImportStore.enqueue(
        bytes: bytes,
        fileName: file.name,
        kind: PendingImportKind.document,
      );
      await ref.read(importJobStoreProvider).ensureQueued(item);
      pending.add(item);
    }
    if (pending.isEmpty) return;
    await _runImportBatch(
      fileNames: pending.map((item) => item.fileName).toList(growable: false),
      operation: (index) => _processPendingImport(pending[index]),
      onCompleted: (index) => _completePendingImport(pending[index]),
      onDeferred: (index) => _deferPendingImport(pending[index]),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final image = await ImagePicker().pickImage(
      source: source,
      imageQuality: 92,
      maxWidth: 2400,
    );
    if (image == null) return;
    await _importImageFile(image);
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

  void _cancelImport() {
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
    return saved == true
        ? ImportQueueDecision.completed
        : ImportQueueDecision.deferred;
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
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
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
