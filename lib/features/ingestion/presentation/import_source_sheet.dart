import 'package:flutter/material.dart';

enum ImportSource { income, scan, manual, history }

class ImportSourceSheet extends StatelessWidget {
  const ImportSourceSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Giao dịch', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Ghi khoản thu, khoản chi hoặc xem lại lịch sử.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              _SourceTile(
                icon: Icons.edit_note,
                title: 'Thêm khoản chi',
                subtitle: 'Không cần hóa đơn; nhập số tiền và danh mục',
                onTap: () => Navigator.pop(context, ImportSource.manual),
              ),
              _SourceTile(
                icon: Icons.add_circle_outline,
                title: 'Thêm khoản thu',
                subtitle: 'Chỉ nhập số tiền',
                onTap: () => Navigator.pop(context, ImportSource.income),
              ),
              _SourceTile(
                icon: Icons.document_scanner_outlined,
                title: 'Quét',
                subtitle: 'Chọn QR thanh toán hoặc OCR hóa đơn',
                onTap: () => Navigator.pop(context, ImportSource.scan),
              ),
              const Divider(),
              _SourceTile(
                icon: Icons.receipt_long_outlined,
                title: 'Lịch sử giao dịch',
                subtitle: 'Tìm kiếm và lọc các khoản thu chi đã ghi',
                onTap: () => Navigator.pop(context, ImportSource.history),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: Semantics(
          button: true,
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            minTileHeight: 64,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: Icon(icon, size: 21),
            ),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}
