import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/groups/presentation/group_invite_qr_sheet.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('hiện QR chứa link mời và mã chữ', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showGroupInviteQrSheet(
                context,
                groupName: 'Đà Lạt',
                inviteCode: 'ABCD1234',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qr.semanticsLabel, 'Mã QR mời vào nhóm Đà Lạt');
    expect(find.text('ABCD1234'), findsOneWidget);
    expect(find.text('Sao chép mã'), findsOneWidget);
  });
}
