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

  testWidgets('auth form fits a small phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(client));
    await tester.pump();

    expect(find.text('Đồng bộ chi tiêu an toàn'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Mật khẩu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth form remains usable in landscape with larger text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(812, 375));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app(client, textScale: 1.5));
    await tester.pump();

    expect(find.text('Đồng bộ chi tiêu an toàn'), findsOneWidget);
    expect(find.byType(Scrollable), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

Widget _app(SupabaseClient client, {double textScale = 1}) {
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
