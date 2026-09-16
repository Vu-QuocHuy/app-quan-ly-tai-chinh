import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers/app_providers.dart';
import '../../features/ingestion/application/import_coordinator.dart';
import '../../features/ingestion/application/import_queue.dart';
import '../../features/ingestion/data/pending_import_store.dart';
import '../../features/ingestion/data/qr_scanner_service.dart';
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
  int _importIndex = 0;
  int _importTotal = 0;
  String? _importFileName;
  final _importQueue = ImportQueueController();
  final _pendingImportStore = PendingImportStore();
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_resumePendingImports());
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
    if (state == AppLifecycleState.resumed) unawaited(_syncCloud());
  }

  Future<void> _syncCloud() async {
    if (_isSyncing || !mounted) return;
    _isSyncing = true;
    try {
      await ref.read(syncCoordinatorProvider).runOnce();
    } on Object {
      // Manual sync exposes errors in the account screen. Resume sync is
      // best-effort so it never interrupts importing or offline usage.
    } finally {
      _isSyncing = false;
    }
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
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Cài đặt',
    ),
    NavigationDestination(
      icon: Icon(Icons.group_outlined),
      selectedIcon: Icon(Icons.group),
      label: 'Nhóm',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    ref.listen(importRetrySignalProvider, (previous, next) {
      if (!_isImporting) unawaited(_resumePendingImports());
    });
    final width = MediaQuery.sizeOf(context).width;
    final useRail = AppBreakpoints.useRail(width);
    final content = widget.navigationShell;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (useRail)
              NavigationRail(
                selectedIndex: widget.navigationShell.currentIndex,
                onDestinationSelected: _goBranch,
                labelType: NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Icon(
                    Icons.receipt_long,
                    color: Theme.of(context).colorScheme.primary,
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
            // Khi rail xuất hiện, nội dung được ràng vào bề rộng đọc và canh
            // giữa thay vì kéo dài hết cửa sổ.
            Expanded(child: useRail ? ReadingPane(child: content) : content),
          ],
        ),
      ),
      bottomNavigationBar: useRail
          ? null
          : NavigationBar(
              selectedIndex: widget.navigationShell.currentIndex,
              onDestinationSelected: _goBranch,
              destinations: _destinations,
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isImporting ? _cancelImport : _showImportSources,
        tooltip: _isImporting && _importFileName != null
            ? 'Đang xử lý $_importFileName · Nhấn để hủy'
            : 'Thêm giao dịch',
        icon: _isImporting
            ? const Icon(Icons.stop_circle_outlined)
            : const Icon(Icons.add_a_photo_outlined),
        label: Text(
          _isImporting ? 'Hủy $_importIndex/$_importTotal' : 'Thêm giao dịch',
        ),
      ),
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
      case ImportSource.qr:
        await _scanQr();
    }
  }

  Future<void> _pickDocument() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xml', 'pdf'],
    );
    if (files.isEmpty) return;
    final pending = <PendingImport>[];
    for (final file in files) {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
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
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final image = await ImagePicker().pickImage(
      source: source,
      imageQuality: 92,
      maxWidth: 2400,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (bytes.isEmpty) {
      _showMessage('Không thể đọc ảnh đã chọn.');
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
    );
  }

  Future<void> _scanQr() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 100,
      maxWidth: 3000,
    );
    if (image == null || !mounted) return;
    try {
      final payload = await QrScannerService().scanFile(image.path);
      if (!mounted) return;
      if (payload == null) {
        _showMessage(
          'Không tìm thấy mã QR trong ảnh. Hãy thử lại với khung hình rõ hơn.',
        );
        return;
      }
      await _showQrResult(payload);
    } on FormatException catch (error) {
      if (mounted) _showMessage(friendlyMessage(error));
    } on Object catch (error) {
      if (mounted) _showMessage('Không thể đọc QR: ${friendlyMessage(error)}');
    }
  }

  Future<void> _showQrResult(QrPayload payload) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.qr_code_2, size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'Đã đọc mã QR',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SelectableText(payload.rawValue),
              const SizedBox(height: 12),
              Text(
                payload.kind == QrPayloadKind.url
                    ? 'Đây là URL của nhà cung cấp. Tra cứu online sẽ chỉ bật sau khi cấu hình allowlist backend an toàn.'
                    : 'Đây là mã QR dạng text; chưa đủ dữ liệu để tự tạo hóa đơn.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('Đóng'),
                ),
              ),
            ],
          ),
        ),
      ),
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
      await jobs.markSucceeded(item.id);
      await _pendingImportStore.remove(item);
      return outcome;
    } on Object catch (error) {
      await jobs.markFailed(item.id, error);
      _schedulePendingResume();
      rethrow;
    }
  }

  Future<void> _resumePendingImports() async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted || _isImporting) return;
    try {
      final stored = await _pendingImportStore.list();
      final jobs = ref.read(importJobStoreProvider);
      for (final item in stored) {
        await jobs.ensureQueued(item);
      }
      final pending = <PendingImport>[];
      for (final item in stored) {
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
  }) async {
    if (fileNames.isEmpty || !mounted) return;
    final jobs = List<ImportQueueJob>.generate(
      fileNames.length,
      (index) => ImportQueueJob(
        fileName: fileNames[index],
        operation: () => operation(index),
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

  Future<void> _openImportOutcome(ImportOutcome outcome) async {
    if (!mounted) return;
    if (outcome.exactDuplicate != null) {
      _showMessage('Hóa đơn này đã có trong danh sách.');
      await context.push('/invoices/${outcome.exactDuplicate!.id}');
      return;
    }
    if (outcome.likelyDuplicate != null) {
      _showMessage('Có một hóa đơn tương tự. Hãy kiểm tra trước khi lưu.');
    }
    if (outcome.result.adapterName == 'offline-text-fallback') {
      _showMessage(
        'Đã dùng bộ trích xuất offline. Hãy kiểm tra kỹ các trường trước khi lưu.',
      );
    }
    await context.push('/review', extra: outcome.result.invoice);
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
