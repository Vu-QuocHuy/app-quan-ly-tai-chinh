@Tags(['visual'])
library;

import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hoadon_insight/features/planning/data/plan_repository.dart';
import 'package:hoadon_insight/features/planning/domain/plan_models.dart';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:hoadon_insight/app/shell/app_shell.dart';

import 'package:hoadon_insight/app/theme/app_theme.dart';
import 'package:hoadon_insight/shared/widgets/finmi_responsive_theme.dart';
import 'package:hoadon_insight/app/theme/finmi_appearance.dart';
import 'package:hoadon_insight/app/theme/finmi_theme.dart';
import 'package:hoadon_insight/core/database/app_database.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/budgets/presentation/budget_screen.dart';
import 'package:hoadon_insight/features/budgets/presentation/category_management.dart';
import 'package:hoadon_insight/features/dashboard/presentation/dashboard_screen.dart';
import 'package:hoadon_insight/features/dashboard/presentation/statistics_screen.dart';
import 'package:hoadon_insight/features/groups/presentation/group_screen.dart';
import 'package:hoadon_insight/features/income/data/income_repository.dart';
import 'package:hoadon_insight/features/income/presentation/transaction_entry_sheet.dart';
import 'package:hoadon_insight/features/ingestion/data/pending_import_store.dart';
import 'package:hoadon_insight/features/chat/presentation/chat_screen.dart';
import 'package:hoadon_insight/features/chat/data/chat_history_store.dart';
import 'package:hoadon_insight/features/auth/presentation/account_screen.dart';
import 'package:hoadon_insight/features/invoices/data/drift_invoice_repository.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:hoadon_insight/features/invoices/presentation/invoice_list_screen.dart';
import 'package:hoadon_insight/features/planning/presentation/plan_screen.dart';
import 'package:hoadon_insight/features/settings/presentation/settings_screen.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return ((x > y ? x : y) + .05) / ((x < y ? x : y) + .05);
}

