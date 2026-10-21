import 'package:flutter/material.dart';

/// Geometry and brand roles shared by every Finmi surface.
@immutable
class FinmiTokens extends ThemeExtension<FinmiTokens> {
  const FinmiTokens({
    required this.accent,
    required this.border,
    required this.heroBackground,
    required this.heroText,
    required this.heroSecondary,
    this.cardRadius = 18,
    this.heroRadius = 22,
  });

  final Color accent;
  final Color border;
  final Color heroBackground;
  final Color heroText;
  final Color heroSecondary;
  final double cardRadius;
  final double heroRadius;
  double get outlineWidth => 1.25;
  double get inputRadius => 12;
  double get buttonRadius => 12;
  double get touchTargetMin => 48;
  List<double> get spacing => const [4, 8, 12, 16, 20, 24, 32];

  @override
  FinmiTokens copyWith({
    Color? accent,
    Color? border,
    Color? heroBackground,
    Color? heroText,
    Color? heroSecondary,
    double? cardRadius,
    double? heroRadius,
  }) => FinmiTokens(
    accent: accent ?? this.accent,
    border: border ?? this.border,
    heroBackground: heroBackground ?? this.heroBackground,
    heroText: heroText ?? this.heroText,
    heroSecondary: heroSecondary ?? this.heroSecondary,
    cardRadius: cardRadius ?? this.cardRadius,
    heroRadius: heroRadius ?? this.heroRadius,
  );

  @override
  FinmiTokens lerp(covariant FinmiTokens? other, double t) {
    if (other == null) return this;
    return FinmiTokens(
      accent: Color.lerp(accent, other.accent, t)!,
      border: Color.lerp(border, other.border, t)!,
      heroBackground: Color.lerp(heroBackground, other.heroBackground, t)!,
      heroText: Color.lerp(heroText, other.heroText, t)!,
      heroSecondary: Color.lerp(heroSecondary, other.heroSecondary, t)!,
      cardRadius: cardRadius + (other.cardRadius - cardRadius) * t,
      heroRadius: heroRadius + (other.heroRadius - heroRadius) * t,
    );
  }
}

extension FinmiThemeContext on BuildContext {
  FinmiTokens get finmi {
    final theme = Theme.of(this);
    return theme.extension<FinmiTokens>() ??
        FinmiTokens(
          accent: const Color(0xFFC99B56),
          border: theme.colorScheme.outline,
          heroBackground: theme.colorScheme.primary,
          heroText: theme.colorScheme.onPrimary,
          heroSecondary: theme.colorScheme.onPrimary,
        );
  }

  bool get needsStackedLayout =>
      MediaQuery.sizeOf(this).width < 360 ||
      MediaQuery.textScalerOf(this).scale(14) / 14 >= 1.3;
}
