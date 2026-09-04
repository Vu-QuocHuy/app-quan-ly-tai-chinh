import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/app/theme/app_color_schemes.dart';
import 'package:hoadon_insight/app/theme/app_theme.dart';
import 'package:hoadon_insight/app/theme/app_tokens.dart';
import 'package:hoadon_insight/app/theme/category_palette.dart';
import 'package:hoadon_insight/app/theme/finance_colors.dart';

/// WCAG 2.1 contrast ratio.
double ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('ColorScheme đạt WCAG AA', () {
    for (final (name, scheme) in [
      ('light', AppColorSchemes.light),
      ('dark', AppColorSchemes.dark),
    ]) {
      test('$name — cặp chữ trên nền đạt >= 4.5:1', () {
        final pairs = <String, (Color, Color)>{
          'onPrimary/primary': (scheme.onPrimary, scheme.primary),
          'onPrimaryContainer/primaryContainer': (
            scheme.onPrimaryContainer,
            scheme.primaryContainer,
          ),
          'onSecondary/secondary': (scheme.onSecondary, scheme.secondary),
          'onSecondaryContainer/secondaryContainer': (
            scheme.onSecondaryContainer,
            scheme.secondaryContainer,
          ),
          'onTertiary/tertiary': (scheme.onTertiary, scheme.tertiary),
          'onTertiaryContainer/tertiaryContainer': (
            scheme.onTertiaryContainer,
            scheme.tertiaryContainer,
          ),
          'onError/error': (scheme.onError, scheme.error),
          'onErrorContainer/errorContainer': (
            scheme.onErrorContainer,
            scheme.errorContainer,
          ),
          'onSurface/cardSurface': (scheme.onSurface, scheme.cardSurface),
          'onSurfaceVariant/cardSurface': (
            scheme.onSurfaceVariant,
            scheme.cardSurface,
          ),
          'onSurface/surface': (scheme.onSurface, scheme.surface),
          'onSurfaceVariant/surface': (scheme.onSurfaceVariant, scheme.surface),
          'onInverseSurface/inverseSurface': (
            scheme.onInverseSurface,
            scheme.inverseSurface,
          ),
          'inversePrimary/inverseSurface': (
            scheme.inversePrimary,
            scheme.inverseSurface,
          ),
        };

        for (final entry in pairs.entries) {
          final (fg, bg) = entry.value;
          expect(
            ratio(fg, bg),
            greaterThanOrEqualTo(4.5),
            reason: '$name ${entry.key} phải >= 4.5:1',
          );
        }
      });

      test('$name — chỉ báo phi văn bản đạt >= 3:1 (WCAG 1.4.11)', () {
        expect(
          ratio(scheme.outline, scheme.surface),
          greaterThanOrEqualTo(3.0),
          reason: 'outline trên nền trang',
        );
        expect(
          ratio(scheme.outline, scheme.cardSurface),
          greaterThanOrEqualTo(3.0),
          reason: 'outline trên thẻ — viền của AppCard(onTap:)',
        );
        expect(
          ratio(scheme.outline, scheme.surfaceContainerLow),
          greaterThanOrEqualTo(3.0),
          reason: 'biên input trên nền input',
        );
      });

      test('$name — CẢ HAI đầu gradient hero đọc được với onPrimary', () {
        // Bản sửa đầu tiên cho hero dùng `onPrimaryFixedVariant` cho điểm cuối.
        // Vai *Fixed bất biến theo brightness, còn `onPrimary` thì không — nên
        // ở theme tối nó cho 2.31:1 và chữ hero gần như biến mất. Test này
        // khoá cả hai đầu, không chỉ đầu `primary`.
        expect(
          ratio(scheme.onPrimary, scheme.primary),
          greaterThanOrEqualTo(4.5),
          reason: '$name đầu gradient',
        );
        expect(
          ratio(scheme.onPrimary, scheme.heroGradientEnd),
          greaterThanOrEqualTo(4.5),
          reason: '$name cuối gradient',
        );
      });

      test('$name — bậc tông thẻ so với nền phải nhìn thấy được', () {
        expect(ratio(scheme.cardSurface, scheme.surface), greaterThan(1.10));
      });
    }
  });

  group('Màu tài chính', () {
    for (final (name, finance, scheme) in [
      ('light', AppFinanceColors.light, AppColorSchemes.light),
      ('dark', AppFinanceColors.dark, AppColorSchemes.dark),
    ]) {
      test('$name — quad on/color và on/container đạt >= 4.5:1', () {
        final tones = <String, FinanceTone>{
          'income': finance.income,
          'budgetSafe': finance.budgetSafe,
          'budgetWarn': finance.budgetWarn,
          'budgetOver': finance.budgetOver,
          'confidenceHigh': finance.confidenceHigh,
          'confidenceLow': finance.confidenceLow,
          'syncOk': finance.syncOk,
          'syncPending': finance.syncPending,
          'syncConflict': finance.syncConflict,
        };
        for (final entry in tones.entries) {
          final tone = entry.value;
          expect(
            ratio(tone.onColor, tone.color),
            greaterThanOrEqualTo(4.5),
            reason: '$name ${entry.key}.onColor/color',
          );
          expect(
            ratio(tone.onContainer, tone.container),
            greaterThanOrEqualTo(4.5),
            reason: '$name ${entry.key}.onContainer/container',
          );
        }
      });

      test('$name — fill thanh ngân sách so với track đạt >= 3:1', () {
        final track = scheme.surfaceContainerHighest;
        for (final entry in {
          'budgetSafe': finance.budgetSafe,
          'budgetWarn': finance.budgetWarn,
          'budgetOver': finance.budgetOver,
        }.entries) {
          expect(
            ratio(entry.value.color, track),
            greaterThanOrEqualTo(3.0),
            reason: '$name ${entry.key} fill trên track',
          );
        }
      });

      test('$name — expense là MỰC, không phải màu cảnh báo', () {
        expect(finance.expense.color, scheme.onSurface);
      });
    }
  });

  group('Bảng màu danh mục', () {
    // 8 màu mặc định trong DB + màu teal mặc định của picker.
    const seeds = <String, int>{
      'Ăn uống': 0xFFEA580C,
      'Di chuyển': 0xFF2563EB,
      'Mua sắm': 0xFF7C3AED,
      'Tiện ích': 0xFFCA8A04,
      'Y tế': 0xFFDC2626,
      'Giáo dục': 0xFF0891B2,
      'Giải trí': 0xFFDB2777,
      'Khác': 0xFF64748B,
      'Teal (picker)': 0xFF0F766E,
    };

    for (final (name, scheme) in [
      ('light', AppColorSchemes.light),
      ('dark', AppColorSchemes.dark),
    ]) {
      test('$name — mọi seed cho glyph >= 4.5:1 trên thẻ VÀ trên tint', () {
        for (final entry in seeds.entries) {
          final colors = CategoryPalette.resolve(entry.value, scheme);
          expect(
            ratio(colors.glyph, scheme.cardSurface),
            greaterThanOrEqualTo(4.5),
            reason: '$name ${entry.key}: glyph trên nền thẻ',
          );
          expect(
            ratio(colors.glyph, colors.tint),
            greaterThanOrEqualTo(4.5),
            reason: '$name ${entry.key}: glyph trên tint của chính nó',
          );
        }
      });
    }
  });

  group('Cổng chữ số tabular', () {
    // Nếu ai đó swap font mà bản subset mất `tnum`, CI đỏ thay vì cột tiền
    // lặng lẽ nhảy trở lại.
    double widthOf(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      return painter.width;
    }

    test('chữ số cùng bề ngang ở mọi cấp nhấn mạnh', () {
      final finance = AppFinanceColors.light;
      for (final (name, style) in [
        ('moneyDisplay', finance.moneyDisplay),
        ('moneyTitle', finance.moneyTitle),
        ('moneyBody', finance.moneyBody),
        ('moneyCaption', finance.moneyCaption),
      ]) {
        expect(
          widthOf('1.111.111 ₫', style),
          closeTo(widthOf('8.888.888 ₫', style), 0.01),
          reason: '$name phải dùng tabular figures',
        );
      }
    });
  });

  group('ThemeData', () {
    test('đăng ký AppFinanceColors ở cả hai theme', () {
      expect(AppTheme.light().extension<AppFinanceColors>(), isNotNull);
      expect(AppTheme.dark().extension<AppFinanceColors>(), isNotNull);
    });

    test('trả về cùng instance mỗi lần gọi (không dựng lại mỗi rebuild)', () {
      expect(identical(AppTheme.light(), AppTheme.light()), isTrue);
      expect(identical(AppTheme.dark(), AppTheme.dark()), isTrue);
    });

    test('không còn dùng vai ColorScheme đã deprecated', () {
      expect(AppTheme.light().useMaterial3, isTrue);
      expect(AppTheme.dark().useMaterial3, isTrue);
    });

    test('mọi bán kính đến từ AppShapes', () {
      expect(AppShapes.cardRadius.topLeft.x, AppShapes.md);
      expect(AppShapes.controlRadius.topLeft.x, AppShapes.sm);
    });
  });
}
