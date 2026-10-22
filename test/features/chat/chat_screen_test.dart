import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/chat/data/ai_chat_client.dart';
import 'package:hoadon_insight/features/chat/data/chat_history_store.dart';
import 'package:hoadon_insight/features/chat/domain/chat_models.dart';
import 'package:hoadon_insight/features/chat/domain/local_chat_assistant.dart';
import 'package:hoadon_insight/features/chat/presentation/chat_screen.dart';
import 'package:hoadon_insight/features/income/data/income_repository.dart';
import 'package:hoadon_insight/features/ingestion/data/ai_extraction_client.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hoadon_insight/shared/widgets/finmi_assistant_button.dart';
import 'package:hoadon_insight/app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const recorderChannel = MethodChannel('com.llfbandit.record/messages');
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recorderChannel, (call) async {
          if (call.method != 'create' && call.method != 'dispose') {
            throw MissingPluginException(
              'Unexpected recorder call: ${call.method}',
            );
          }
          return null;
        });
  });
  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recorderChannel, null);
  });

  testWidgets('closing the assistant starts a fresh chat session', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    const history = ChatHistoryStore();
    const question = 'Tháng này tôi đã thu bao nhiêu?';
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
    await tester.enterText(find.byType(TextField), question);
    await tester.pump();
    await tester.tap(find.byTooltip('Gửi câu hỏi'));
    await tester.pumpAndSettle();
    expect(find.textContaining('tổng thu 250.000'), findsOneWidget);
    await tester.tap(find.byTooltip('Đóng trợ lý'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mở trợ lý'));
    await tester.pumpAndSettle();
    expect(find.textContaining('tổng thu 250.000'), findsNothing);
    expect(await history.loadLocal(), isEmpty);
    expect(tester.takeException(), isNull);
  });
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
  testWidgets('text-only chat answers income without persisting history', (
    tester,
  ) async {
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
    expect(saved, isEmpty);
  });
  testWidgets('LLM still answers when local facts never load', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final aiClient = _AnsweringAiChatClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiChatClientProvider.overrideWithValue(aiClient),
          localChatAssistantProvider.overrideWithValue(
            _PendingLocalChatAssistant(),
          ),
          chatHistoryStoreProvider.overrideWithValue(const ChatHistoryStore()),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'Tháng nào chênh lệch thu chi là bao nhiêu?',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Gửi câu hỏi'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('Câu trả lời từ LLM'), findsOneWidget);
    expect(aiClient.receivedFacts, isEmpty);
  });
  testWidgets('shows text instead of a spinner while thinking', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final aiClient = _PendingAiChatClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiChatClientProvider.overrideWithValue(aiClient),
          localChatAssistantProvider.overrideWithValue(
            _PendingLocalChatAssistant(),
          ),
          chatHistoryStoreProvider.overrideWithValue(const ChatHistoryStore()),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Tổng chi tháng này?');
    await tester.pump();
    await tester.tap(find.byTooltip('Gửi câu hỏi'));
    await tester.pump();

    expect(find.text('Đang suy nghĩ…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    aiClient.complete();
    await tester.pumpAndSettle();
  });
  testWidgets('LLM can select one local read-only tool before answering', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final aiClient = _ToolSelectingAiChatClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiChatClientProvider.overrideWithValue(aiClient),
          localChatAssistantProvider.overrideWithValue(
            _ToolExecutingLocalChatAssistant(),
          ),
          chatHistoryStoreProvider.overrideWithValue(const ChatHistoryStore()),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      'Chênh lệch thu chi tháng này?',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Gửi câu hỏi'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(aiClient.calls, 2);
    expect(
      aiClient.receivedFacts,
      contains(const ChatFact('total_minor_vnd', '4424997')),
    );
    expect(find.text('Chênh lệch là 1.575.003 đồng.'), findsOneWidget);
  });
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
  testWidgets('transaction drafts fall back to the existing Khác category', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final other = CategoryEntity(
      id: 'other',
      name: 'Khác',
      iconName: 'category',
      colorValue: 0xFF64748B,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiExtractionClientProvider.overrideWithValue(
            _DraftingAiClient(
              const TransactionDraftResult(
                isTransaction: true,
                type: 'expense',
                amountMinor: 90000,
                date: null,
                description: 'Chi tiêu kiểm thử',
                categoryId: null,
                clarification: '',
              ),
            ),
          ),
          incomeCategoriesProvider.overrideWith((ref) => Stream.value([])),
          categoriesProvider.overrideWith((ref) => Stream.value([other])),
          chatHistoryStoreProvider.overrideWithValue(const ChatHistoryStore()),
          invoiceRepositoryProvider.overrideWithValue(_InvoiceRepository()),
        ],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Hôm nay chi 90 nghìn');
    await tester.pump();
    await tester.tap(find.byTooltip('Gửi câu hỏi'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Khác'), findsOneWidget);
    expect(find.text('Xác nhận lưu'), findsOneWidget);
    expect(find.textContaining('Mình đã tạo bản nháp'), findsNothing);
  });
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

class _DraftingAiClient extends AiExtractionClient {
  _DraftingAiClient(this.result) : super(enabled: false);

  final TransactionDraftResult result;

  @override
  Future<TransactionDraftResult> draftTransaction(
    String text, {
    required DateTime today,
    required List<CategoryEntity> categories,
    TransactionDraftResult? previous,
  }) async {
    return result;
  }
}

class _PendingLocalChatAssistant extends Fake implements LocalChatAssistant {
  final _pendingReply = Completer<ChatReply>();

  @override
  Future<ChatReply> answer(String question, {DateTime? now}) =>
      _pendingReply.future;
}

class _AnsweringAiChatClient extends Fake implements AiChatClient {
  List<ChatFact>? receivedFacts;

  @override
  Future<ChatReply> answer(
    String question, {
    required List<ChatFact> facts,
    bool allowToolCalls = false,
  }) {
    receivedFacts = facts;
    return Future.value(const ChatReply(text: 'Câu trả lời từ LLM'));
  }
}

class _PendingAiChatClient extends Fake implements AiChatClient {
  final _pendingReply = Completer<ChatReply>();

  void complete() => _pendingReply.complete(
    const ChatReply(text: 'Câu trả lời sau khi suy nghĩ'),
  );

  @override
  Future<ChatReply> answer(
    String question, {
    required List<ChatFact> facts,
    bool allowToolCalls = false,
  }) => _pendingReply.future;
}

class _ToolSelectingAiChatClient extends Fake implements AiChatClient {
  int calls = 0;
  List<ChatFact>? receivedFacts;

  @override
  Future<ChatReply> answer(
    String question, {
    required List<ChatFact> facts,
    bool allowToolCalls = false,
  }) async {
    calls++;
    if (allowToolCalls) {
      return const ChatReply(
        text: 'Đang kiểm tra dữ liệu.',
        toolCall: ChatToolCall(name: 'get_cashflow_summary', period: 'current'),
      );
    }
    receivedFacts = facts;
    return const ChatReply(text: 'Chênh lệch là 1.575.003 đồng.');
  }
}

class _ToolExecutingLocalChatAssistant extends Fake
    implements LocalChatAssistant {
  @override
  Future<ChatReply> executeTool(ChatToolCall call, {DateTime? now}) async =>
      const ChatReply(
        text: 'Đã lấy dữ liệu.',
        facts: [
          ChatFact('income_total_minor_vnd', '6000000'),
          ChatFact('total_minor_vnd', '4424997'),
        ],
      );
}
