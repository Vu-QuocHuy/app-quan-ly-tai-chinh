import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/database/app_database.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/chat/data/assistant_command_client.dart';
import 'package:hoadon_insight/features/chat/domain/assistant_command.dart';
import 'package:hoadon_insight/features/chat/presentation/chat_screen.dart';
import 'package:hoadon_insight/features/debts/data/debt_repository.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Planner extends AssistantCommandClient {
  final List<AssistantCommand> commands = [];
  final List<AssistantCommand?> pendingSeen = [];
  final List<AssistantCommand?> lastSeen = [];
  @override
  bool get isConfigured => true;
  @override
  Future<AssistantCommand> interpret(
    String text, {
    required List<CategoryEntity> categories,
    AssistantCommand? pending,
    AssistantCommand? last,
  }) async {
    pendingSeen.add(pending);
    lastSeen.add(last);
    return commands.removeAt(0);
  }
}

void main() {
  const recorder = MethodChannel('com.llfbandit.record/messages');
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late ProviderContainer container;
  late _Planner planner;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recorder, (_) async => null);
    db = AppDatabase(NativeDatabase.memory());
    planner = _Planner();
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        supabaseClientProvider.overrideWithValue(null),
        assistantCommandClientProvider.overrideWithValue(planner),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recorder, null);
  });
  Future<void> open(WidgetTester tester, {String language = 'vi'}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: Locale(language),
          supportedLocales: const [Locale('vi'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const ChatScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'ambiguous debt asks, follow-up saves, correction updates same record',
    (tester) async {
      planner.commands.addAll([
        const AssistantCommand(
          kind: 'debt',
          personName: 'Nam',
          amountMinor: 500000,
        ),
        const AssistantCommand(
          kind: 'debt',
          personName: 'Nam',
          amountMinor: 500000,
          debtDirection: 'they_owe',
        ),
        const AssistantCommand(
          kind: 'debt',
          operation: 'update_last',
          personName: 'Nam',
          amountMinor: 600000,
          debtDirection: 'they_owe',
        ),
      ]);
      await open(tester);
      await send(tester, 'Ghi nợ Nam 500k');
      expect(find.text('Bạn nợ người đó hay người đó nợ bạn?'), findsOneWidget);
      expect(await container.read(debtRepositoryProvider).loadDebts(), isEmpty);
      await send(tester, 'Nam nợ tôi');
      final first =
          (await container.read(debtRepositoryProvider).loadDebts()).single;
      expect(first.amountMinor, 500000);
      expect(planner.pendingSeen.last!.personName, 'Nam');
      await send(tester, 'Sửa khoản vừa ghi thành 600k');
      final updated =
          (await container.read(debtRepositoryProvider).loadDebts()).single;
      expect(updated.id, first.id);
      expect(updated.amountMinor, 600000);
      expect(planner.lastSeen.last!.amountMinor, 500000);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'English UI returns English identity and refusal without model calls',
    (tester) async {
      await open(tester, language: 'en');
      await send(tester, 'Bạn là ai?');
      expect(
        find.text('I’m FinmiAI, your financial assistant.'),
        findsOneWidget,
      );
      await send(tester, 'Neural Network là gì');
      expect(
        find.textContaining('I can help with your finances'),
        findsOneWidget,
      );
      expect(planner.lastSeen, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('cancel clears pending debt without writing', (tester) async {
    planner.commands.addAll([
      const AssistantCommand(kind: 'debt', amountMinor: 500000),
      const AssistantCommand(kind: 'cancel'),
    ]);
    await open(tester);
    await send(tester, 'Ghi nợ 500k');
    await send(tester, 'Hủy');
    expect(await container.read(debtRepositoryProvider).loadDebts(), isEmpty);
    expect(find.textContaining('Đã hủy yêu cầu'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
