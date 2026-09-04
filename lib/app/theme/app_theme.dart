import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'app_color_schemes.dart';
import 'app_tokens.dart';
import 'finance_colors.dart';

abstract final class AppTheme {
  // Hoist ra `static final`: trước đây `app.dart` gọi AppTheme.light() và
  // AppTheme.dark() trong build() của widget gốc, chạy lại toàn bộ việc dựng
  // ThemeData mỗi lần root rebuild.
  static final ThemeData _light = _build(
    AppColorSchemes.light,
    AppFinanceColors.light,
  );
  static final ThemeData _dark = _build(
    AppColorSchemes.dark,
    AppFinanceColors.dark,
  );

  static ThemeData light() => _light;
  static ThemeData dark() => _dark;

  static ThemeData _build(ColorScheme scheme, AppFinanceColors finance) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface, // L0
      // Từ `.standard` cố định -> theo nền tảng. App có target web và dùng
      // NavigationRail trên 840dp, nên mật độ nên theo platform.
      visualDensity: VisualDensity.adaptivePlatformDensity,
      splashFactory: InkSparkle.splashFactory,
      extensions: <ThemeExtension<dynamic>>[finance],
      // Đặt một lần ở đây thay vì per-route: biến thể reduced-motion sau này
      // chỉ là một dòng swap.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );

    final text = _textTheme(base.textTheme);

    return base.copyWith(
      textTheme: text,

      // ---------- Surface ----------
      cardTheme: CardThemeData(
        elevation: AppElevations.none,
        margin: EdgeInsets.zero,
        color: scheme.cardSurface, // L1 — 1.21:1 / 1.17:1 so với L0
        // KHÔNG có `side`. Thẻ tĩnh là borderless; thẻ chạm được nhận viền
        // `outline` từ `AppCard(onTap:)`.
        shape: AppShapes.card,
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: DividerThemeData(
        // Kẻ tóc THỤT LỀ TREO — canh theo cột chữ, không theo avatar.
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
        indent: AppSpacing.dividerIndent,
        endIndent: 0,
      ),

      // ---------- Chrome điều hướng ----------
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        scrolledUnderElevation: AppElevations.raised,
        elevation: AppElevations.none,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(color: scheme.onSurface),
        iconTheme: IconThemeData(
          color: scheme.onSurface,
          size: AppIconSizes.md,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        // `height: 72` bị XOÁ. Mặc định M3 là 80dp và 8dp chênh lệch đó chính
        // là khoảng dư mà bộ kẹp nhãn của Flutter cần cho "Tổng quan".
        elevation: AppElevations.raised,
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        // Pill thương hiệu đặc: 7.20:1 sáng / 11.13:1 tối.
        indicatorColor: scheme.primary,
        indicatorShape: AppShapes.pill,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
          );
        }),
        // resolveWith, KHÔNG phải WidgetStatePropertyAll. Trước đây nhãn chọn và
        // không chọn giống hệt nhau -> màu là tín hiệu duy nhất.
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return text.labelMedium?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary,
        indicatorShape: AppShapes.pill,
        selectedIconTheme: IconThemeData(color: scheme.onPrimary, size: 24),
        unselectedIconTheme: IconThemeData(
          color: scheme.onSurfaceVariant,
          size: 24,
        ),
        selectedLabelTextStyle: text.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(
          fontWeight: FontWeight.w500,
          color: scheme.onSurfaceVariant,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        // Trước đây FAB hoàn toàn không được theme -> rơi về `primaryContainer`
        // mặc định của M3 = 1.23:1 so với nền. Nó là CTA toàn cục duy nhất.
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary, // 8.72:1 / 9.10:1
        elevation: AppElevations.raised,
        hoverElevation: AppElevations.raisedHover,
        focusElevation: AppElevations.raisedHover,
        extendedTextStyle: text.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        shape: AppShapes.pill,
      ),

