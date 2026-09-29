import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/ingestion/presentation/import_source_sheet.dart';

void main() {
  testWidgets('offers supported invoice sources without XML or PDF', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ImportSourceSheet())),
    );

    expect(find.text('Chụp hóa đơn'), findsOneWidget);
    expect(find.text('Chọn ảnh'), findsOneWidget);
    expect(find.text('Quét QR thanh toán'), findsOneWidget);
    expect(find.text('Nhập thủ công'), findsOneWidget);
    expect(find.textContaining('XML'), findsNothing);
    expect(find.textContaining('PDF'), findsNothing);
  });
}
