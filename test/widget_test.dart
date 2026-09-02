import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/app/theme/app_theme.dart';

void main() {
  testWidgets('theme provides a Material 3 app shell', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: Text('Quản lý Tài chính')),
      ),
    );

    expect(find.text('Quản lý Tài chính'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('Quản lý Tài chính'))).useMaterial3,
      isTrue,
    );
  });
}
