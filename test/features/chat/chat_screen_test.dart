import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/providers/app_providers.dart';
import 'package:hoadon_insight/features/chat/data/chat_history_store.dart';
import 'package:hoadon_insight/features/chat/domain/local_chat_assistant.dart';
import 'package:hoadon_insight/features/chat/presentation/chat_screen.dart';
import 'package:hoadon_insight/features/income/data/income_repository.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
