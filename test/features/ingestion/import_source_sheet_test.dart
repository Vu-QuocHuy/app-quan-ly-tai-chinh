import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/ingestion/presentation/import_source_sheet.dart';

void main() {
  testWidgets('offers supported invoice sources without XML or PDF', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('vi'),
        supportedLocales: [Locale('vi'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: ImportSourceSheet()),
      ),
    );

    expect(find.text('Thêm khoản thu'), findsOneWidget);
    expect(find.text('Chỉ nhập số tiền'), findsOneWidget);
    expect(find.text('Quét QR hoặc hóa đơn'), findsOneWidget);
    expect(
      find.text('Kiểm tra thông tin trước khi lưu khoản chi'),
      findsOneWidget,
    );
    expect(find.text('Chụp hóa đơn'), findsNothing);
    expect(find.text('Chọn ảnh'), findsNothing);
    expect(find.text('Quét QR thanh toán'), findsNothing);
    expect(find.text('Thêm khoản chi'), findsOneWidget);
    expect(find.textContaining('XML'), findsNothing);
    expect(find.textContaining('PDF'), findsNothing);
  });
}
