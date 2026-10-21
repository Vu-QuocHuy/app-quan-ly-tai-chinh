import 'package:flutter/material.dart';

/// Một quad màu ngữ nghĩa đầy đủ. Không widget nào được ứng biến màu tài chính.
@immutable
class FinanceTone {
  const FinanceTone({
    required this.color,
    required this.onColor,
    required this.container,
    required this.onContainer,
  });

  final Color color;
  final Color onColor;
  final Color container;
  final Color onContainer;

  static FinanceTone lerp(FinanceTone a, FinanceTone b, double t) =>
      FinanceTone(
        color: Color.lerp(a.color, b.color, t)!,
        onColor: Color.lerp(a.onColor, b.onColor, t)!,
        container: Color.lerp(a.container, b.container, t)!,
        onContainer: Color.lerp(a.onContainer, b.onContainer, t)!,
      );
}

@immutable
class AppFinanceColors extends ThemeExtension<AppFinanceColors> {
  const AppFinanceColors({
    required this.income,
    required this.expense,
    required this.budgetSafe,
    required this.budgetWarn,
    required this.cashFlowBalance,
    required this.budgetOver,
    required this.confidenceHigh,
    required this.confidenceLow,
    required this.syncOk,
    required this.syncPending,
    required this.syncConflict,
    required this.moneyDisplay,
    required this.moneyTitle,
    required this.moneyBody,
    required this.moneyCaption,
  });

  final FinanceTone income;

  /// Màu khoản chi đi cùng nhãn, biểu tượng hoặc dấu trừ để dễ phân biệt.
  final FinanceTone expense;

  final FinanceTone budgetSafe;

  /// Tầng 80% — khớp `BudgetAlertPolicy.approachingThreshold`. Hôm nay policy
  /// bắn thông báo ở ngưỡng này nhưng KHÔNG màn hình nào render nó.
  final FinanceTone budgetWarn;
  final FinanceTone cashFlowBalance;

  final FinanceTone budgetOver;
  final FinanceTone confidenceHigh;
  final FinanceTone confidenceLow;
  final FinanceTone syncOk;
  final FinanceTone syncPending;
  final FinanceTone syncConflict;

  /// Style tiền — tất cả mang `FontFeature.tabularFigures()` để chữ số đều bề
  /// ngang, cột tiền thẳng hàng và số đếm lên không bị dồn chữ.
  final TextStyle moneyDisplay;
  final TextStyle moneyTitle;
  final TextStyle moneyBody;
  final TextStyle moneyCaption;

  static const _tabular = <FontFeature>[FontFeature.tabularFigures()];

  static const _moneyDisplay = TextStyle(
    fontSize: 34,
    height: 1.22,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    fontFeatures: _tabular,
  );
  static const _moneyTitle = TextStyle(
    fontSize: 22,
    height: 1.30,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
    fontFeatures: _tabular,
  );
  static const _moneyBody = TextStyle(
    fontSize: 16,
    height: 1.35,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    fontFeatures: _tabular,
  );
  static const _moneyCaption = TextStyle(
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
    fontFeatures: _tabular,
  );

