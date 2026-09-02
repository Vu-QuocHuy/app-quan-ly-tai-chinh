import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../invoices/domain/invoice_models.dart';

class SyncConflictsScreen extends ConsumerWidget {
  const SyncConflictsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conflicts = ref.watch(invoiceConflictsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Xung đột đồng bộ')),
      body: SafeArea(
        child: conflicts.when(
          data: (items) => items.isEmpty
              ? const _EmptyConflicts()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) => _ConflictCard(
                    conflict: items[index],
                    onKeepLocal: () => _resolve(
                      context,
                      ref,
                      items[index].local.id,
                      keepLocal: true,
                    ),
                    onUseCloud: () => _resolve(
                      context,
                      ref,
                      items[index].local.id,
                      keepLocal: false,
                    ),
                  ),
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Không đọc được xung đột: $error'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _resolve(
    BuildContext context,
    WidgetRef ref,
    String invoiceId, {
    required bool keepLocal,
  }) async {
    try {
      final repository = ref.read(invoiceRepositoryProvider);
      if (keepLocal) {
        await repository.resolveInvoiceConflictKeepLocal(invoiceId);
      } else {
        await repository.resolveInvoiceConflictUseRemote(invoiceId);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            keepLocal
                ? 'Đã giữ bản trên thiết bị và xếp lại để đồng bộ.'
                : 'Đã áp dụng bản cloud trên thiết bị.',
          ),
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể xử lý xung đột: $error')),
      );
    }
  }
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({
    required this.conflict,
    required this.onKeepLocal,
    required this.onUseCloud,
  });

  final InvoiceConflictEntity conflict;
  final VoidCallback onKeepLocal;
  final VoidCallback onUseCloud;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final local = conflict.local;
    final remote = conflict.remote;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              local.sellerName.isEmpty
                  ? 'Hóa đơn chưa có tên'
                  : local.sellerName,
              style: theme.textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              'Phát hiện ${_formatDate(conflict.detectedAt)} · revision cloud ${remote.revision}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            _ComparisonHeader(),
            const SizedBox(height: 8),
            _ComparisonRow(
              label: 'Nhà bán',
              localValue: local.sellerName,
              remoteValue: remote.sellerName,
            ),
            _ComparisonRow(
              label: 'Tổng tiền',
              localValue: _money(local.totalMinor, local.currencyCode),
              remoteValue: _money(remote.totalMinor, remote.currencyCode),
            ),
            _ComparisonRow(
              label: 'Số hóa đơn',
              localValue: local.invoiceNumber ?? 'Chưa có',
              remoteValue: remote.invoiceNumber ?? 'Chưa có',
            ),
            _ComparisonRow(
              label: 'Danh mục',
              localValue: local.categoryId ?? 'Chưa phân loại',
              remoteValue: remote.categoryId ?? 'Chưa phân loại',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: onUseCloud,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('Dùng bản cloud'),
                ),
                FilledButton.icon(
                  onPressed: onKeepLocal,
                  icon: const Icon(Icons.phone_android_outlined),
                  label: const Text('Giữ bản trên máy'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _money(int value, String currency) => '$value $currency';

  static String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year} ${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _ComparisonHeader extends StatelessWidget {
  const _ComparisonHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.primary,
    );
    return Row(
      children: [
        const SizedBox(width: 84),
        Expanded(child: Text('Trên máy', style: style)),
        const SizedBox(width: 12),
        Expanded(
          child: Text('Cloud', style: style, textAlign: TextAlign.end),
        ),
      ],
    );
  }
}

class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({
    required this.label,
    required this.localValue,
    required this.remoteValue,
  });

  final String label;
  final String localValue;
  final String remoteValue;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 84, child: Text(label, style: textTheme.bodySmall)),
          Expanded(
            child: Text(
              localValue,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              remoteValue,
              style: textTheme.bodyMedium,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyConflicts extends StatelessWidget {
  const _EmptyConflicts();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_done_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Dữ liệu đã nhất quán',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'Khi hai thiết bị cùng sửa một hóa đơn, bạn có thể chọn bản muốn giữ tại đây.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
