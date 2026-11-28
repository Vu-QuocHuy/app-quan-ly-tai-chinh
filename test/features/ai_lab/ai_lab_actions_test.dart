import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/monitoring/ai_lab_store.dart';
import 'package:hoadon_insight/core/monitoring/ai_telemetry.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/ai_lab/application/ai_lab_actions.dart';
import 'package:hoadon_insight/features/ai_lab/application/ai_lab_import_hook.dart';
import 'package:hoadon_insight/features/ai_lab/application/ai_lab_providers.dart';
import 'package:hoadon_insight/features/chat/data/chat_history_store.dart';
import 'package:hoadon_insight/features/chat/domain/chat_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> loadedAssets;
  late ProviderContainer container;
  late DefaultAiLabActions actions;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AiLabStore.instance.reset();
    loadedAssets = [];
    container = ProviderContainer(
      overrides: [
        chatHistoryStoreProvider.overrideWithValue(const ChatHistoryStore()),
      ],
    );
    final ref = container.read(Provider<Ref>((ref) => ref));
    actions = DefaultAiLabActions(
      ref,
      loadAsset: (path) async {
        loadedAssets.add(path);
        return ByteData.sublistView(Uint8List.fromList([1, 2, 3, 4]), 1, 4);
      },
    );
  });

  tearDown(() {
    container.dispose();
    AiLabStore.instance.reset();
  });

  test('aiLabActionsProvider mặc định là DefaultAiLabActions', () {
    expect(container.read(aiLabActionsProvider), isA<DefaultAiLabActions>());
  });

  test('askPreset đặt aiLabPromptRequestProvider', () async {
    await actions.askPreset('Tháng này tôi chi bao nhiêu?');
    expect(
      container.read(aiLabPromptRequestProvider),
      'Tháng này tôi chi bao nhiêu?',
    );
  });

  test('setFault ghi vào AiLabStore (null = tắt)', () {
    actions.setFault('429');
    expect(AiLabStore.instance.fault, '429');
    actions.setFault(null);
    expect(AiLabStore.instance.fault, isNull);
  });

  test('setTamperTotal ghi vào AiLabStore', () {
    actions.setTamperTotal(true);
    expect(AiLabStore.instance.tamperExtractTotal, isTrue);
    actions.setTamperTotal(false);
    expect(AiLabStore.instance.tamperExtractTotal, isFalse);
  });

  test('importAsset đọc asset và tạo XFile cùng tên cho đường nhập ảnh', () async {
    await actions.importAsset('assets/ai_lab/receipt_normal.png');
    expect(loadedAssets, ['assets/ai_lab/receipt_normal.png']);
    final file = container.read(aiLabImportRequestProvider)!;
    expect(file.name, 'receipt_normal.png');
    expect(await file.readAsBytes(), [2, 3, 4]);
  });

  test('resetLocal xóa AI Lab, telemetry, lịch sử chat; giữ dữ liệu khác', () async {
    const history = ChatHistoryStore();
    await history.save([
      ChatMessage(
        id: 'm1',
        role: ChatMessageRole.user,
        text: 'xin chào',
        createdAt: DateTime(2026, 11, 28),
      ),
    ]);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('invoices.cache', 'giữ nguyên');
    AiLabStore.instance
      ..fault = '500'
      ..tamperExtractTotal = true
      ..recordCall(const AiLabCall(action: 'chat', durationMs: 5, llmCalls: 2));
    AiTelemetry.instance.recordLocal('chat');
    container.read(aiLabPromptRequestProvider.notifier).state = 'chờ gửi';
    container.read(aiLabLastAnswerProvider.notifier).state = const AiLabAnswer(
      messageId: 'a',
      text: 'b',
    );

    await actions.resetLocal();

    expect(AiLabStore.instance.fault, isNull);
    expect(AiLabStore.instance.tamperExtractTotal, isFalse);
    expect(AiLabStore.instance.totals.llmCalls, 0);
    expect(AiTelemetry.instance.events, isEmpty);
    expect(await history.loadLocal(), isEmpty);
    expect(container.read(aiLabPromptRequestProvider), isNull);
    expect(container.read(aiLabLastAnswerProvider), isNull);
    expect(preferences.getString('invoices.cache'), 'giữ nguyên');
  });
}
