import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/database/app_database.dart';
import 'package:hoadon_insight/features/chat/domain/local_chat_assistant.dart';
import 'package:hoadon_insight/features/invoices/data/drift_invoice_repository.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  late AppDatabase database;
  late DriftInvoiceRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftInvoiceRepository(database);
  });

  tearDown(() => database.close());

  test('answers monthly total from local SQL aggregates', () async {
    final date = DateTime(2026, 8, 12);
    await repository.saveInvoice(
      _invoice('local-1', 'Cửa hàng A', 125000, date),
    );
    await repository.saveInvoice(
      _invoice('local-2', 'Cửa hàng B', 75000, date),
    );

    final reply = await LocalChatAssistant(
      repository,
    ).answer('Tháng 8/2026 tôi đã chi bao nhiêu?');

    expect(reply.text, contains('200.000'));
    expect(reply.text, contains('2 hóa đơn'));
    expect(reply.citations.single.sourceType, 'local');
    expect(reply.facts.any((fact) => fact.key == 'total_minor_vnd'), isTrue);
  });

  test('answers budget and recent invoice questions offline', () async {
    final date = DateTime(2026, 8, 12);
    await repository.saveInvoice(
      _invoice('local-3', 'Cửa hàng A', 800000, date),
    );
    await repository.saveBudget(
      const BudgetEntity(
        id: '2026-08-food',
        monthKey: '2026-08',
        categoryId: 'food',
        limitMinor: 1000000,
      ),
    );

    final assistant = LocalChatAssistant(repository);
    final budget = await assistant.answer(
      'Ngân sách tháng 8/2026 còn ổn không?',
    );
    final recent = await assistant.answer('Liệt kê hóa đơn gần đây');
    final search = await assistant.answer('Tìm hóa đơn của Cửa hàng A');
    final amountSearch = await assistant.answer('Tìm hóa đơn trên 500000');
    final combinedSearch = await assistant.answer(
      'Tìm hóa đơn của Cửa hàng A từ 500000 đến 900000',
    );
    final categorySearch = await assistant.answer(
      'Tìm hóa đơn danh mục ăn uống trên 500000 trong tháng 8/2026',
    );

    expect(budget.text, contains('80.0%'));
    expect(recent.text, contains('Cửa hàng A'));
    expect(search.text, contains('Cửa hàng A'));
    expect(
      search.citations.where((item) => item.sourceType == 'invoice'),
      hasLength(1),
    );
    expect(search.citations.last.label, contains('Cửa hàng A'));
    expect(amountSearch.text, contains('Cửa hàng A'));
    expect(combinedSearch.text, contains('Cửa hàng A'));
    expect(
      combinedSearch.citations.where((item) => item.sourceType == 'invoice'),
      hasLength(1),
    );
    expect(categorySearch.text, contains('danh mục Ăn uống'));
    expect(categorySearch.text, contains('Cửa hàng A'));
    expect(
      categorySearch.citations.where((item) => item.sourceType == 'invoice'),
      hasLength(1),
    );
  });
}

InvoiceEntity _invoice(String id, String seller, int total, DateTime date) {
  return InvoiceEntity(
    id: id,
    sellerName: seller,
    currencyCode: 'VND',
    subtotalMinor: total,
    taxMinor: 0,
    totalMinor: total,
    sourceType: InvoiceSourceType.manual,
    status: InvoiceStatus.confirmed,
    categoryId: 'food',
    issuedAt: date,
    createdAt: date,
    updatedAt: date,
  );
}
