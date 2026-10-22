import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../domain/invite_link.dart';

Future<void> showGroupInviteQrSheet(
  BuildContext context, {
  required String groupName,
  required String inviteCode,
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
                'Mời vào $groupName',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              // Nền trắng cố định để máy khác quét được cả khi app ở chế độ tối.
              Center(
                child: QrImageView(
                  data: InviteLink.groupUri(inviteCode),
                  size: 220,
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.all(16),
                  semanticsLabel: 'Mã QR mời vào nhóm $groupName',
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: SelectableText(
                  inviteCode,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: inviteCode));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã sao chép mã mời nhóm.')),
                    );
                  },
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Sao chép mã'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
