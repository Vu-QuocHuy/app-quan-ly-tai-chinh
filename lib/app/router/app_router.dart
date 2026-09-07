import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/budgets/presentation/budget_screen.dart';
import '../../features/auth/presentation/account_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/invoices/domain/invoice_models.dart';
import '../../features/invoices/presentation/invoice_detail_screen.dart';
import '../../features/invoices/presentation/invoice_list_screen.dart';
import '../../features/ingestion/presentation/import_job_history_screen.dart';
import '../../features/review/presentation/review_invoice_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/sync/presentation/sync_conflicts_screen.dart';
import '../../shared/widgets/app_empty_state.dart';
import '../shell/app_shell.dart';
import '../theme/app_tokens.dart';
import 'auth_redirect.dart';
import '../../core/security/supabase_bootstrap.dart';

/// Trang tab có crossfade nhẹ.
///
/// Bốn tab trước đây dùng `NoTransitionPage`, nên đổi tab là một cú nhảy cứng.
/// Fade cực ngắn cho não biết nội dung đã đổi mà không làm chậm thao tác.
/// Đi qua `AppMotion.of` nên khi hệ thống bật "giảm chuyển động" thì nó về 0ms
/// và hành vi giống hệt trước đây.
CustomTransitionPage<void> _tabPage(BuildContext context, Widget child) {
  return CustomTransitionPage<void>(
    child: child,
    transitionDuration: AppMotion.of(context, AppMotion.base),
    reverseTransitionDuration: AppMotion.of(context, AppMotion.base),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(
          opacity: CurveTween(curve: AppMotion.standard).animate(animation),
          child: child,
        ),
  );
}

final _rootKey = GlobalKey<NavigatorState>();
final authRouterRefresh = _AuthRouterRefresh();

final appRouter = GoRouter(
  navigatorKey: _rootKey,
  refreshListenable: authRouterRefresh,
  initialLocation: '/',
  redirect: (context, state) => authRedirect(
    location: state.matchedLocation,
    isConfigured: SupabaseBootstrap.isConfigured,
    isSignedIn: SupabaseBootstrap.clientOrNull?.auth.currentUser != null,
  ),
  // go_router không có errorBuilder -> deep link không khớp cho ra trang lỗi
  // tiếng Anh mặc định, trong một app thuần Việt.
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
  routes: [
    GoRoute(path: '/auth', builder: (context, state) => const AccountScreen()),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (context, state) =>
                  _tabPage(context, const DashboardScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/invoices',
              pageBuilder: (context, state) =>
                  _tabPage(context, const InvoiceListScreen()),
              routes: [
                GoRoute(
                  path: ':id',
                  parentNavigatorKey: _rootKey,
                  builder: (context, state) => InvoiceDetailScreen(
                    invoiceId: state.pathParameters['id']!,
                  ),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/budgets',
              pageBuilder: (context, state) =>
                  _tabPage(context, const BudgetScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              pageBuilder: (context, state) =>
                  _tabPage(context, const SettingsScreen()),
              routes: [
                GoRoute(
                  path: 'account',
                  parentNavigatorKey: _rootKey,
                  builder: (context, state) => const AccountScreen(),
                ),
                GoRoute(
                  path: 'import-jobs',
                  parentNavigatorKey: _rootKey,
                  builder: (context, state) => const ImportJobHistoryScreen(),
                ),
                GoRoute(
                  path: 'conflicts',
                  parentNavigatorKey: _rootKey,
                  builder: (context, state) => const SyncConflictsScreen(),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/chat',
      parentNavigatorKey: _rootKey,
      builder: (context, state) => const ChatScreen(),
    ),
    GoRoute(
      path: '/review',
      parentNavigatorKey: _rootKey,
      builder: (context, state) {
        final invoice = state.extra;
        if (invoice is! InvoiceEntity) {
          // Trước đây fallback là một Scaffold KHÔNG AppBar -> không nút quay
          // lại, người dùng mắc kẹt (iOS không có phím back cứng).
          return Scaffold(
            appBar: AppBar(title: const Text('Kiểm tra hóa đơn')),
            body: AppEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Không có dữ liệu hóa đơn',
              message:
                  'Phiên kiểm tra đã kết thúc hoặc ứng dụng vừa được mở lại. '
                  'Hãy chọn hóa đơn từ danh sách để xem và sửa.',
              action: FilledButton.icon(
                onPressed: () => context.go('/invoices'),
                icon: const Icon(Icons.list_alt_outlined),
                label: const Text('Quay lại danh sách'),
              ),
            ),
          );
        }
        return ReviewInvoiceScreen(invoice: invoice);
      },
    ),
  ],
);

class _AuthRouterRefresh extends ChangeNotifier {
  StreamSubscription<AuthState>? _subscription;

  void attach(SupabaseClient? client) {
    _subscription?.cancel();
    _subscription = client?.auth.onAuthStateChange.listen(
      (_) => notifyListeners(),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
