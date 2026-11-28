import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/chat/domain/chat_routing_rules.dart';
import 'package:hoadon_insight/features/chat/presentation/chat_screen.dart';

void main() {
  // Write commands / transaction entries. None of them may be treated as a
  // read-only question (KPI M6 gate: 0 commands misread as questions).
  const writeCommands = [
    'Hôm nay chi 90 nghìn ăn trưa',
    'Ghi lại khoản chi 50k cà phê',
    'Thêm khoản thu lương 15 triệu',
    'Nam nợ tôi 500k',
    'Tôi cho Lan vay 2 triệu',
    'Tôi vay Minh 300.000đ',
    'Trả nợ cho Hùng 200k',
    'Đặt ngân sách ăn uống 3 triệu',
    'Đặt hạn mức mua sắm tháng này 2 triệu',
    'Xóa khoản chi vừa rồi',
    'Sửa khoản chi hôm qua thành 120k',
    'Góp quỹ nhóm du lịch 500k',
    'Tạo lịch nhắc tiền nhà hàng tháng',
    'Nhắc tôi trả tiền điện ngày 5',
    'Huỷ',
    'Lưu khoản này',
    'Nhận lương 12tr',
    'Mua sữa 45.000',
    'Record 50k for lunch',
    'Add an expense of 200000',
  ];

  test('write commands are never read-only questions', () {
    for (final text in writeCommands) {
      expect(ChatRoutingRules.isReadOnlyQuestion(text), isFalse, reason: text);
      expect(ChatRoutingRules.localIntent(text), isNull, reason: text);
    }
  });

  test('typical lookups are read-only questions', () {
    for (final text in [
      'Tháng này tôi đã chi bao nhiêu?',
      'Tôi còn bao nhiêu hạn mức ngân sách?',
      'Tôi đang nợ ai?',
      'Danh mục nào chi nhiều nhất',
      'Xem thu chi tháng trước',
      'Tại sao tháng này chi nhiều vậy?',
      'How much did I spend this month?',
    ]) {
      expect(ChatRoutingRules.isReadOnlyQuestion(text), isTrue, reason: text);
    }
  });

  test('every Vietnamese quick prompt routes locally', () {
    for (final prompt in chatQuickPrompts) {
      expect(ChatRoutingRules.localIntent(prompt), isNotNull, reason: prompt);
    }
  });

  test('maps standard lookups to the right local intent', () {
    final cases = {
      'Tháng này tôi đã chi bao nhiêu?': LocalChatIntent.expenseTotal,
      'Tổng chi tháng 8/2026': LocalChatIntent.expenseTotal,
      'Tháng trước tôi chi bao nhiêu?': LocalChatIntent.expenseTotal,
      'Tháng này tôi đã thu bao nhiêu?': LocalChatIntent.incomeTotal,
      'Tôi còn bao nhiêu ngân sách?': LocalChatIntent.budget,
      'Tôi đang nợ ai?': LocalChatIntent.debt,
      'Ai nợ tôi?': LocalChatIntent.debt,
      'Tổng nợ của tôi là bao nhiêu': LocalChatIntent.debt,
      'Danh mục nào chi nhiều nhất?': LocalChatIntent.topCategory,
      'So sánh chi tiêu tháng này với tháng trước': LocalChatIntent.comparison,
      'Dự báo chi tiêu đến cuối tháng': LocalChatIntent.forecast,
      'Hóa đơn gần đây của tôi': LocalChatIntent.recentInvoices,
      'Có khoản chi nào bất thường không?': LocalChatIntent.anomaly,
      'Tôi có khoản chi định kỳ nào không?': LocalChatIntent.recurring,
      'Nếu tôi giảm chi 500.000đ mỗi tháng thì tiết kiệm được bao nhiêu?':
          LocalChatIntent.scenario,
    };
    cases.forEach((question, intent) {
      expect(ChatRoutingRules.localIntent(question), intent, reason: question);
    });
  });

  test('analytical or mixed questions go to the LLM', () {
    for (final text in [
      'Tại sao tháng này tôi chi nhiều vậy?',
      'Gợi ý 3 cách tiết kiệm tiền ăn uống',
      'Tôi có nên mua iPhone không?',
      'Tháng nào chênh lệch thu chi là bao nhiêu?',
      'Chênh lệch thu chi tháng này?',
      'Thu và chi tháng này thế nào?',
      'Lịch định kỳ của tôi có gì?',
      'Quỹ nhóm du lịch còn bao nhiêu?',
      'Thời tiết hôm nay thế nào?',
    ]) {
      expect(ChatRoutingRules.localIntent(text), isNull, reason: text);
    }
  });

  test('guesses tools and period for prefetched FACTS', () {
    final now = DateTime(2026, 11, 7);
    List<String> tools(String q) => [
      for (final call in ChatRoutingRules.guessTools(q, now: now)) call.name,
    ];
    expect(tools('Chênh lệch thu chi tháng này?'), ['get_cashflow_summary']);
    expect(tools('Tại sao tháng này chi nhiều?'), ['get_expense_summary']);
    expect(tools('Tôi nên trả nợ ai trước?'), ['get_debt_summary']);
    expect(tools('Lịch nhắc định kỳ của tôi'), [
      'get_recurring_schedules',
      'get_spending_insights',
    ]);
    expect(tools('Quỹ nhóm còn bao nhiêu?'), ['get_group_summary']);
    expect(tools('Phân tích ngân sách giúp tôi'), ['get_budget_status']);
    expect(tools('Xin chào'), isEmpty);
    expect(
      ChatRoutingRules.guessTools(
        'Tại sao tháng trước chi nhiều?',
        now: now,
      ).single.period,
      '2026-10',
    );
    expect(
      ChatRoutingRules.guessTools(
        'Chi tiêu tháng 8/2026 thế nào?',
        now: now,
      ).single.period,
      '2026-08',
    );
    expect(ChatRoutingRules.periodFor('Tháng 11 chi gì', now: now), 'current');
  });
}
