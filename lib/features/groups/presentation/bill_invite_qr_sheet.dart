import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../domain/invite_link.dart';

/// Bottom sheet QR mời vào một bill. Chỉ mở sau khi `openBillInvite` thành
/// công, nên lời mời luôn đang mở; "Đóng lời mời" gọi [onCloseInvite] rồi đóng.
Future<void> showBillInviteQrSheet(
  BuildContext context, {
  required String description,
  required String joinCode,
  required Future<void> Function() onCloseInvite,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SizedBox(
      width: double.infinity,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Mời vào bill “$description”',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              const Text(
                'Người quét mã sẽ vào bill này, không vào nhóm.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // Nền trắng cố định để máy khác quét được cả khi app ở chế độ tối.
              Center(
                child: QrImageView(
                  data: InviteLink.billUri(joinCode),
                  size: 220,
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                  semanticsLabel: 'Mã QR mời vào bill $description',
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: SelectableText(
                  joinCode,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: joinCode));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã sao chép mã mời bill.')),
                    );
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Sao chép mã'),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await onCloseInvite();
                    if (context.mounted) Navigator.pop(context);
                  },
                  icon: const Icon(Icons.link_off_outlined),
                  label: const Text('Đóng lời mời'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
