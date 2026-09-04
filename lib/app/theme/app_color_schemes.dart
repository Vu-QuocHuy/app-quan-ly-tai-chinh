import 'package:flutter/material.dart';

/// Hai ColorScheme hand-paired. KHÔNG dùng `ColorScheme.fromSeed` ở đây.
///
/// `fromSeed` + ghi đè lẻ là nguyên nhân gốc của bug hiện tại: `tertiary` được
/// ghi đè thành xanh lá #047857 trong khi `tertiaryContainer` do thuật toán
/// sinh ra là HỒNG (HCT hue 335.8). Ghi đè lẻ làm mồ côi cả họ vai.
///
/// Mọi tỉ lệ tương phản ghi trong comment đều tính theo WCAG 2.1 relative
/// luminance và được khoá lại bằng `test/app/theme/theme_contrast_test.dart`.
abstract final class AppColorSchemes {
  static const light = ColorScheme(
    brightness: Brightness.light,

    // --- Thương hiệu: giữ #1E40AF, giờ có đủ bạn đời ---
    primary: Color(0xFF1E40AF),
    onPrimary: Color(0xFFFFFFFF), // 8.72:1
    primaryContainer: Color(0xFFDBE0FF),
    onPrimaryContainer: Color(0xFF0E1A54), // 12.45:1
    primaryFixed: Color(0xFFDBE0FF),
    primaryFixedDim: Color(0xFFB9C3FF),
    onPrimaryFixed: Color(0xFF0E1A54),
    onPrimaryFixedVariant: Color(0xFF2A50CC), // = điểm cuối gradient hero

    secondary: Color(0xFF4A5578),
    onSecondary: Color(0xFFFFFFFF), // 7.34:1
    secondaryContainer: Color(0xFFDDE1F2),
    onSecondaryContainer: Color(0xFF131B33), // 13.09:1
    // --- Xanh tài chính: giờ là một HỌ mạch lạc ---
    tertiary: Color(0xFF0F6E4C),
    onTertiary: Color(0xFFFFFFFF), // 6.26:1
    tertiaryContainer: Color(0xFFA8F2CE),
    onTertiaryContainer: Color(0xFF00351F), // 10.63:1

    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF), // 6.54:1
    errorContainer: Color(0xFFF9DEDC),
    onErrorContainer: Color(0xFF410E0B), // 12.77:1
    // --- Thang neutral: MỘT họ hue duy nhất (~264 độ) ---
    surface: Color(0xFFEAE8F3), // NỀN TRANG
    surfaceDim: Color(0xFFDCDAE9),
    surfaceBright: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFFFFFFF), // THẺ — 1.21:1 so với nền
    surfaceContainerLow: Color(0xFFF7F5FC), // nền input
    surfaceContainer: Color(0xFFEAE8F3),
    surfaceContainerHigh: Color(0xFFE3E1EE), // "lõm" bên trong thẻ
    surfaceContainerHighest: Color(0xFFDCDAE9), // track thanh tiến trình
    onSurface: Color(0xFF1A1B23), // 17.14:1 trên thẻ
    onSurfaceVariant: Color(0xFF454754), // 9.20:1 trên thẻ

    outline: Color(0xFF75768A), // BIÊN — 3.68 nền / 4.45 thẻ
    outlineVariant: Color(0xFFB9BAC9), // CHỈ làm divider trong thẻ

    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF2F303A),
    onInverseSurface: Color(0xFFF2F0F7), // 11.58:1
    inversePrimary: Color(0xFFB4C4FF), // 7.65:1 trên inverseSurface
    surfaceTint: Color(0xFF1E40AF),
  );

  static const dark = ColorScheme(
    brightness: Brightness.dark,

    primary: Color(0xFFB4C4FF),
    onPrimary: Color(0xFF0A1B63), // 9.10:1
    primaryContainer: Color(0xFF2A3F86),
    onPrimaryContainer: Color(0xFFDCE2FF), // 7.60:1
    // Vai *Fixed bất biến theo brightness — đó chính là mục đích của chúng.
    primaryFixed: Color(0xFFDBE0FF),
    primaryFixedDim: Color(0xFFB9C3FF),
    onPrimaryFixed: Color(0xFF0E1A54),
    onPrimaryFixedVariant: Color(0xFF2A50CC),

    secondary: Color(0xFFBEC6E8),
    onSecondary: Color(0xFF1B2540), // 8.97:1
    secondaryContainer: Color(0xFF333C5C),
    onSecondaryContainer: Color(0xFFDDE1F2), // 8.31:1

    tertiary: Color(0xFF6FDDA9),
    onTertiary: Color(0xFF003820), // 7.94:1
    tertiaryContainer: Color(0xFF0B5236),
    onTertiaryContainer: Color(0xFFB6F5D3), // 7.47:1

    error: Color(0xFFFFB4AB),
    onError: Color(0xFF5A1A15), // 7.76:1
    errorContainer: Color(0xFF8C1D18),
    onErrorContainer: Color(0xFFF9DEDC), // 7.17:1

    surface: Color(0xFF0E1014), // NỀN TRANG
    surfaceDim: Color(0xFF0E1014),
    surfaceBright: Color(0xFF343841),
    surfaceContainerLowest: Color(0xFF0A0C10),
    surfaceContainerLow: Color(0xFF171A22), // nền input
    surfaceContainer: Color(0xFF1D2029), // THẺ — 1.17:1 so với nền
    surfaceContainerHigh: Color(0xFF262A34), // "lõm" bên trong thẻ
    surfaceContainerHighest: Color(0xFF31353F), // track thanh tiến trình
    onSurface: Color(0xFFE4E2EC), // 12.70:1 trên thẻ
    onSurfaceVariant: Color(0xFFC5C6D8), // 9.64:1 trên thẻ

    outline: Color(0xFF8F90A6), // BIÊN — 5.20 thẻ / 6.08 nền
    outlineVariant: Color(0xFF4C4E5E), // CHỈ làm divider trong thẻ

    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE4E2EC),
    onInverseSurface: Color(0xFF1D2029), // 12.70:1
    inversePrimary: Color(0xFF1E40AF), // 6.81:1 trên inverseSurface
    surfaceTint: Color(0xFFB4C4FF),
  );
}
