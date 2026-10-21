import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../shared/widgets/finmi_responsive_theme.dart';
import 'router/app_router.dart';
import 'theme/app_scroll_behavior.dart';
import 'theme/app_theme.dart';
import 'theme/theme_mode_provider.dart';
import 'theme/finmi_appearance.dart';

class HoaDonInsightApp extends ConsumerWidget {
  const HoaDonInsightApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => FinmiResponsiveTheme(child: child!),
      theme: ref.watch(finmiAppearanceProvider).isDark
          ? AppTheme.light()
          : AppTheme.forAppearance(ref.watch(finmiAppearanceProvider)),
      darkTheme: ref.watch(finmiAppearanceProvider).isDark
          ? AppTheme.forAppearance(ref.watch(finmiAppearanceProvider))
          : AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      // Toàn bộ app là tiếng Việt nhưng trước đây không có delegate nào, nên
      // showDatePicker và semantics của widget Material render bằng tiếng Anh.
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Kéo-chuột để cuộn trên web/desktop.
      scrollBehavior: const AppScrollBehavior(),
      routerConfig: appRouter,
    );
  }
}