      // ---------- Nút: bốn cấp, bốn ý nghĩa ----------
      // FilledButton        = hành động cam kết DUY NHẤT trên màn hình
      // FilledButton.tonal  = hành động khẳng định hỗ trợ
      // OutlinedButton      = có thể hoàn tác nhưng đáng cân nhắc
      // TextButton          = phụ / bỏ qua
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: AppShapes.control,
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        ).copyWith(overlayColor: _stateLayer(scheme.onPrimary)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: AppShapes.control,
          side: BorderSide(color: scheme.outline), // 3.68:1 / 6.08:1
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        ).copyWith(overlayColor: _stateLayer(scheme.primary)),
      ),
      textButtonTheme: TextButtonThemeData(
        // 48dp áp ở tầng theme -> các vi phạm cố ý trong màn hình có thể xoá.
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: AppShapes.control,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        ).copyWith(overlayColor: _stateLayer(scheme.primary)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          tapTargetSize: MaterialTapTargetSize.padded,
          iconSize: AppIconSizes.md,
        ).copyWith(overlayColor: _stateLayer(scheme.onSurface)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: scheme.secondaryContainer,
          selectedForegroundColor: scheme.onSecondaryContainer,
          side: BorderSide(color: scheme.outline),
        ),
      ),

      // ---------- Nhập liệu ----------
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: const OutlineInputBorder(borderRadius: AppShapes.controlRadius),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppShapes.controlRadius,
          // `outline` chứ không phải `outlineVariant`: 4.12:1 / 5.56:1 so với
          // nền input, vượt ngưỡng 3:1 của WCAG 1.4.11 cho biên control.
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppShapes.controlRadius,
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppShapes.controlRadius,
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppShapes.controlRadius,
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        labelStyle: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        floatingLabelStyle: text.bodyMedium?.copyWith(color: scheme.primary),
        helperStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        helperMaxLines: 2,
        errorStyle: text.bodySmall?.copyWith(color: scheme.error),
        errorMaxLines: 3,
        alignLabelWithHint: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(AppElevations.none),
        backgroundColor: WidgetStatePropertyAll(scheme.cardSurface),
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
        shape: const WidgetStatePropertyAll(AppShapes.control),
        textStyle: WidgetStatePropertyAll(text.bodyLarge),
        hintStyle: WidgetStatePropertyAll(
          text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        ),
      ),

      // ---------- Danh sách, chip, chia cắt ----------
      listTileTheme: ListTileThemeData(
        shape: AppShapes.control,
        minTileHeight: 56,
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.titleMedium?.copyWith(color: scheme.onSurface),
        subtitleTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.cardSurface,
        selectedColor: scheme.secondaryContainer,
        side: BorderSide(color: scheme.outline),
        shape: AppShapes.control,
        labelStyle: text.labelLarge?.copyWith(color: scheme.onSurface),
        secondaryLabelStyle: text.labelLarge?.copyWith(
          color: scheme.onSecondaryContainer,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),

      // ---------- Overlay ----------
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.liftedSurface, // L3
        surfaceTintColor: Colors.transparent,
        elevation: AppElevations.none,
        shape: AppShapes.card,
        titleTextStyle: text.headlineSmall?.copyWith(color: scheme.onSurface),
        contentTextStyle: text.bodyLarge?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.cardSurface,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevations.none,
        shape: AppShapes.sheet,
        showDragHandle: true,
        dragHandleColor: scheme.outlineVariant,
        clipBehavior: Clip.antiAlias,
      ),
      snackBarTheme: SnackBarThemeData(
        // `floating` thay cho `docked` mặc định: trước đây SnackBar hiển thị
        // sát mép dưới, ngay dưới FAB mở rộng, đẩy nó lên xuống.
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ), // 11.58:1
        actionTextColor: scheme.inversePrimary, // 7.65:1 / 6.81:1
        shape: AppShapes.control,
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        elevation: AppElevations.raised,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: AppShapes.controlRadius,
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        waitDuration: const Duration(milliseconds: 400),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.liftedSurface,
        surfaceTintColor: Colors.transparent,
        elevation: AppElevations.raised,
        shape: AppShapes.card,
        textStyle: text.bodyLarge?.copyWith(color: scheme.onSurface),
      ),

      // ---------- Chỉ báo ----------
      progressIndicatorTheme: ProgressIndicatorThemeData(
        // MỘT thanh duy nhất. Trước đây Dashboard vẽ cao 10 bo 999 còn Ngân
        // sách vẽ cao 8 bo 8 — cùng một số liệu, hai hình dạng.
        linearMinHeight: 10,
        borderRadius: BorderRadius.circular(999),
        linearTrackColor: scheme.surfaceContainerHighest,
        color: scheme.primary,
      ),
      iconTheme: IconThemeData(
        color: scheme.onSurfaceVariant,
        size: AppIconSizes.md,
      ),
      tabBarTheme: TabBarThemeData(
        labelStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: text.titleSmall,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: scheme.outlineVariant,
      ),
    );
  }

  /// Độ mờ state layer M3, đặt một lần thay vì per call site.
  /// Đây cũng là thứ mang lại focus ring mà target web trước đây không có.
  static WidgetStateProperty<Color?> _stateLayer(Color on) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return on.withValues(alpha: 0.10);
        }
        if (states.contains(WidgetState.focused)) {
          return on.withValues(alpha: 0.10);
        }
        if (states.contains(WidgetState.hovered)) {
          return on.withValues(alpha: 0.08);
        }
        return null;
      });

  /// Thang 15 vai đầy đủ. Leading được nâng so với mặc định M3 vì mặc định đó
  /// tinh chỉnh cho Latin: ở 30–36sp, một glyph như `Ổ` mang dấu mũ CỘNG dấu
  /// thanh và leading mặc định làm dấu thanh chạm dòng trên.
  ///
  /// letterSpacing: 0 ở mọi vai display/headline — tracking âm làm bẹp dấu chấm
  /// phân nhóm trong "1.234.567 ₫".
  static TextTheme _textTheme(TextTheme base) => base
      .copyWith(
        displayLarge: base.displayLarge!.copyWith(
          height: 1.20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        displayMedium: base.displayMedium!.copyWith(
          height: 1.22,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        displaySmall: base.displaySmall!.copyWith(
          height: 1.28,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        headlineLarge: base.headlineLarge!.copyWith(
          height: 1.32,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        headlineMedium: base.headlineMedium!.copyWith(
          height: 1.34,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        headlineSmall: base.headlineSmall!.copyWith(
          height: 1.36,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        titleLarge: base.titleLarge!.copyWith(
          height: 1.34,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: base.titleMedium!.copyWith(
          height: 1.40,
          fontWeight: FontWeight.w600,
        ),
        // titleSmall trước đây bị bỏ quên ở w500 mặc định trong khi titleLarge
        // là w700 -> thang trọng lượng gãy ngay trong một thẻ.
        titleSmall: base.titleSmall!.copyWith(
          height: 1.40,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: base.bodyLarge!.copyWith(height: 1.50),
        bodyMedium: base.bodyMedium!.copyWith(height: 1.50),
        bodySmall: base.bodySmall!.copyWith(height: 1.45),
        labelLarge: base.labelLarge!.copyWith(fontWeight: FontWeight.w600),
        labelMedium: base.labelMedium!.copyWith(fontWeight: FontWeight.w600),
        labelSmall: base.labelSmall!.copyWith(fontWeight: FontWeight.w600),
      )
      // Phòng thủ cho ROM Android bị lược bớt font.
      .apply(fontFamilyFallback: const ['Roboto', 'Noto Sans']);
}
