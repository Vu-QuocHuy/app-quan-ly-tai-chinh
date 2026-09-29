import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/providers/app_providers.dart';
import '../../../shared/errors/error_presenter.dart';
import '../../../shared/widgets/app_callout.dart';
import '../data/supabase_invoice_attachment_store.dart';

class InvoiceAttachmentsScreen extends ConsumerStatefulWidget {
  const InvoiceAttachmentsScreen({required this.invoiceId, super.key});

  final String invoiceId;

  @override
  ConsumerState<InvoiceAttachmentsScreen> createState() =>
      _InvoiceAttachmentsScreenState();
}

class _InvoiceAttachmentsScreenState
    extends ConsumerState<InvoiceAttachmentsScreen> {
  bool _uploading = false;
  String? _actionError;

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(invoiceAttachmentStoreProvider);
    final user = ref.watch(authUserProvider).value;
    final attachments = ref.watch(invoiceAttachmentsProvider(widget.invoiceId));

    return Scaffold(
      appBar: AppBar(title: const Text('Chứng từ gốc')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const AppCallout(
            icon: Icons.lock_outline,
            message:
                'Tệp được lưu trong Storage riêng tư của tài khoản. '
                'Chỉ bạn mới mở được liên kết tạm thời.',
          ),
          const SizedBox(height: 12),
          if (user == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 32),
                    const SizedBox(height: 8),
                    const Text('Đăng nhập để lưu chứng từ lên cloud.'),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: () => context.push('/settings/account'),
                      child: const Text('Đến tài khoản'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            FilledButton.icon(
              onPressed: _uploading || store == null ? null : _pickAndUpload,
              icon: _uploading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: Text(_uploading ? 'Đang tải chứng từ…' : 'Thêm chứng từ'),
            ),
            const SizedBox(height: 6),
            Text(
              'JPG, PNG, WebP hoặc PDF · tối đa 15 MB mỗi tệp',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_actionError case final message?) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text('Tệp đã lưu', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            attachments.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Card(
                child: ListTile(
                  leading: const Icon(Icons.cloud_off_outlined),
                  title: const Text('Không tải được chứng từ'),
                  subtitle: Text(friendlyMessage(error)),
                  trailing: IconButton(
                    tooltip: 'Thử tải lại',
                    onPressed: () => ref.invalidate(
                      invoiceAttachmentsProvider(widget.invoiceId),
                    ),
                    icon: const Icon(Icons.refresh),
                  ),
                ),
              ),
              data: (items) => items.isEmpty
                  ? Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            const Icon(Icons.receipt_long_outlined, size: 32),
                            const SizedBox(height: 8),
                            const Text('Chưa có chứng từ gốc.'),
                            const SizedBox(height: 4),
                            Text(
                              'Thêm ảnh hoặc PDF để giữ bản gốc cùng hóa đơn.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    )
                  : Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < items.length;
                            index++
                          ) ...[
                            if (index > 0) const Divider(height: 1),
                            _AttachmentTile(
                              attachment: items[index],
                              onOpen: () => _open(items[index]),
                              onDelete: () => _delete(items[index]),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickAndUpload() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );
    if (file == null || !mounted) return;
    setState(() {
      _uploading = true;
      _actionError = null;
    });
    try {
      final fileLength = await file.length();
      if (!mounted) return;
      if (fileLength > AppConstants.maxImportBytes) {
        throw const FormatException('Tệp vượt quá giới hạn 15 MB.');
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final store = ref.read(invoiceAttachmentStoreProvider);
      if (store == null) throw StateError('Supabase chưa được cấu hình.');
      await store.upload(
        invoiceId: widget.invoiceId,
        fileName: file.name,
        bytes: bytes,
      );
      ref.invalidate(invoiceAttachmentsProvider(widget.invoiceId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu chứng từ lên cloud.')),
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => _actionError = friendlyMessage(error));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _open(InvoiceAttachment attachment) async {
    try {
      final store = ref.read(invoiceAttachmentStoreProvider);
      if (store == null) throw StateError('Supabase chưa được cấu hình.');
      final uri = await store.signedUrl(attachment);
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw StateError('Không mở được tệp trên thiết bị này.');
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không mở được chứng từ: ${friendlyMessage(error)}'),
        ),
      );
    }
  }

  Future<void> _delete(InvoiceAttachment attachment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa chứng từ?'),
        content: Text('Tệp “${attachment.fileName}” sẽ bị xóa khỏi cloud.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Giữ lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final store = ref.read(invoiceAttachmentStoreProvider);
      if (store == null) throw StateError('Supabase chưa được cấu hình.');
      await store.delete(attachment);
      ref.invalidate(invoiceAttachmentsProvider(widget.invoiceId));
    } on Object catch (error) {
      if (mounted) setState(() => _actionError = friendlyMessage(error));
    }
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.onOpen,
    required this.onDelete,
  });

  final InvoiceAttachment attachment;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final icon = attachment.contentType == 'application/pdf'
        ? Icons.picture_as_pdf_outlined
        : Icons.image_outlined;
    final date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(attachment.createdAt.toLocal());
    return ListTile(
      leading: Icon(icon),
      title: Text(
        attachment.fileName,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('$date · ${_formatSize(attachment.sizeBytes)}'),
      onTap: onOpen,
      trailing: IconButton(
        tooltip: 'Xóa chứng từ',
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline),
      ),
    );
  }

  String _formatSize(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).ceil()} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
