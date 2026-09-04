import 'package:flutter/material.dart';

import 'app_tokens.dart'; // cho AppSurfaces.cardSurface

@immutable
class CategoryColors {
  const CategoryColors({
    required this.glyph,
    required this.tint,
    required this.onTint,
  });

  /// Màu icon và dấu chấm màu. >= 4.5:1 so với nền thẻ.
  final Color glyph;

  /// Nền avatar dạng tint. glyph >= 4.5:1 so với nó.
  final Color tint;

  final Color onTint;
}

/// Suy dẫn màu danh mục theo brightness.
///
/// Cột `colorValue` trong DB KHÔNG đổi và migration không đụng tới. Giá trị đã
/// lưu trở thành *seed*; app suy dẫn `(glyph, tint, onTint)` theo theme hiện tại.
///
/// Dùng `HSLColor` (có sẵn trong `package:flutter/painting`) thay vì import
/// `material_color_utilities` trực tiếp: package đó chỉ là dependency transitive
/// nên lint `depend_on_referenced_packages` sẽ làm `flutter analyze` trong CI đỏ.
abstract final class CategoryPalette {
  static const double _minRatio = 4.5;

  /// Giữ nguyên hue của seed, đặt saturation vào dải an toàn, rồi dò lightness
  /// cho tới khi glyph đạt >= 4.5:1 với CẢ nền thẻ VÀ tint của chính nó.
  /// Deterministic, chạy được cho seed bất kỳ người dùng chọn.
  static CategoryColors resolve(int seedValue, ColorScheme scheme) {
    final hsl = HSLColor.fromColor(Color(seedValue));
    final card = scheme.cardSurface;
    final isDark = scheme.brightness == Brightness.dark;

    final tint = isDark
        ? hsl
              .withSaturation(hsl.saturation.clamp(0.30, 0.62))
              .withLightness(0.19)
              .toColor()
        : hsl
              .withSaturation(hsl.saturation.clamp(0.38, 0.85))
              .withLightness(0.93)
              .toColor();

    final glyphSaturation = isDark
        ? hsl.saturation.clamp(0.45, 0.82)
        : (hsl.saturation < 0.55 ? 0.55 : hsl.saturation);

    var lightness = isDark ? 0.72 : 0.34;
    final step = isDark ? 0.02 : -0.02;
    var glyph = Color(seedValue);

    for (var i = 0; i < 50; i++) {
      glyph = hsl
          .withSaturation(glyphSaturation)
          .withLightness(lightness.clamp(0.0, 1.0))
          .toColor();
      if (_ratio(glyph, card) >= _minRatio &&
          _ratio(glyph, tint) >= _minRatio) {
        break;
      }
      lightness += step;
      if (lightness < 0.04 || lightness > 0.96) break;
    }

    return CategoryColors(glyph: glyph, tint: tint, onTint: glyph);
  }

  static double _ratio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }
}
