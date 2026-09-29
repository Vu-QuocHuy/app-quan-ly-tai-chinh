import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoadon_insight/app/router/auth_redirect.dart';
import 'package:hoadon_insight/shared/widgets/app_empty_state.dart';

void main() {
  group('Cổng đăng nhập', () {
    group('build chưa có cấu hình Supabase', () {
      const routes = [
        '/',
        '/invoices',
        '/invoices/invoice-1',
        '/invoices/invoice-1/attachments',
        '/budgets',
        '/groups',
        '/settings',
        '/settings/account',
        '/settings/cloud',
        '/settings/import-jobs',
        '/settings/conflicts',
        '/chat',
        '/qr-payment',
        '/review',
      ];

      for (final route in routes) {
        test('$route không thể vào khi chưa cấu hình Supabase', () {
          expect(
            authRedirect(
              location: route,
              isConfigured: false,
              isSignedIn: false,
            ),
            '/auth',
            reason: '$route phải yêu cầu cấu hình và đăng nhập',
          );
        });
      }

      test('/auth vẫn hiện hướng dẫn cấu hình', () {
        expect(
          authRedirect(
            location: '/auth',
            isConfigured: false,
            isSignedIn: false,
          ),
          isNull,
        );
      });

      test('phiên cũ cũng không bỏ qua build thiếu cấu hình', () {
        expect(
          authRedirect(location: '/', isConfigured: false, isSignedIn: true),
          '/auth',
        );
      });
    });

    group('có cloud nhưng chưa đăng nhập', () {
      test('mọi route dữ liệu đều bị chặn', () {
        for (final route in [
          '/',
          '/invoices',
          '/invoices/invoice-1',
          '/budgets',
          '/groups',
          '/settings',
          '/settings/import-jobs',
          '/settings/conflicts',
          '/chat',
          '/qr-payment',
          '/review',
        ]) {
          expect(
            authRedirect(
              location: route,
              isConfigured: true,
              isSignedIn: false,
            ),
            '/auth',
            reason: '$route phải yêu cầu phiên đăng nhập',
          );
        }
      });

      test('chỉ trang đăng nhập vẫn tới được', () {
        expect(
          authRedirect(
            location: '/auth',
            isConfigured: true,
            isSignedIn: false,
          ),
          isNull,
        );
        expect(
          authRedirect(
            location: '/settings/account',
            isConfigured: true,
            isSignedIn: false,
          ),
          '/auth',
        );
      });
    });

    group('đã đăng nhập', () {
      test('/auth chuyển về trang chủ', () {
        expect(
          authRedirect(location: '/auth', isConfigured: true, isSignedIn: true),
          '/',
        );
      });

      test('mọi route dữ liệu được mở', () {
        for (final route in [
          '/',
          '/invoices',
          '/settings/account',
          '/settings/conflicts',
          '/chat',
          '/qr-payment',
        ]) {
          expect(
            authRedirect(location: route, isConfigured: true, isSignedIn: true),
            isNull,
          );
        }
      });
    });
  });

  group('Route lỗi', () {
    testWidgets('deep link không khớp cho trang tiếng Việt có lối ra', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(body: Text('home')),
          ),
        ],
        errorBuilder: (context, state) => Scaffold(
          appBar: AppBar(title: const Text('Không mở được trang')),
          body: AppEmptyState(
            icon: Icons.link_off,
            title: 'Không mở được trang này',
            message: 'Đường dẫn “${state.uri}” không tồn tại trong ứng dụng.',
            action: FilledButton.icon(
              onPressed: () => context.go('/'),
              icon: const Icon(Icons.home_outlined),
              label: const Text('Về trang Tổng quan'),
            ),
          ),
        ),
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      router.go('/khong-ton-tai');
      await tester.pumpAndSettle();

      expect(find.text('Không mở được trang này'), findsOneWidget);
      // Lối ra là bắt buộc: iOS không có phím back cứng.
      expect(find.text('Về trang Tổng quan'), findsOneWidget);

      await tester.tap(find.text('Về trang Tổng quan'));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
    });
  });
}
