import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hoadon_insight/app/router/auth_redirect.dart';
import 'package:hoadon_insight/shared/widgets/app_empty_state.dart';

void main() {
  group('Cổng đăng nhập', () {
    // Đây là kịch bản của chính APK mà CI dựng: không có --dart-define nào.
    group('build không có cấu hình cloud', () {
      const routes = [
        '/',
        '/invoices',
        '/budgets',
        '/settings',
        '/settings/account',
        '/settings/import-jobs',
        '/chat',
        '/review',
      ];

      for (final route in routes) {
        test('$route dùng được mà không cần đăng nhập', () {
          expect(
            authRedirect(
              location: route,
              isConfigured: false,
              isSignedIn: false,
            ),
            isNull,
            reason:
                'App là local-first; không có cloud thì không có gì để đăng '
                'nhập, nên chặn $route làm app không dùng được.',
          );
        });
      }

      test('/auth tự chuyển về trang chủ vì không có gì để đăng nhập', () {
        expect(
          authRedirect(
            location: '/auth',
            isConfigured: false,
            isSignedIn: false,
          ),
          '/',
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

      test('trang đăng nhập và tài khoản vẫn tới được', () {
        for (final route in ['/auth', '/settings/account']) {
          expect(
            authRedirect(
              location: route,
              isConfigured: true,
              isSignedIn: false,
            ),
            isNull,
          );
        }
      });
    });

    group('đã đăng nhập', () {
      test('/auth chuyển về trang chủ', () {
        expect(
          authRedirect(location: '/auth', isConfigured: true, isSignedIn: true),
          '/',
        );
      });

      test('mọi route khác đi thẳng', () {
        for (final route in ['/', '/settings/conflicts', '/chat']) {
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
