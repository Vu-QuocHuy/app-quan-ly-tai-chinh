import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/app/theme/app_theme.dart';
import 'package:hoadon_insight/app/theme/finance_colors.dart';
import 'package:hoadon_insight/shared/widgets/budget_meter.dart';
import 'package:hoadon_insight/shared/widgets/status_pill.dart';

void main() {
  testWidgets('simplified budget meter hides labels and exposes progress', (
    tester,
  ) async {
    await _pumpMeter(tester, spentMinor: 60, limitMinor: 100);

    expect(find.byType(StatusPill), findsNothing);
    expect(find.text('60%'), findsNothing);
    expect(find.text('Sắp chạm hạn mức'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Tiến độ ngân sách' &&
            widget.properties.value == '60% đã sử dụng',
      ),
      findsOneWidget,
    );

    final finance = AppFinanceColors.light;
    final expectedColor = Color.lerp(
      finance.budgetWarn.color,
      finance.budgetOver.color,
      0.2,
    );
    final fillFinder = find.descendant(
      of: find.byType(BudgetMeter),
      matching: find.byType(ColoredBox),
    );
    expect(fillFinder, findsOneWidget);
    final fill = tester.widget<ColoredBox>(fillFinder);
    expect(fill.color.toARGB32(), expectedColor!.toARGB32());
  });

  testWidgets('over-budget progress fills the track and reaches red', (
    tester,
  ) async {
    await _pumpMeter(tester, spentMinor: 120, limitMinor: 100);

    final redFill = find.byWidgetPredicate(
      (widget) =>
          widget is ColoredBox &&
          widget.color == AppFinanceColors.light.budgetOver.color,
    );
    expect(redFill, findsOneWidget);
    expect(tester.getSize(redFill).width, 200);
  });

  testWidgets('detailed budget meter keeps its status and amount labels', (
    tester,
  ) async {
    await _pumpMeter(
      tester,
      spentMinor: 90,
      limitMinor: 100,
      showLabel: true,
      colorTransition: false,
    );

    expect(find.byType(StatusPill), findsOneWidget);
    expect(find.text('Sắp chạm hạn mức'), findsOneWidget);
    expect(find.text('90%'), findsOneWidget);
  });
}

Future<void> _pumpMeter(
  WidgetTester tester, {
  required int spentMinor,
  required int limitMinor,
  bool showLabel = false,
  bool colorTransition = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            child: BudgetMeter(
              spentMinor: spentMinor,
              limitMinor: limitMinor,
              showLabel: showLabel,
              colorTransition: colorTransition,
              animate: false,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
