import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/chat/data/chat_history_store.dart';
import 'package:hoadon_insight/features/chat/domain/local_chat_assistant.dart';
import 'package:hoadon_insight/features/chat/domain/chat_models.dart';
import 'package:hoadon_insight/features/chat/presentation/chat_screen.dart';
import 'package:hoadon_insight/features/income/data/income_repository.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hoadon_insight/shared/widgets/finmi_assistant_button.dart';
import 'package:hoadon_insight/app/theme/app_theme.dart';

void main() {
  testWidgets(
    'dismissal lets queued history writes finish without using a disposed widget',
    (tester) async {
      final history = _DelayedHistoryStore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatHistoryStoreProvider.overrideWithValue(history),
            localChatAssistantProvider.overrideWithValue(
              LocalChatAssistant(_InvoiceRepository(), _IncomeRepository()),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showFinmiAssistant(context),
                  child: const Text('Mở trợ lý'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Mở trợ lý'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Tháng này tôi đã thu bao nhiêu?',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Gửi câu hỏi'));
      await tester.pumpAndSettle();
      expect(history.messages, hasLength(1));
      await tester.tap(find.byTooltip('Đóng trợ lý'));
      await tester.pumpAndSettle();
      history.gate.complete();
      await tester.pumpAndSettle();
      expect(history.messages, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'assistant opens as a bottom sheet, supports keyboard, and closes to the same page',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatHistoryStoreProvider.overrideWithValue(
              const ChatHistoryStore(),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: Center(child: FinmiAssistantButton())),
          ),
        ),
      );
      await tester.tap(find.byType(FinmiAssistantButton));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      final bounds = tester.getRect(find.byType(ChatScreen));
      expect(bounds.height, closeTo(630, 1));
      expect(bounds.top, greaterThan(200));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.enterText(find.byType(TextField), 'Xem thu chi');
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.byType(TextField)).dy,
        lessThanOrEqualTo(600),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Đóng trợ lý'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsNothing);
      expect(find.byType(FinmiAssistantButton), findsOneWidget);
    },
  );
  testWidgets(
    'text-only chat answers income and saves history without a network',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      const history = ChatHistoryStore();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localChatAssistantProvider.overrideWithValue(
              LocalChatAssistant(_InvoiceRepository(), _IncomeRepository()),
            ),
            chatHistoryStoreProvider.overrideWithValue(history),
          ],
          child: const MaterialApp(home: ChatScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.add_photo_alternate_outlined), findsNothing);

      await tester.enterText(
        find.byType(TextField),
        'Tháng này tôi đã thu bao nhiêu?',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Gửi câu hỏi'));
      await tester.pumpAndSettle();

      expect(find.textContaining('tổng thu 250.000'), findsOneWidget);
      final saved = await history.loadLocal();
      expect(saved, hasLength(2));
      expect(saved.last.text, contains('tổng thu 250.000'));
    },
  );
  testWidgets('quick prompts stay available after the conversation starts', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const history = ChatHistoryStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localChatAssistantProvider.overrideWithValue(
            LocalChatAssistant(_InvoiceRepository(), _IncomeRepository()),
          ),
          chatHistoryStoreProvider.overrideWithValue(history),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final incomeChip = find.widgetWithText(
      ActionChip,
      'Tháng này tôi đã thu bao nhiêu?',
    );
    expect(find.byType(ActionChip), findsWidgets);
    await tester.ensureVisible(incomeChip);
    await tester.tap(incomeChip);
    await tester.pumpAndSettle();

    expect(find.textContaining('tổng thu 250.000'), findsOneWidget);
    expect(incomeChip, findsOneWidget);
    expect(find.byType(ActionChip), findsWidgets);
  });
}

class _DelayedHistoryStore extends ChatHistoryStore {
  final gate = Completer<void>();
  final messages = <ChatMessage>[];
  @override
  Future<List<ChatMessage>> load() async => [];
  @override
  Future<bool> append(ChatMessage message) async {
    messages.add(message);
    if (messages.length == 1) await gate.future;
    return true;
  }
}

class _DelayedHistoryStore extends ChatHistoryStore {
  final gate = Completer<void>();
  final messages = <ChatMessage>[];
  @override
  Future<List<ChatMessage>> load() async => [];
  @override
  Future<bool> append(ChatMessage message) async {
    messages.add(message);
    if (messages.length == 1) await gate.future;
    return true;
  }
}

class _InvoiceRepository extends Fake implements InvoiceRepository {
  @override
  Stream<List<CategoryEntity>> watchIncomeCategories() => Stream.value([]);
}

class _IncomeRepository extends Fake implements IncomeRepository {
  @override
  Stream<List<IncomeEntry>> watchAll() {
    final now = DateTime.now();
    return Stream.value([
      IncomeEntry(
        id: 'test-income',
        amountMinor: 250000,
        source: IncomeSource.manual,
        receivedAt: now,
        updatedAt: now,
      ),
    ]);
  }
}
