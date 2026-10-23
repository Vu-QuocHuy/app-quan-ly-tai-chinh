import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hoadon_insight/app/theme/app_theme.dart';
import 'package:hoadon_insight/shared/widgets/finmi_brand.dart';
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
    expect(find.textContaining('người quản lý ứng dụng'), findsOneWidget);
    expect(find.text('Tiếp tục dùng offline'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signed-in account shows the editable personal profile form', (
    tester,
  ) async {
    final user = User.fromJson({
      'id': '00000000-0000-4000-8000-000000000001',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'aud': 'authenticated',
      'created_at': '2026-10-23T00:00:00Z',
      'email': 'test@example.com',
    });

    await tester.pumpWidget(_app(client, user: user));
    await tester.pumpAndSettle();

    expect(find.text('Đã kết nối tài khoản'), findsOneWidget);
    expect(find.text('Thông tin cá nhân'), findsOneWidget);
    expect(
      find.text(
        'Họ tên và số điện thoại sẽ hiển thị với thành viên trong các nhóm bạn tham gia.',
      ),
      findsOneWidget,
    );
    expect(find.text('Họ và tên'), findsOneWidget);
    expect(find.text('Số điện thoại *'), findsOneWidget);
    expect(find.text('Lưu thông tin'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth form fits a small phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(client));
    await tester.pump();

    expect(find.text('Theo dõi chi tiêu mỗi ngày'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Mật khẩu'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(
      tester.getSize(find.byType(SegmentedButton<bool>)).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      tester.getSize(find.widgetWithText(TextButton, 'Quên mật khẩu?')).height,
      greaterThanOrEqualTo(48),
    );
    expect(find.text('Đăng nhập với Google'), findsOneWidget);
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

    expect(find.text('Theo dõi chi tiêu mỗi ngày'), findsOneWidget);
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

    expect(find.byType(FinmiBrand), findsOneWidget);
    expect(find.text('Theo dõi chi tiêu mỗi ngày'), findsOneWidget);
    expect(
      tester.getRect(find.byType(FinmiBrand)).right,
      lessThan(tester.getRect(find.byType(TextFormField).first).left),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth artwork remains readable in dark theme', (tester) async {
    await tester.pumpWidget(_app(client, themeMode: ThemeMode.dark));
    await tester.pump();

    expect(find.text('Theo dõi chi tiêu mỗi ngày'), findsOneWidget);
    expect(find.text('Chào mừng trở lại'), findsOneWidget);
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
    expect(find.text('Đăng nhập với Google'), findsOneWidget);
    expect(find.byIcon(Icons.login), findsNothing);
    expect(find.text('Liên kết Google'), findsNothing);
    expect(find.textContaining('đồng bộ'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching auth mode clears validation errors', (tester) async {
    await tester.pumpWidget(_app(client));
    await tester.pump();

    final submitButton = find.text('Đăng nhập').last;
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();
    expect(find.text('Hãy nhập email.'), findsOneWidget);
    expect(find.text('Hãy nhập mật khẩu.'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).first,
      'test@example.com',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Đăng ký'));
    await tester.pumpAndSettle();

    expect(find.text('Hãy nhập email.'), findsNothing);
    expect(find.text('Hãy nhập mật khẩu.'), findsNothing);
    expect(
      tester
          .widget<TextFormField>(find.widgetWithText(TextFormField, 'Email'))
          .controller!
          .text,
      'test@example.com',
    );

    await tester.binding.setSurfaceSize(const Size(812, 375));
    await tester.pumpAndSettle();
    expect(find.text('Hãy nhập lại mật khẩu.'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(
  SupabaseClient client, {
  double textScale = 1,
  ThemeMode themeMode = ThemeMode.light,
  User? user,
}) {
  return ProviderScope(
    overrides: [
      supabaseClientProvider.overrideWithValue(client),
      authUserProvider.overrideWith((ref) => Stream.value(user)),
    ],
    child: MaterialApp(
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,

      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
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
    child: const MaterialApp(
      locale: Locale('vi'),
      supportedLocales: [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: AccountScreen(),
    ),
  );
}