  static const light = AppFinanceColors(
    income: FinanceTone(
      color: Color(0xFF236447),
      onColor: Color(0xFFFFFFFF),
      container: Color(0xFFD7E5D8),
      onContainer: Color(0xFF152F20),
    ),
    expense: FinanceTone(
      color: Color(0xFFB23C36),
      onColor: Color(0xFFFFFFFF),
      container: Color(0xFFFBEDEB),
      onContainer: Color(0xFF842D28),
    ),
    budgetSafe: FinanceTone(
      color: Color(0xFF236447),
      onColor: Color(0xFFFFFFFF),
      container: Color(0xFFD7E5D8),
      onContainer: Color(0xFF152F20),
    ),
    budgetWarn: FinanceTone(
      color: Color(0xFF805821),
      onColor: Color(0xFFFFFFFF),
      container: Color(0xFFF4E4C9),
      onContainer: Color(0xFF3E2D18),
    ),
    cashFlowBalance: FinanceTone(
      color: Color(0xFF896329),
      onColor: Color(0xFFFFFFFF),
      container: Color(0xFFFFE8A0),
      onContainer: Color(0xFF3B2A00),
    ),
    budgetOver: FinanceTone(
      color: Color(0xFFB3261E),
      onColor: Color(0xFFFFFFFF),
      container: Color(0xFFF9DEDC),
      onContainer: Color(0xFF410E0B),
    ),
    confidenceHigh: FinanceTone(
      color: Color(0xFF236447),
      onColor: Color(0xFFFFFFFF),
      container: Color(0xFFD7E5D8),
      onContainer: Color(0xFF152F20),
    ),
    confidenceLow: FinanceTone(
      color: Color(0xFF805821),
      onColor: Color(0xFFFFFFFF),
      container: Color(0xFFF4E4C9),
      onContainer: Color(0xFF3E2D18),
    ),
    syncOk: FinanceTone(
      color: Color(0xFF236447),
      onColor: Color(0xFFFFFFFF),
      container: Color(0xFFD7E5D8),
      onContainer: Color(0xFF152F20),
    ),
    syncPending: FinanceTone(
      color: Color(0xFF485D68),
      onColor: Color(0xFFFFFFFF),
      container: Color(0xFFDBE6E8),
      onContainer: Color(0xFF203038),
    ),
    syncConflict: FinanceTone(
      color: Color(0xFF805821),
      onColor: Color(0xFFFFFFFF),
      container: Color(0xFFF4E4C9),
      onContainer: Color(0xFF3E2D18),
    ),
    moneyDisplay: _moneyDisplay,
    moneyTitle: _moneyTitle,
    moneyBody: _moneyBody,
    moneyCaption: _moneyCaption,
  );

  static const dark = AppFinanceColors(
    income: FinanceTone(
      color: Color(0xFFC1D7C3),
      onColor: Color(0xFF183425),
      container: Color(0xFF294A35),
      onContainer: Color(0xFFE1ECE0),
    ),
    expense: FinanceTone(
      color: Color(0xFFFFBBB4),
      onColor: Color(0xFF111813),
      container: Color(0xFF29362C),
      onContainer: Color(0xFFE2E8E0),
    ),
    budgetSafe: FinanceTone(
      color: Color(0xFFC1D7C3),
      onColor: Color(0xFF183425),
      container: Color(0xFF294A35),
      onContainer: Color(0xFFE1ECE0),
    ),
    budgetWarn: FinanceTone(
      color: Color(0xFFEAC88F),
      onColor: Color(0xFF422E12),
      container: Color(0xFF5C421F),
      onContainer: Color(0xFFF4E4C9),
    ),
    cashFlowBalance: FinanceTone(
      color: Color(0xFFF2C84B),
      onColor: Color(0xFF2A2000),
      container: Color(0xFF5B4500),
      onContainer: Color(0xFFFFE8A0),
    ),
    budgetOver: FinanceTone(
      color: Color(0xFFFFB4AB),
      onColor: Color(0xFF5A1A15),
      container: Color(0xFF8C1D18),
      onContainer: Color(0xFFF9DEDC),
    ),
    confidenceHigh: FinanceTone(
      color: Color(0xFFC1D7C3),
      onColor: Color(0xFF183425),
      container: Color(0xFF294A35),
      onContainer: Color(0xFFE1ECE0),
    ),
    confidenceLow: FinanceTone(
      color: Color(0xFFEAC88F),
      onColor: Color(0xFF422E12),
      container: Color(0xFF5C421F),
      onContainer: Color(0xFFF4E4C9),
    ),
    syncOk: FinanceTone(
      color: Color(0xFFC1D7C3),
      onColor: Color(0xFF183425),
      container: Color(0xFF294A35),
      onContainer: Color(0xFFE1ECE0),
    ),
    syncPending: FinanceTone(
      color: Color(0xFFB8CED2),
      onColor: Color(0xFF163034),
      container: Color(0xFF2E484B),
      onContainer: Color(0xFFD8E7E8),
    ),
    syncConflict: FinanceTone(
      color: Color(0xFFEAC88F),
      onColor: Color(0xFF422E12),
      container: Color(0xFF5C421F),
      onContainer: Color(0xFFF4E4C9),
    ),
    moneyDisplay: _moneyDisplay,
    moneyTitle: _moneyTitle,
    moneyBody: _moneyBody,
    moneyCaption: _moneyCaption,
  );

