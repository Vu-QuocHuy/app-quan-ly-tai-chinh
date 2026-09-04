import 'package:flutter/material.dart';

enum ImportSource { xmlOrPdf, camera, gallery, manual, qr }

class ImportSourceSheet extends StatelessWidget {
  const ImportSourceSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Thêm giao dịch', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Ưu tiên XML để có dữ liệu chính xác nhất. Bạn luôn được kiểm tra trước khi lưu.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            _SourceTile(
              icon: Icons.upload_file,
              title: 'Nhập XML hoặc PDF',
              subtitle: 'Có thể chọn nhiều file; PDF cần có lớp text',
              onTap: () => Navigator.pop(context, ImportSource.xmlOrPdf),
            ),
            _SourceTile(
              icon: Icons.photo_camera_outlined,
              title: 'Chụp hóa đơn',
              subtitle: 'OCR trên thiết bị, sau đó kiểm tra dữ liệu',
              onTap: () => Navigator.pop(context, ImportSource.camera),
            ),
            _SourceTile(
              icon: Icons.photo_library_outlined,
              title: 'Chọn ảnh',
              subtitle: 'Dùng ảnh hóa đơn đã có trong máy',
              onTap: () => Navigator.pop(context, ImportSource.gallery),
            ),
            _SourceTile(
              icon: Icons.edit_note,
              title: 'Nhập thủ công',
              subtitle: 'Phù hợp khi không có file hoặc ảnh',
              onTap: () => Navigator.pop(context, ImportSource.manual),
            ),
            _SourceTile(
              icon: Icons.qr_code_scanner,
              title: 'Quét QR',
              subtitle: 'Đọc QR từ camera; tra cứu provider vẫn Experimental',
              onTap: () => Navigator.pop(context, ImportSource.qr),
            ),
          ],
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
    return Semantics(
      button: true,
      child: ListTile(
        minTileHeight: 64,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