void main() {
  late SupabaseClient authClient;
  TestWidgetsFlutterBinding.ensureInitialized();
  const connectivityChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity_status',
  );
  const recorderChannel = MethodChannel('com.llfbandit.record/messages');
  setUpAll(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(connectivityChannel, (call) async {
      if (call.method != 'listen' && call.method != 'cancel') {
        throw MissingPluginException(
          'Unexpected connectivity call: ${call.method}',
        );
      }
      return null;
    });
    messenger.setMockMethodCallHandler(recorderChannel, (call) async {
      if (call.method != 'create' && call.method != 'dispose') {
        throw MissingPluginException(
          'Unexpected recorder call: ${call.method}',
        );
      }
      return null;
    });
    authClient = SupabaseClient(
      'https://example.supabase.co',
      'sb_publishable_test',
    );
    final icons = FontLoader('MaterialIcons');
    icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final cupertino = FontLoader('packages/cupertino_icons/CupertinoIcons');
    cupertino.addFont(
      rootBundle.load('packages/cupertino_icons/assets/CupertinoIcons.ttf'),
    );
    await cupertino.load();
    final vietnamese = FontLoader('Be Vietnam Pro');
    for (final weight in [400, 500, 600, 700]) {
      vietnamese.addFont(
        rootBundle.load('assets/fonts/BeVietnamPro-$weight.ttf'),
      );
    }
    await vietnamese.load();
    final font = File('C:/Windows/Fonts/arial.ttf');
    if (font.existsSync()) {
      final loader = FontLoader('Roboto');
      loader.addFont(font.readAsBytes().then((b) => ByteData.sublistView(b)));
      await loader.load();
    }
  });
  tearDownAll(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(connectivityChannel, null);
    messenger.setMockMethodCallHandler(recorderChannel, null);
  });

  test('all reference themes preserve text contrast and clear boundaries', () {
    for (final appearance in FinmiAppearance.values) {
      final theme = AppTheme.forAppearance(appearance);
      final scheme = theme.colorScheme;
      for (final foreground in [scheme.onSurface, scheme.onSurfaceVariant]) {
        expect(
          contrast(foreground, scheme.surface),
          greaterThanOrEqualTo(4.5),
          reason: appearance.name,
        );
        expect(
          contrast(foreground, appearance.surface),
          greaterThanOrEqualTo(4.5),
          reason: appearance.name,
        );
      }
      final tokens = theme.extension<FinmiTokens>()!;
      expect(
        contrast(tokens.heroText, tokens.heroBackground),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(tokens.heroSecondary, tokens.heroBackground),
        greaterThanOrEqualTo(4.5),
      );
      expect(tokens.outlineWidth, 1.25);
      expect(theme.inputDecorationTheme.focusedBorder!.borderSide.width, 2);
    }
    expect(AppTheme.light().scaffoldBackgroundColor, Colors.white);
  });

  test(
    'palette selection persists and restores independently from data',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = ProviderContainer();
      expect(first.read(finmiAppearanceProvider).id, 'white');
      await first
          .read(finmiAppearanceProvider.notifier)
          .set(FinmiAppearance.fromId('ivory'));
      first.dispose();
      final second = ProviderContainer();
      second.read(finmiAppearanceProvider);
      await Future<void>.delayed(Duration.zero);
      expect(second.read(finmiAppearanceProvider).id, 'ivory');
      second.dispose();
    },
  );

  for (final width in [320, 390, 430]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('screens and transaction/assistant sheets at $width dp / $scale', (
        tester,
      ) async {
        final layoutErrors = <String>[];
        final previousErrorHandler = FlutterError.onError!;
        FlutterError.onError = (details) {
          layoutErrors.add(details.toString());
          previousErrorHandler(details);
        };
        addTearDown(() => FlutterError.onError = previousErrorHandler);
        SharedPreferences.setMockInitialValues({});
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width.toDouble(), 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final database = AppDatabase(NativeDatabase.memory());
        final repository = DriftInvoiceRepository(database);
        final now = DateTime.now();
        await tester.runAsync(() async {
          await repository.saveInvoice(
            InvoiceEntity(
              id: 'visual-fixture',
              sellerName: 'WinMart Vincom Đồng Khởi',
              currencyCode: 'VND',
              subtotalMinor: 225240,
              taxMinor: 0,
              totalMinor: 225240,
              sourceType: InvoiceSourceType.manual,
              status: InvoiceStatus.confirmed,
              createdAt: now,
              updatedAt: now,
              issuedAt: DateTime(now.year, now.month, 1),
              confirmedAt: now,
              categoryId: 'other',
            ),
          );
          await repository.saveInvoice(
            InvoiceEntity(
              id: 'visual-today',
              sellerName: 'Phúc Long Coffee',
              currencyCode: 'VND',
              subtotalMinor: 75000,
              taxMinor: 0,
              totalMinor: 75000,
              sourceType: InvoiceSourceType.imageOcr,
              status: InvoiceStatus.confirmed,
              createdAt: now,
              updatedAt: now,
              issuedAt: now,
              confirmedAt: now,
              categoryId: 'other',
            ),
          );
          await IncomeRepository(
            database,
          ).save(20000000, source: IncomeSource.manual);
        });
        await tester.runAsync(() async {
          await repository.saveBudget(
            BudgetEntity(
              id: 'visual-budget',
              monthKey: '${now.year}-${now.month.toString().padLeft(2, '0')}',
              categoryId: 'other',
              limitMinor: 100000,
            ),
          );
          await PlanRepository(database).save(
            RecurringBill(
              id: 'visual-rent',
              updatedAt: now,
              title: 'Tiền thuê nhà',
              amountMinor: 5000000,
              frequency: BillFrequency.monthly,
              anchorDate: now,
              nextDueDate: now.add(const Duration(days: 2)),
              categoryId: 'other',
            ),
          );
          await PlanRepository(database).save(
            RecurringIncome(
              id: 'visual-salary',
              updatedAt: now,
              title: 'Lương công ty',
              amountMinor: 20000000,
              categoryId: 'income_uncategorized',
              anchorDate: now,
              nextDueDate: now.add(const Duration(days: 2)),
            ),
          );
        });
        final container = ProviderContainer(
          overrides: [
            databaseProvider.overrideWithValue(database),
            pendingImportStoreProvider.overrideWithValue(
              _EmptyPendingImports(),
            ),
            authUserProvider.overrideWith(
              (ref) => Stream.value(
                User(
                  id: 'visual-user',
                  appMetadata: const {},
                  userMetadata: const {'display_name': 'Nguyễn Quốc Huy'},
                  aud: 'authenticated',
                  createdAt: now.toIso8601String(),
                ),
              ),
            ),
            budgetAlertsEnabledProvider.overrideWith((ref) async => false),
            chatHistoryStoreProvider.overrideWithValue(
              const ChatHistoryStore(),
            ),
          ],
        );
        final boundary = GlobalKey();
        final pages = <String, Widget>{
          'overview': const DashboardScreen(),
          'history': const InvoiceListScreen(),
          'statistics': const StatisticsScreen(),
          'recurring': const PlanScreen(),
          'budgets': const BudgetScreen(),
          'groups': const GroupScreen(),
          'categories': const CategoryManagementScreen(),
          'settings': const SettingsScreen(),
          'assistant-sheet': Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showFinmiAssistant(context),
                  child: const Text('Mở trợ lý'),
                ),
              ),
            ),
          ),
          'login': ProviderScope(
            overrides: [
              supabaseClientProvider.overrideWithValue(authClient),
              authUserProvider.overrideWith((ref) => Stream.value(null)),
            ],
            child: const AccountScreen(),
          ),
          'register': ProviderScope(
            overrides: [
              supabaseClientProvider.overrideWithValue(authClient),
              authUserProvider.overrideWith((ref) => Stream.value(null)),
            ],
            child: const AccountScreen(),
          ),
          'source-sheet': Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showTransactionEntry(context),
                  child: const Text('Mở giao dịch'),
                ),
              ),
            ),
          ),
        };
        final router = GoRouter(
          routes: [
            StatefulShellRoute.indexedStack(
              builder: (context, state, shell) =>
                  AppShell(navigationShell: shell),
              branches: [
                for (final entry in [
                  'overview',
                  'budgets',
                  'groups',
                  'settings',
                ])
                  StatefulShellBranch(
                    routes: [
                      GoRoute(
                        path: entry == 'overview' ? '/' : '/$entry',
                        builder: (_, _) => pages[entry]!,
                      ),
                    ],
                  ),
              ],
            ),
            for (final entry in [
              'history',
              'statistics',
              'recurring',
              'categories',
              'source-sheet',
              'assistant-sheet',
              'login',
              'register',
            ])
              GoRoute(path: '/$entry', builder: (_, _) => pages[entry]!),
          ],
        );
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              routerConfig: router,
              theme: AppTheme.light(),
              locale: const Locale('vi'),
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              supportedLocales: const [Locale('vi')],
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: FinmiResponsiveTheme(
                  child: RepaintBoundary(key: boundary, child: child!),
                ),
              ),
            ),
          ),
        );
        for (final page in pages.entries) {
          debugPrint('Rendering ${page.key} at $width/$scale');
          router.go(page.key == 'overview' ? '/' : '/${page.key}');
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 120)),
          );
          await tester.pump(const Duration(milliseconds: 500));
          if (page.key == 'source-sheet') {
            await tester.tap(find.text('Mở giao dịch'));
            await tester.pumpAndSettle();
          }
          if (page.key == 'assistant-sheet') {
            await tester.tap(find.text('Mở trợ lý'));
            await tester.pumpAndSettle();
          }
          if (page.key == 'register') {
            await tester.ensureVisible(find.text('Đăng ký').first);
            await tester.tap(find.text('Đăng ký').first);
            await tester.pumpAndSettle();
          }
          tester.takeException();
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await render.toImage();
            final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.png,
            ))!;
            final target = File(
              'artifacts/finmi/${page.key}-$width-${scale.toStringAsFixed(1)}.png',
            );
            await target.parent.create(recursive: true);
            await target.writeAsBytes(bytes.buffer.asUint8List());
            image.dispose();
          });
          Future<void> captureExtra(String name) async {
            await tester.runAsync(() async {
              final image = await render.toImage();
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.png,
              ))!;
              await File(
                'artifacts/finmi/$name-$width-${scale.toStringAsFixed(1)}.png',
              ).writeAsBytes(bytes.buffer.asUint8List());
              image.dispose();
            });
          }

          if (page.key == 'overview') {
            await tester.scrollUntilVisible(
              find.byKey(const ValueKey('finmi-banner')),
              300,
              scrollable: find.byType(Scrollable).first,
            );
            await captureExtra('overview-banner');
          }
          if (page.key == 'statistics') {
            await tester.tap(find.text('Theo năm'));
            await tester.pumpAndSettle();
            await captureExtra('statistics-year');
            await tester.scrollUntilVisible(
              find.text('Tháng ${now.month}'),
              250,
              scrollable: find.byType(Scrollable).first,
            );
            await Scrollable.ensureVisible(
              tester.element(find.text('Tháng ${now.month}')),
              alignment: .5,
            );
            await tester.pumpAndSettle();
            await tester.tap(find.text('Tháng ${now.month}'));
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(
              find.byKey(const ValueKey('statistics-period')),
              250,
              scrollable: find.byType(Scrollable).first,
            );
            expect(
              find.text('Biểu đồ · Tháng ${now.month}/${now.year}'),
              findsOneWidget,
            );
            await captureExtra('statistics-month-charts');
          }
          if (page.key == 'budgets') {
            await tester.tap(find.byTooltip('Xem danh mục vượt hạn mức'));
            await tester.pumpAndSettle();
            await captureExtra('budget-details');
          }
          if (page.key == 'source-sheet') {
            await tester.tap(find.text('Thêm khoản chi'));
            await tester.pumpAndSettle();
            await captureExtra('expense-sheet');
          }
          // Walk the primary scroll view so lower sections also exercise layout.
          final scrollables = find.byType(Scrollable);
          if (scrollables.evaluate().isNotEmpty) {
            for (var step = 0; step < 10; step++) {
              await tester.drag(scrollables.first, const Offset(0, -500));
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 30)),
              );
              await tester.pump(const Duration(milliseconds: 500));
              tester.takeException();
            }
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          debugPrint('Disposing router');
          router.dispose();
          debugPrint('Disposing container');
          container.dispose();
          debugPrint('Closing database');
          await database.close();
          debugPrint('Cleanup complete');
        });
        expect(layoutErrors, isEmpty, reason: layoutErrors.join('\n\n'));
      });
    }
  }
}

class _EmptyPendingImports extends Fake implements PendingImportStore {
  @override
  Future<List<PendingImport>> list() async => const [];
}
