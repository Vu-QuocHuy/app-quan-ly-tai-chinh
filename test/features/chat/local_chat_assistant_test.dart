import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/database/app_database.dart';
import 'package:hoadon_insight/features/chat/domain/local_chat_assistant.dart';
import 'package:hoadon_insight/features/chat/domain/chat_models.dart';
import 'package:hoadon_insight/features/chat/presentation/chat_screen.dart';
import 'package:hoadon_insight/features/income/data/income_repository.dart';
import 'package:hoadon_insight/features/invoices/data/drift_invoice_repository.dart';
import 'package:hoadon_insight/features/invoices/domain/invoice_models.dart';

void main() {
  late AppDatabase database;
  late DriftInvoiceRepository repository;
  late IncomeRepository incomes;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftInvoiceRepository(database);
    incomes = IncomeRepository(database);
  });

  tearDown(() => database.close());

  test('every quick prompt is understood by the offline assistant', () async {
    final assistant = LocalChatAssistant(repository, incomes);
    for (final prompt in chatQuickPrompts) {
      final reply = await assistant.answer(prompt, now: DateTime(2026, 8, 20));
      expect(
        reply.text,
        isNot(contains('Bạn có thể hỏi cụ thể hơn')),
        reason: prompt,
      );
      expect(reply.text, isNot(contains('Hãy nêu số tiền')), reason: prompt);
    }
  });

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
      incomes,
    ).answer('Tháng 8/2026 tôi đã chi bao nhiêu?');
    final habitual = await LocalChatAssistant(
      repository,
      incomes,
    ).answer('Tôi thường chi bao nhiêu tháng 8/2026?');

    expect(reply.text, contains('200.000'));
    expect(reply.text, contains('2 hóa đơn'));
    expect(habitual.text, contains('tổng cộng 200.000'));
    expect(reply.citations.single.sourceType, 'local');
    expect(reply.facts.any((fact) => fact.key == 'total_minor_vnd'), isTrue);
  });

  test(
    'calculates a hypothetical saving without recording a transaction',
    () async {
      final assistant = LocalChatAssistant(repository, incomes);
      final reply = await assistant.answer(
        'Nếu giảm chi 500k mỗi tháng trong 6 tháng?',
        now: DateTime(2026, 10, 20),
      );
      expect(reply.text, contains('3.000.000'));
      expect(reply.text, contains('chưa ghi giao dịch'));
      expect(await incomes.getAll(), isEmpty);
    },
  );

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

    final assistant = LocalChatAssistant(repository, incomes);
    final budget = await assistant.answer(
      'Ngân sách tháng 8/2026 còn ổn không?',
    );
    final recent = await assistant.answer('Liệt kê hóa đơn gần đây');
    final search = await assistant.answer('Tìm hóa đơn của Cửa hàng A');
    final spendingSearch = await assistant.answer(
      'Tôi đã chi ở Cửa hàng A bao nhiêu?',
    );
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
    expect(spendingSearch.text, contains('Cửa hàng A'));
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

  test('does not load local data for an unsupported question', () async {
    final reply = await LocalChatAssistant(
      repository,
      incomes,
    ).answer('Thời tiết hôm nay thế nào?');

    expect(reply.facts, isEmpty);
    expect(reply.citations, isEmpty);
    expect(reply.text, contains('Mình chưa bắt đúng ý bạn'));
  });

  test('answers income totals and categories from local data', () async {
    await repository.saveCategory(
      const CategoryEntity(
        id: 'income_freelance',
        name: 'Việc tự do',
        iconName: 'category',
        colorValue: 0xFF0F766E,
        kind: CategoryKind.income,
        isSystem: false,
      ),
    );
    await incomes.save(
      250000,
      source: IncomeSource.manual,
      categoryId: 'income_freelance',
    );

    final assistant = LocalChatAssistant(repository, incomes);
    final total = await assistant.answer('Tháng này tôi đã thu bao nhiêu?');
    final categories = await assistant.answer(
      'Danh mục thu nhiều nhất tháng này?',
    );
    final recent = await assistant.answer('Khoản thu gần đây');

    expect(total.text, contains('250.000'));
    expect(total.text, contains('1 khoản thu'));
    expect(categories.text, contains('Việc tự do'));
    expect(recent.text, contains('Việc tự do'));
    expect(total.citations.single.sourceType, 'local');
  });

  test(
    'loads income and expense facts for cashflow difference questions',
    () async {
      final now = DateTime(2026, 10, 22);
      await repository.saveInvoice(
        _invoice('cashflow-expense', 'Cửa hàng A', 4424997, now),
      );
      await incomes.save(6000000, source: IncomeSource.manual, receivedAt: now);

      final reply = await LocalChatAssistant(
        repository,
        incomes,
      ).answer('Chênh lệch thu chi tháng này bao nhiêu?', now: now);

      expect(
        reply.facts.map((fact) => (fact.key, fact.value)),
        containsAll([
          ('income_total_minor_vnd', '6000000'),
          ('total_minor_vnd', '4424997'),
        ]),
      );
    },
  );

  test('budget tool returns category spending and matching limits', () async {
    final now = DateTime(2026, 8, 12);
    await repository.saveInvoice(
      _invoice(
        'transport-expense',
        'Taxi',
        535000,
        now,
        categoryId: 'transport',
      ),
    );
    await repository.saveBudget(
      const BudgetEntity(
        id: '2026-08-transport',
        monthKey: '2026-08',
        categoryId: 'transport',
        limitMinor: 100000,
      ),
    );

    final reply = await LocalChatAssistant(repository, incomes).executeTool(
      const ChatToolCall(name: 'get_budget_status', period: '2026-08'),
      now: now,
    );

    expect(
      reply.facts.map((fact) => (fact.key, fact.value)),
      containsAll([
        ('category_transport_minor_vnd', '535000'),
        ('budget_transport_limit_minor_vnd', '100000'),
      ]),
    );
  });

  test('agent tools return recurring and recent invoice details', () async {
    for (final (id, date, amount) in [
      ('may', DateTime(2026, 5, 5), 200000),
      ('jun', DateTime(2026, 6, 5), 205000),
      ('jul', DateTime(2026, 7, 5), 195000),
    ]) {
      await repository.saveInvoice(_invoice(id, 'Nhà mạng', amount, date));
    }
    await repository.saveInvoice(
      _invoice('recent', 'Siêu thị A', 350000, DateTime(2026, 10, 20)),
    );
    final assistant = LocalChatAssistant(repository, incomes);

    final recurring = await assistant.executeTool(
      const ChatToolCall(name: 'get_spending_insights', period: '2026-10'),
      now: DateTime(2026, 10, 22),
    );
    final recent = await assistant.executeTool(
      const ChatToolCall(name: 'get_recent_invoices', period: '2026-10'),
      now: DateTime(2026, 10, 22),
    );

    expect(
      recurring.facts.map((fact) => (fact.key, fact.value)),
      containsAll([
        ('recurring_1_merchant', 'Nhà mạng'),
        ('recurring_1_cadence', 'Hàng tháng'),
        ('recurring_1_average_minor_vnd', '200000'),
      ]),
    );
    expect(
      recent.facts.map((fact) => (fact.key, fact.value)),
      containsAll([
        ('recent_invoice_1_seller', 'Siêu thị A'),
        ('recent_invoice_1_date', '2026-10-20'),
        ('recent_invoice_1_amount_minor_vnd', '350000'),
      ]),
    );
  });
}

InvoiceEntity _invoice(
  String id,
  String seller,
  int total,
  DateTime date, {
  String categoryId = 'food',
}) {
  return InvoiceEntity(
    id: id,
    sellerName: seller,
    currencyCode: 'VND',
    subtotalMinor: total,
    taxMinor: 0,
    totalMinor: total,
    sourceType: InvoiceSourceType.manual,
    status: InvoiceStatus.confirmed,
    categoryId: categoryId,
    issuedAt: date,
    createdAt: date,
    updatedAt: date,
  );
}
