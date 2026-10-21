import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/groups/presentation/bill_invite_qr_sheet.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  testWidgets('hiện QR, mã 10 ký tự và nút Đóng lời mời', (tester) async {
    var closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showBillInviteQrSheet(
                context,
                description: 'Ăn tối',
                joinCode: 'ABCDEF1234',
                onCloseInvite: () async => closed++,
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
    expect(qr.semanticsLabel, 'Mã QR mời vào bill Ăn tối');
    expect(find.text('ABCDEF1234'), findsOneWidget);
    expect(find.text('Sao chép mã'), findsOneWidget);

    await tester.tap(find.text('Đóng lời mời'));
    await tester.pumpAndSettle();
    expect(closed, 1);
    expect(find.byType(QrImageView), findsNothing);
  });
}
