import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/auth/presentation/account_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late SupabaseClient client;

  setUp(() {
    client = SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test',
    );
  });

  testWidgets('unconfigured build blocks access and explains setup', (
    tester,
  ) async {
    await tester.pumpWidget(_unconfiguredApp());
    await tester.pump();

    expect(find.text('Cần cấu hình tài khoản'), findsOneWidget);
    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
    expect(find.text('Tiếp tục dùng offline'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth form fits a small phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(client));
    await tester.pump();

    expect(find.text('Làm chủ chi tiêu,\ntừng ngày một.'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Mật khẩu'), findsOneWidget);
    expect(find.text('Tiếp tục với Google'), findsNothing);
    expect(find.byIcon(Icons.login), findsNothing);
    expect(find.text('Liên kết Google'), findsNothing);
    expect(find.textContaining('đồng bộ'), findsNothing);
    expect(find.textContaining('cloud'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth form remains usable in landscape with larger text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(812, 375));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(client, textScale: 1.5));
    await tester.pump();

    expect(find.text('Làm chủ chi tiêu,\ntừng ngày một.'), findsOneWidget);
    expect(find.byType(Scrollable), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide auth layout shows finance benefits beside the form', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(client));
    await tester.pump();

    expect(find.text('Theo dõi thu chi'), findsOneWidget);
    expect(find.text('Kiểm soát ngân sách'), findsOneWidget);
    expect(find.text('Nhìn lại thói quen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth artwork remains readable in dark theme', (tester) async {
    await tester.pumpWidget(_app(client, themeMode: ThemeMode.dark));
    await tester.pump();

    expect(find.text('Làm chủ chi tiêu,\ntừng ngày một.'), findsOneWidget);
    expect(find.text('CHÀO MỪNG TRỞ LẠI'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching to registration reveals password confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(_app(client));
    await tester.pump();

    final registerTab = find.text('Đăng ký');
    await tester.ensureVisible(registerTab);
    await tester.tap(registerTab);
    await tester.pumpAndSettle();

    expect(find.text('Nhập lại mật khẩu'), findsOneWidget);
    expect(find.text('Tạo tài khoản'), findsWidgets);
    expect(find.text('Tiếp tục với Google'), findsNothing);
    expect(find.byIcon(Icons.login), findsNothing);
    expect(find.text('Liên kết Google'), findsNothing);
    expect(find.textContaining('đồng bộ'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(
  SupabaseClient client, {
  double textScale = 1,
  ThemeMode themeMode = ThemeMode.light,
}) {
  return ProviderScope(
    overrides: [
      supabaseClientProvider.overrideWithValue(client),
      authUserProvider.overrideWith((ref) => Stream.value(null)),
    ],
    child: MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: themeMode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const AccountScreen(),
    ),
  );
}

Widget _unconfiguredApp() {
  return ProviderScope(
    overrides: [
      supabaseClientProvider.overrideWithValue(null),
      authUserProvider.overrideWith((ref) => Stream.value(null)),
    ],
    child: const MaterialApp(home: AccountScreen()),
  );
}
