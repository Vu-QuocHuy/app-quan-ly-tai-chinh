import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/groups/domain/group_models.dart';
import 'package:hoadon_insight/features/groups/presentation/group_expense_dialog.dart';
import 'package:hoadon_insight/features/groups/presentation/group_split_dialog.dart';
import 'package:image_picker/image_picker.dart';

const _members = [
  GroupMember(userId: 'u1', displayName: 'Huy', role: 'owner'),
  GroupMember(userId: 'u2', displayName: 'Lan', role: 'member'),
];

/// Mở dialog; kết quả `showDialog` ghi vào [result] khi dialog đóng.
Future<void> _open(
  WidgetTester tester,
  Future<ReceiptPrefill?> Function(ImageSource) onScan,
  void Function(GroupExpenseDraft?) result,
) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,

      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result(
            await showDialog<GroupExpenseDraft>(
              context: context,
              builder: (_) =>
                  GroupSplitDialog(members: _members, onScan: onScan),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Finder _inTab(String tab, Finder finder) =>
    find.descendant(of: find.byKey(ValueKey(tab)), matching: finder);

Finder _saveButton() => find.widgetWithText(FilledButton, 'Chia tiền');

void main() {
  testWidgets('tab Nhập thủ công trả bản nháp chia đều', (tester) async {
    GroupExpenseDraft? draft;
    await _open(tester, (_) async => null, (d) => draft = d);
    expect(find.text('Nhập thủ công'), findsOneWidget);
    expect(find.text('Quét hóa đơn'), findsOneWidget);
    await tester.enterText(
      _inTab('tab-thu-cong', find.widgetWithText(TextField, 'Nội dung')),
      'Ăn tối',
    );
    await tester.enterText(
      _inTab('tab-thu-cong', find.widgetWithText(TextField, 'Tổng tiền')),
      '90000',
    );
    await tester.tap(_saveButton());
    await tester.pumpAndSettle();
    expect(draft!.description, 'Ăn tối');
    expect(draft!.totalMinor, 90000);
    expect(draft!.memberIds.toSet(), {'u1', 'u2'});
  });

  testWidgets('tab Quét hóa đơn điền sẵn rồi lưu', (tester) async {
    GroupExpenseDraft? draft;
    ImageSource? asked;
    await _open(tester, (source) async {
      asked = source;
      return const ReceiptPrefill(
        description: 'Hóa đơn Highlands',
        totalMinor: 120000,
      );
    }, (d) => draft = d);
    await tester.tap(find.text('Quét hóa đơn'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(_saveButton()).onPressed,
      isNull,
      reason: 'chưa quét thì chưa lưu được',
    );
    await tester.tap(find.text('Chọn từ thư viện'));
    await tester.pumpAndSettle();
    expect(asked, ImageSource.gallery);
    final ten = tester.widget<TextField>(
      _inTab('tab-quet', find.widgetWithText(TextField, 'Nội dung')),
    );
    expect(ten.controller!.text, 'Hóa đơn Highlands');
    await tester.tap(_saveButton());
    await tester.pumpAndSettle();
    expect(draft!.description, 'Hóa đơn Highlands');
    expect(draft!.totalMinor, 120000);
  });

  testWidgets('quét lỗi thì báo trong dialog, vẫn còn nút quét', (
    tester,
  ) async {
    await _open(tester, (_) async => throw StateError('mất mạng'), (_) {});
    await tester.tap(find.text('Quét hóa đơn'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chụp ảnh hóa đơn'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Không thể xử lý hóa đơn'), findsOneWidget);
    expect(find.text('Chụp ảnh hóa đơn'), findsOneWidget);
    expect(find.byType(GroupSplitDialog), findsOneWidget);
  });

  testWidgets('huỷ chọn ảnh thì không báo lỗi', (tester) async {
    await _open(tester, (_) async => null, (_) {});
    await tester.tap(find.text('Quét hóa đơn'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chọn từ thư viện'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Không thể xử lý hóa đơn'), findsNothing);
    expect(find.text('Chọn từ thư viện'), findsOneWidget);
  });

  testWidgets('chuyển tab không mất chữ đã nhập', (tester) async {
    await _open(tester, (_) async => null, (_) {});
    await tester.enterText(
      _inTab('tab-thu-cong', find.widgetWithText(TextField, 'Nội dung')),
      'Cà phê',
    );
    await tester.tap(find.text('Quét hóa đơn'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nhập thủ công'));
    await tester.pumpAndSettle();
    final o = tester.widget<TextField>(
      _inTab('tab-thu-cong', find.widgetWithText(TextField, 'Nội dung')),
    );
    expect(o.controller!.text, 'Cà phê');
  });
}
