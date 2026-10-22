import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/groups/presentation/fund_progress_card.dart';

Future<void> _pump(WidgetTester tester, FundProgressCard card) =>
    tester.pumpWidget(
      MaterialApp(
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Scaffold(body: card),
      ),
    );

void main() {
  final today = DateTime(2026, 10, 20);

  testWidgets('thành viên không thấy gì khi chưa có mục tiêu', (tester) async {
    await _pump(
      tester,
      FundProgressCard(
        balanceMinor: 0,
        goalMinor: null,
        deadline: null,
        isOwner: false,
        onEditGoal: () {},
        today: today,
      ),
    );
    expect(find.text('Đặt mục tiêu quỹ'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('trưởng nhóm thấy nút đặt mục tiêu khi chưa có', (tester) async {
    var tapped = false;
    await _pump(
      tester,
      FundProgressCard(
        balanceMinor: 0,
        goalMinor: null,
        deadline: null,
        isOwner: true,
        onEditGoal: () => tapped = true,
        today: today,
      ),
    );
    await tester.tap(find.text('Đặt mục tiêu quỹ'));
    expect(tapped, isTrue);
  });

  testWidgets('đang góp hiện phần trăm và số ngày còn lại', (tester) async {
    await _pump(
      tester,
      FundProgressCard(
        balanceMinor: 6400000,
        goalMinor: 10000000,
        deadline: DateTime(2026, 12, 15),
        isOwner: false,
        onEditGoal: () {},
        today: today,
      ),
    );
    expect(find.textContaining('64%'), findsOneWidget);
    expect(find.text('Còn 56 ngày'), findsOneWidget);
    expect(find.byTooltip('Sửa mục tiêu'), findsNothing);
  });

  testWidgets('vượt mục tiêu hiện 150% và thanh đầy', (tester) async {
    await _pump(
      tester,
      FundProgressCard(
        balanceMinor: 1500,
        goalMinor: 1000,
        deadline: null,
        isOwner: true,
        onEditGoal: () {},
        today: today,
      ),
    );
    expect(find.textContaining('150%'), findsOneWidget);
    expect(find.text('Đã đạt mục tiêu'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 1.0);
  });

  testWidgets('quá hạn chưa đạt', (tester) async {
    await _pump(
      tester,
      FundProgressCard(
        balanceMinor: 100,
        goalMinor: 1000,
        deadline: DateTime(2026, 10, 17),
        isOwner: false,
        onEditGoal: () {},
        today: today,
      ),
    );
    expect(find.text('Quá hạn 3 ngày'), findsOneWidget);
  });
}
