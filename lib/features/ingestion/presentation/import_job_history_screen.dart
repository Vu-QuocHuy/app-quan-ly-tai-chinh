import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/app_providers.dart';
import '../domain/import_job.dart';

class ImportJobHistoryScreen extends ConsumerWidget {
  const ImportJobHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(importJobsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử nhập hóa đơn'),
        actions: [
          IconButton(
            tooltip: 'Thử lại tất cả tác vụ thất bại',
            onPressed: () => _retryAllFailed(context, ref),
            icon: const Icon(Icons.replay_outlined),
          ),
          PopupMenuButton<_HistoryAction>(
            tooltip: 'Tùy chọn lịch sử',
            onSelected: (action) {
              if (action == _HistoryAction.clearSucceeded) {
                _clearSucceeded(context, ref);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _HistoryAction.clearSucceeded,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.cleaning_services_outlined),
                  title: Text('Xóa lịch sử hoàn tất'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: jobs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ImportJobError(
          message: error.toString(),
          onRetry: () => ref.invalidate(importJobsProvider),
        ),
        data: (items) {
          if (items.isEmpty) return const _ImportJobEmpty();
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(importJobsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _ImportJobCard(
                job: items[index],
                onRetry: () => _retry(context, ref, items[index]),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _retry(
    BuildContext context,
    WidgetRef ref,
    ImportJobEntity job,
  ) async {
    try {
      await ref.read(importJobStoreProvider).retryNow(job.id);
      ref.read(importRetrySignalProvider.notifier).state++;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã xếp “${job.fileName}” để thử lại.')),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không thể thử lại: $error')));
    }
  }

  Future<void> _retryAllFailed(BuildContext context, WidgetRef ref) async {
    try {
      final count = await ref.read(importJobStoreProvider).retryAllFailed();
      if (count > 0) ref.read(importRetrySignalProvider.notifier).state++;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'Không có tác vụ thất bại cần thử lại.'
                : 'Đã xếp $count tác vụ để thử lại.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể thử lại hàng loạt: $error')),
      );
    }
  }

  Future<void> _clearSucceeded(BuildContext context, WidgetRef ref) async {
    try {
      final count = await ref.read(importJobStoreProvider).clearSucceeded();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã xóa $count mục lịch sử hoàn tất.')),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Không thể dọn lịch sử: $error')));
    }
  }
}

enum _HistoryAction { clearSucceeded }

class _ImportJobCard extends StatelessWidget {
  const _ImportJobCard({required this.job, required this.onRetry});

  final ImportJobEntity job;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final presentation = _presentation(job.state);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(presentation.icon, color: presentation.color(context)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    job.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StateBadge(job: job, presentation: presentation),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Lần chạy ${job.attemptCount}/${job.maxAttempts} · '
              '${DateFormat('dd/MM/yyyy HH:mm').format(job.updatedAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (job.nextRetryAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Tự thử lại lúc ${DateFormat('HH:mm:ss dd/MM').format(job.nextRetryAt!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (job.lastError != null) ...[
              const SizedBox(height: 8),
              Text(
                job.lastError!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            if (job.canRetry) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử lại ngay'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StateBadge extends StatelessWidget {
  const _StateBadge({required this.job, required this.presentation});

  final ImportJobEntity job;
  final _JobPresentation presentation;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Trạng thái ${presentation.label}',
      child: Chip(
        visualDensity: VisualDensity.compact,
        avatar: Icon(presentation.icon, size: 16),
        label: Text(presentation.label),
      ),
    );
  }
}

class _ImportJobEmpty extends StatelessWidget {
  const _ImportJobEmpty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 64),
            SizedBox(height: 16),
            Text('Chưa có tác vụ nhập hóa đơn.'),
          ],
        ),
      ),
    );
  }
}

class _ImportJobError extends StatelessWidget {
  const _ImportJobError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(
              'Không thể tải lịch sử: $message',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tải lại'),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobPresentation {
  const _JobPresentation(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color Function(BuildContext context) color;
}

_JobPresentation _presentation(ImportJobState state) => switch (state) {
  ImportJobState.queued => _JobPresentation(
    'Đang chờ',
    Icons.schedule,
    (context) => Theme.of(context).colorScheme.primary,
  ),
  ImportJobState.running => _JobPresentation(
    'Đang chạy',
    Icons.sync,
    (context) => Theme.of(context).colorScheme.primary,
  ),
  ImportJobState.succeeded => _JobPresentation(
    'Hoàn tất',
    Icons.check_circle_outline,
    (context) => Colors.green,
  ),
  ImportJobState.retryScheduled => _JobPresentation(
    'Chờ thử lại',
    Icons.update,
    (context) => Theme.of(context).colorScheme.tertiary,
  ),
  ImportJobState.failed => _JobPresentation(
    'Thất bại',
    Icons.error_outline,
    (context) => Theme.of(context).colorScheme.error,
  ),
};
