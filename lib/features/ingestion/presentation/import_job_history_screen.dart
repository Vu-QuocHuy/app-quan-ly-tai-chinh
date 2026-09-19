import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/app_providers.dart';
import '../domain/import_job.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../../app/theme/finance_colors.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/app_empty_state.dart';
import '../../../shared/widgets/app_error_state.dart';

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
        error: (error, stack) => AppErrorState(
          error: error,
          stackTrace: stack,
          title: 'Không tải được lịch sử',
          retryLabel: 'Tải lại',
          onRetry: () => ref.invalidate(importJobsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const AppEmptyState(
              icon: Icons.history,
              title: 'Chưa có tác vụ nhập hóa đơn',
              message:
                  'Khi bạn nhập hóa đơn từ file, ảnh hoặc camera, tiến độ và '
                  'các lần thử lại sẽ xuất hiện ở đây.',
            );
          }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể thử lại: ${friendlyMessage(error)}')),
      );
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
        SnackBar(
          content: Text(
            'Không thể thử lại hàng loạt: ${friendlyMessage(error)}',
          ),
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không thể dọn lịch sử: ${friendlyMessage(error)}'),
        ),
      );
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
            if (job.state == ImportJobState.awaitingReview) ...[
              const SizedBox(height: 8),
              Text(
                'Đã trích xuất; mở lại để kiểm tra và lưu hóa đơn.',
                style: Theme.of(context).textTheme.bodySmall,
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
    // StatusPill ép icon + label là bắt buộc, nên trạng thái không bao giờ chỉ
    // được truyền đạt bằng màu. Trước đây Chip tính `presentation.color` rồi
    // vứt đi — màu không tới được đâu cả.
    return StatusPill(
      icon: presentation.icon,
      label: presentation.label,
      tone: jobStatusTone(job.state),
      semanticsLabel: 'Trạng thái ${presentation.label}',
    );
  }
}

class _JobPresentation {
  const _JobPresentation(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color Function(BuildContext context) color;
}

/// Tone lấy từ AppFinanceColors nên nó theo theme. Trước đây trạng thái
/// "Hoàn tất" dùng `Colors.green` cứng — mù theme và tương phản kém trên nền
/// tối.
_JobPresentation _presentation(ImportJobState state) => switch (state) {
  ImportJobState.queued => _JobPresentation(
    'Đang chờ',
    Icons.schedule,
    (context) => context.finance.syncPending.color,
  ),
  ImportJobState.running => _JobPresentation(
    'Đang chạy',
    Icons.sync,
    (context) => context.finance.syncPending.color,
  ),
  ImportJobState.awaitingReview => _JobPresentation(
    'Chờ xác nhận',
    Icons.fact_check_outlined,
    (context) => context.finance.syncPending.color,
  ),
  ImportJobState.succeeded => _JobPresentation(
    'Hoàn tất',
    Icons.check_circle_outline,
    (context) => context.finance.syncOk.color,
  ),
  ImportJobState.retryScheduled => _JobPresentation(
    'Chờ thử lại',
    Icons.update,
    (context) => context.finance.syncConflict.color,
  ),
  ImportJobState.failed => _JobPresentation(
    'Thất bại',
    Icons.error_outline,
    (context) => Theme.of(context).colorScheme.error,
  ),
};

/// Tone tương ứng cho `StatusPill` — icon + chữ luôn đi kèm màu.
StatusTone jobStatusTone(ImportJobState state) => switch (state) {
  ImportJobState.queued ||
  ImportJobState.running ||
  ImportJobState.awaitingReview => StatusTone.info,
  ImportJobState.succeeded => StatusTone.safe,
  ImportJobState.retryScheduled => StatusTone.warn,
  ImportJobState.failed => StatusTone.danger,
};
