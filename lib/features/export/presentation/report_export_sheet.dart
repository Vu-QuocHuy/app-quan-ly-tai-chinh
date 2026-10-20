import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/month_utils.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../../shared/widgets/app_card.dart';
import '../../invoices/domain/invoice_models.dart';
import '../application/invoice_export_service.dart';

Future<void> showReportExportSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _ReportExportSheet(),
    );

class _ReportExportSheet extends ConsumerStatefulWidget {
  const _ReportExportSheet();
  @override
  ConsumerState<_ReportExportSheet> createState() => _ReportExportSheetState();
}

class _ReportExportSheetState extends ConsumerState<_ReportExportSheet> {
  bool _busy = false;
  String? _error;
  @override
  Widget build(BuildContext context) {
    final month = ref.watch(selectedMonthProvider);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Xuất báo cáo',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Đóng',
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              'Dữ liệu đã xác nhận · ${MonthUtils.label(month)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            for (final format in ['PDF', 'CSV'])
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  onTap: _busy ? null : () => _export(format),
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    enabled: !_busy,
                    leading: Icon(
                      format == 'PDF'
                          ? Icons.picture_as_pdf_outlined
                          : Icons.table_chart_outlined,
                    ),
                    title: Text('Báo cáo $format'),
                    subtitle: Text(
                      format == 'PDF'
                          ? 'Tổng quan và danh sách khoản chi'
                          : 'Dữ liệu khoản chi để mở bằng bảng tính',
                    ),
                    trailing: const Icon(Icons.download_outlined),
                  ),
                ),
              ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _export(String format) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final month = ref.read(selectedMonthProvider);
      final key = MonthUtils.key(month);
      final all = await ref
          .read(invoiceRepositoryProvider)
          .watchInvoiceSummaries()
          .first;
      final entries = all
          .where(
            (e) =>
                e.status == InvoiceStatus.confirmed &&
                MonthUtils.key(e.issuedAt ?? e.createdAt) == key,
          )
          .toList();
      const service = InvoiceExportService();
      final uri = format == 'PDF'
          ? await service.exportPdf(
              invoices: entries,
              dashboard: await ref.read(dashboardProvider.future),
              categories: await ref.read(categoriesProvider.future),
            )
          : await service.exportCsv(entries);
      if (!mounted) return;
      if (uri != null) {
        Navigator.pop(context);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = friendlyMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