  @override
  AppFinanceColors copyWith({
    FinanceTone? income,
    FinanceTone? expense,
    FinanceTone? budgetSafe,
    FinanceTone? budgetWarn,
    FinanceTone? cashFlowBalance,
    FinanceTone? budgetOver,
    FinanceTone? confidenceHigh,
    FinanceTone? confidenceLow,
    FinanceTone? syncOk,
    FinanceTone? syncPending,
    FinanceTone? syncConflict,
    TextStyle? moneyDisplay,
    TextStyle? moneyTitle,
    TextStyle? moneyBody,
    TextStyle? moneyCaption,
  }) {
    return AppFinanceColors(
      income: income ?? this.income,
      expense: expense ?? this.expense,
      budgetSafe: budgetSafe ?? this.budgetSafe,
      budgetWarn: budgetWarn ?? this.budgetWarn,
      cashFlowBalance: cashFlowBalance ?? this.cashFlowBalance,
      budgetOver: budgetOver ?? this.budgetOver,
      confidenceHigh: confidenceHigh ?? this.confidenceHigh,
      confidenceLow: confidenceLow ?? this.confidenceLow,
      syncOk: syncOk ?? this.syncOk,
      syncPending: syncPending ?? this.syncPending,
      syncConflict: syncConflict ?? this.syncConflict,
      moneyDisplay: moneyDisplay ?? this.moneyDisplay,
      moneyTitle: moneyTitle ?? this.moneyTitle,
      moneyBody: moneyBody ?? this.moneyBody,
      moneyCaption: moneyCaption ?? this.moneyCaption,
    );
  }

  @override
  AppFinanceColors lerp(ThemeExtension<AppFinanceColors>? other, double t) {
    if (other is! AppFinanceColors) return this;
    return AppFinanceColors(
      income: FinanceTone.lerp(income, other.income, t),
      expense: FinanceTone.lerp(expense, other.expense, t),
      budgetSafe: FinanceTone.lerp(budgetSafe, other.budgetSafe, t),
      budgetWarn: FinanceTone.lerp(budgetWarn, other.budgetWarn, t),
      cashFlowBalance: FinanceTone.lerp(
        cashFlowBalance,
        other.cashFlowBalance,
        t,
      ),
      budgetOver: FinanceTone.lerp(budgetOver, other.budgetOver, t),
      confidenceHigh: FinanceTone.lerp(confidenceHigh, other.confidenceHigh, t),
      confidenceLow: FinanceTone.lerp(confidenceLow, other.confidenceLow, t),
      syncOk: FinanceTone.lerp(syncOk, other.syncOk, t),
      syncPending: FinanceTone.lerp(syncPending, other.syncPending, t),
      syncConflict: FinanceTone.lerp(syncConflict, other.syncConflict, t),
      moneyDisplay: TextStyle.lerp(moneyDisplay, other.moneyDisplay, t)!,
      moneyTitle: TextStyle.lerp(moneyTitle, other.moneyTitle, t)!,
      moneyBody: TextStyle.lerp(moneyBody, other.moneyBody, t)!,
      moneyCaption: TextStyle.lerp(moneyCaption, other.moneyCaption, t)!,
    );
  }
}

/// Truy cập ngắn gọn — dùng cái này thay `Theme.of(context).extension<...>()!`.
///
/// Cố ý KHÔNG dùng `!`: một widget được pump với `ThemeData` trần (test hiện có
/// làm đúng vậy, hoặc khi nhúng vào một MaterialApp khác) sẽ không có extension.
/// Rơi về bộ màu khớp brightness thay vì ném lỗi.
extension FinanceColorsX on BuildContext {
  AppFinanceColors get finance {
    final theme = Theme.of(this);
    return theme.extension<AppFinanceColors>() ??
        (theme.brightness == Brightness.dark
            ? AppFinanceColors.dark
            : AppFinanceColors.light);
  }
}
