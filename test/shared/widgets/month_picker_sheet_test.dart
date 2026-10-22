import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/shared/widgets/month_picker_sheet.dart';

void main() {
  testWidgets('month picker fits a narrow viewport', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,

        theme: ThemeData(useMaterial3: true),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showMonthPickerSheet(context, selected: DateTime(2026, 10)),
              child: const Text('Mở chọn tháng'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Mở chọn tháng'));
    await tester.pumpAndSettle();

    expect(find.text('Chọn tháng'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
