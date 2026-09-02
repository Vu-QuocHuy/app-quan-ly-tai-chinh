import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
import '../shell/app_shell.dart';

final _rootKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: DashboardScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/invoices',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: InvoiceListScreen()),
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
                  const NoTransitionPage(child: BudgetScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: SettingsScreen()),
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
          return const Scaffold(
            body: Center(child: Text('Không có dữ liệu hóa đơn.')),
          );
        }
        return ReviewInvoiceScreen(invoice: invoice);
      },
    ),
  ],
);
