import '../../../core/utils/money_formatter.dart';
import '../../../core/utils/month_utils.dart';
import '../../income/data/income_repository.dart';
import '../../ingestion/domain/quick_transaction_parser.dart';
import '../../invoices/domain/invoice_filters.dart';
import '../../invoices/domain/invoice_models.dart';
import '../../invoices/domain/invoice_repository.dart';
import 'chat_models.dart';
import 'local_chat_tools.dart';

class LocalChatAssistant {
  const LocalChatAssistant(this._repository, this._incomes);

  final InvoiceRepository _repository;
  final IncomeRepository _incomes;

  Future<ChatReply> executeTool(ChatToolCall call, {DateTime? now}) async {
    final reference = now ?? DateTime.now();
    final match = RegExp(r'^(\d{4})-(0[1-9]|1[0-2])$').firstMatch(call.period);
    final month = call.period == 'current'
        ? DateTime(reference.year, reference.month)
        : match == null
        ? throw const FormatException('Kỳ dữ liệu không hợp lệ.')
        : DateTime(int.parse(match.group(1)!), int.parse(match.group(2)!));
    final tools = LocalChatTools(_repository, _incomes);
    final monthKey = MonthUtils.key(month);
    final citation = ChatCitation(
      label: 'Dữ liệu cá nhân ${MonthUtils.label(month)}',
      sourceType: 'local',
      sourceId: monthKey,
    );

    switch (call.name) {
      case 'get_cashflow_summary':
        final dashboard = await tools.monthSummary(monthKey);
        final income = (await tools.incomeEntries())
            .where((entry) => MonthUtils.key(entry.receivedAt) == monthKey)
            .fold<int>(0, (sum, entry) => sum + entry.amountMinor);
        return ChatReply(
          text: 'Đã lấy dữ liệu thu chi.',
          citations: [citation],
          facts: [
            ChatFact('period', MonthUtils.label(month)),
            ChatFact('income_total_minor_vnd', '$income'),
            ChatFact('total_minor_vnd', '${dashboard.totalMinor}'),
          ],
        );
      case 'get_expense_summary':
        final dashboard = await tools.monthSummary(monthKey);
        return ChatReply(
          text: 'Đã lấy dữ liệu chi tiêu.',
          citations: [citation],
          facts: [
            ..._summaryFacts(dashboard, month),
            ..._categoryFacts(dashboard),
          ],
        );
      case 'get_income_summary':
        final entries = (await tools.incomeEntries())
            .where((entry) => MonthUtils.key(entry.receivedAt) == monthKey)
            .toList(growable: false);
        return ChatReply(
          text: 'Đã lấy dữ liệu khoản thu.',
          citations: [citation],
          facts: [
            ChatFact('period', MonthUtils.label(month)),
            ChatFact('income_count', '${entries.length}'),
            ChatFact(
              'income_total_minor_vnd',
              '${entries.fold<int>(0, (sum, entry) => sum + entry.amountMinor)}',
            ),
          ],
        );
      case 'get_budget_status':
        final result = await tools.budgetStatus(monthKey);
        return ChatReply(
          text: 'Đã lấy tình hình ngân sách.',
          citations: [citation],
          facts: _budgetFacts(result.dashboard, result.budgets, month),
        );
      case 'get_spending_insights':
        final insights = await tools.spendingInsights(monthKey);
        return ChatReply(
          text: 'Đã lấy phân tích chi tiêu.',
          citations: [citation],
          facts: [
            ..._insightFacts(insights, month),
            ..._recurringFacts(insights),
          ],
        );
      case 'get_recent_invoices':
        final invoices = (await tools.recentTransactions(limit: 5)).items;
        return ChatReply(
          text: 'Đã lấy các hóa đơn gần đây.',
          citations: _invoiceCitations(citation, invoices),
          facts: [
            ..._resultFacts(invoices),
            for (final (index, invoice) in invoices.indexed) ...[
              ChatFact(
                'recent_invoice_${index + 1}_seller',
                invoice.sellerName,
              ),
              ChatFact(
                'recent_invoice_${index + 1}_date',
                (invoice.issuedAt ?? invoice.createdAt)
                    .toIso8601String()
                    .substring(0, 10),
              ),
              ChatFact(
                'recent_invoice_${index + 1}_amount_minor_vnd',
                '${invoice.totalMinor}',
              ),
            ],
          ],
        );
      default:
        throw const FormatException('Công cụ chatbot không được phép.');
    }
  }

  Future<ChatReply> answer(String question, {DateTime? now}) async {
    final tools = LocalChatTools(_repository, _incomes);
    final reference = now ?? DateTime.now();
    final normalized = _normalize(question);
    final month = _monthFromQuestion(normalized, reference);
    final monthKey = MonthUtils.key(month);
    final merchantQuery = _merchantQuery(question);
    final amountBounds = _amountBounds(question);
    final citation = ChatCitation(
      label: 'Dữ liệu hóa đơn ${MonthUtils.label(month)}',
      sourceType: 'local',
      sourceId: monthKey,
      capturedAt: DateTime.now(),
    );

    if (normalized.contains('neu ') &&
        (normalized.contains('giam chi') ||
            normalized.contains('tang thu') ||
            normalized.contains('tiet kiem'))) {
      QuickTransaction scenario;
      try {
        scenario = QuickTransactionParser.parse(question, now: reference);
      } on FormatException {
        return const ChatReply(
          text:
              'Hãy nêu số tiền muốn giảm chi, tăng thu hoặc tiết kiệm mỗi tháng.',
        );
      }
      final period = RegExp(r'(\d+)\s*thang').firstMatch(normalized);
      final months = int.tryParse(period?.group(1) ?? '') ?? 1;
      if (months < 1 || months > 60) {
        return const ChatReply(
          text: 'Hãy chọn khoảng thời gian từ 1 đến 60 tháng.',
        );
      }
      final insights = await tools.spendingInsights(monthKey);
      final income = (await tools.incomeEntries())
          .where((entry) => MonthUtils.key(entry.receivedAt) == monthKey)
          .fold<int>(0, (sum, entry) => sum + entry.amountMinor);
      final baseSavings = income - insights.forecastTotalMinor;
      final adjustedSavings = baseSavings + scenario.amountMinor;
      return ChatReply(
        text:
            'Nếu bạn điều chỉnh ${MoneyFormatter.format(scenario.amountMinor)} mỗi tháng, '
            'mức tích lũy dự kiến sẽ là ${MoneyFormatter.format(adjustedSavings)}/tháng. '
            'Sau $months tháng, bạn có thể để dành được khoảng ${MoneyFormatter.format(adjustedSavings * months)} 🎉. '
            '(Lưu ý: Đây là ước tính giả định, chưa ghi giao dịch vào ứng dụng nhé).',
        citations: [citation],
        facts: [
          ChatFact('period', MonthUtils.label(month)),
          ChatFact('scenario_monthly_savings_minor_vnd', '$adjustedSavings'),
          ChatFact('scenario_months', '$months'),
        ],
      );
    }

    if (_isCashflowBalanceQuestion(normalized)) {
      final dashboard = await tools.monthSummary(monthKey);
      final income = (await tools.incomeEntries())
          .where((entry) => MonthUtils.key(entry.receivedAt) == monthKey)
          .fold<int>(0, (sum, entry) => sum + entry.amountMinor);
      return ChatReply(
        text: 'Mình đã lấy dữ liệu thu và chi của ${MonthUtils.label(month)}.',
        citations: [citation],
        facts: [
          ChatFact('period', MonthUtils.label(month)),
          ChatFact('income_total_minor_vnd', '$income'),
          ChatFact('total_minor_vnd', '${dashboard.totalMinor}'),
        ],
      );
    }

    if (_isIncomeQuestion(normalized)) {
      final entries = await tools.incomeEntries();
      final categories = await tools.incomeCategories();
      final names = {
        for (final category in categories) category.id: category.name,
      };
      final monthly = entries
          .where((entry) => MonthUtils.key(entry.receivedAt) == monthKey)
          .toList(growable: false);
      final total = monthly.fold<int>(
        0,
        (sum, entry) => sum + entry.amountMinor,
      );
      String answer;
      if (normalized.contains('gan day') || normalized.contains('moi nhat')) {
        if (entries.isEmpty) {
          answer = 'Bạn chưa có khoản thu nào được ghi nhận trên thiết bị.';
        } else {
          final items = entries
              .take(5)
              .map(
                (entry) =>
                    '• ${names[entry.categoryId] ?? 'Chưa phân loại'}: ${MoneyFormatter.format(entry.amountMinor)}',
              )
              .join('\n');
          answer = 'Mình tìm thấy các khoản thu gần đây này:\n$items';
        }
      } else if (_isCategoryQuestion(normalized) ||
          _isRankingQuestion(normalized)) {
        final totals = <String, int>{};
        for (final entry in monthly) {
          totals.update(
            entry.categoryId,
            (value) => value + entry.amountMinor,
            ifAbsent: () => entry.amountMinor,
          );
        }
        final ranked = totals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        if (ranked.isEmpty) {
          answer =
              'Trong ${MonthUtils.label(month)}, bạn chưa có khoản thu nào.';
        } else {
          final items = ranked
              .take(5)
              .map(
                (entry) =>
                    '• ${names[entry.key] ?? 'Chưa phân loại'}: ${MoneyFormatter.format(entry.value)}',
              )
              .join('\n');
          answer =
              'Các nguồn thu trong ${MonthUtils.label(month)} theo danh mục gồm:\n$items';
        }
      } else {
        answer =
            'Trong ${MonthUtils.label(month)}, bạn đã ghi nhận ${monthly.length} khoản thu với tổng thu ${MoneyFormatter.format(total)}.'
            '${total > 0 ? ' 👏 Tiếp tục phát huy nhé!' : ''}';
      }
      return ChatReply(
        text: answer,
        citations: [
          ChatCitation(
            label: 'Dữ liệu khoản thu ${MonthUtils.label(month)}',
            sourceType: 'local',
            sourceId: monthKey,
          ),
        ],
        facts: [
          ChatFact('period', MonthUtils.label(month)),
          ChatFact('income_count', '${monthly.length}'),
          ChatFact('income_total_minor_vnd', '$total'),
        ],
      );
    }

    if (_isBudgetQuestion(normalized)) {
      final result = await tools.budgetStatus(monthKey);
      return ChatReply(
        text: _budgetAnswer(result.dashboard, result.budgets, month),
        citations: [citation],
        facts: _budgetFacts(result.dashboard, result.budgets, month),
      );
    }
    if (_isRecurringQuestion(normalized)) {
      final insights = await tools.spendingInsights(monthKey);
      return ChatReply(
        text: _recurringAnswer(insights),
        citations: [citation],
        facts: _insightFacts(insights, month),
      );
    }
    if (_isForecastQuestion(normalized)) {
      final insights = await tools.spendingInsights(monthKey);
      return ChatReply(
        text:
            'Dựa trên tốc độ chi tiêu hàng ngày, dự báo tổng chi ${MonthUtils.label(month)} của bạn sẽ vào khoảng '
            '${MoneyFormatter.format(insights.forecastTotalMinor)} '
            '(hiện tại bạn đã ghi nhận ${MoneyFormatter.format(insights.currentTotalMinor)}).',
        citations: [citation],
        facts: _insightFacts(insights, month),
      );
    }
    if (_isAnomalyQuestion(normalized)) {
      final insights = await tools.spendingInsights(monthKey);
      return ChatReply(
        text: _anomalyAnswer(insights),
        citations: _anomalyCitations(citation, insights.anomalies),
        facts: _insightFacts(insights, month),
      );
    }
    if ((_isCategoryQuestion(normalized) || _isRankingQuestion(normalized)) &&
        !normalized.contains('tim hoa don')) {
      final dashboard = await tools.monthSummary(monthKey);
      final categories = await tools.categories();
      final categoryNames = {
        for (final category in categories) category.id: category.name,
      };
      return ChatReply(
        text: _categoryAnswer(
          dashboard,
          categoryNames,
          month,
          ranking: _isRankingQuestion(normalized),
        ),
        citations: [citation],
        facts: [
          ..._summaryFacts(dashboard, month),
          ..._categoryFacts(dashboard),
        ],
      );
    }
    if (_isComparisonQuestion(normalized)) {
      final dashboard = await tools.monthSummary(monthKey);
      return ChatReply(
        text: _comparisonAnswer(dashboard, month),
        citations: [citation],
        facts: _summaryFacts(dashboard, month),
      );
    }
    if (_isRecentInvoiceQuestion(normalized)) {
      final recentInvoices = await tools.recentTransactions();
      return ChatReply(
        text: _recentInvoiceAnswer(recentInvoices.items),
        citations: _invoiceCitations(citation, recentInvoices.items),
        facts: _resultFacts(recentInvoices.items),
      );
    }
    final categories = normalized.contains('danh muc')
        ? await tools.categories()
        : const <CategoryEntity>[];
    final categoryNames = {
      for (final category in categories) category.id: category.name,
    };
    final categoryId = _categoryQuery(normalized, categoryNames);
    final hasSearch =
        merchantQuery != null || amountBounds != null || categoryId != null;
    if (hasSearch) {
      final searchedInvoices = await tools.searchTransactions(
        filter: InvoiceFilter(
          query: merchantQuery ?? '',
          monthKey: normalized.contains('thang') ? monthKey : null,
          categoryId: categoryId,
          minTotalMinor: amountBounds?.$1,
          maxTotalMinor: amountBounds?.$2,
        ),
      );
      return ChatReply(
        text: _searchAnswer(
          searchedInvoices.items,
          _searchLabel(
            merchantQuery: merchantQuery,
            amountBounds: amountBounds,
            categoryId: categoryId,
            categoryNames: categoryNames,
            month: month,
            includeMonth: normalized.contains('thang'),
          ),
        ),
        citations: _invoiceCitations(citation, searchedInvoices.items),
        facts: _resultFacts(searchedInvoices.items),
      );
    }
    if (_isTotalQuestion(normalized)) {
      final dashboard = await tools.monthSummary(monthKey);
      final count = dashboard.invoiceCount;
      final total = MoneyFormatter.format(dashboard.totalMinor);
      final text = count == 0
          ? 'Trong ${MonthUtils.label(month)}, mình chưa thấy hóa đơn nào được ghi nhận; tổng chi là 0 đ.'
          : 'Trong ${MonthUtils.label(month)}, bạn đã ghi nhận $count hóa đơn, tổng cộng $total.';
      return ChatReply(
        text: text,
        citations: [citation],
        facts: _summaryFacts(dashboard, month),
      );
    }

    return ChatReply(
      text:
          'Mình chưa bắt đúng ý bạn. Bạn thử hỏi về tổng thu, tổng chi, ngân sách, '
          'danh mục chi tiêu, so sánh các tháng hoặc dự báo chi tiêu nhé.',
      citations: const [],
    );
  }

  List<ChatFact> _summaryFacts(DashboardSnapshot dashboard, DateTime month) {
    return [
      ChatFact('period', MonthUtils.label(month)),
      ChatFact('invoice_count', '${dashboard.invoiceCount}'),
      ChatFact('total_minor_vnd', '${dashboard.totalMinor}'),
      ChatFact(
        'previous_total_minor_vnd',
        '${dashboard.previousMonthTotalMinor}',
      ),
    ];
  }

  List<ChatFact> _budgetFacts(
    DashboardSnapshot dashboard,
    List<BudgetEntity> budgets,
    DateTime month,
  ) {
    return [
      ..._summaryFacts(dashboard, month),
      ..._categoryFacts(dashboard),
      ChatFact('budget_count', '${budgets.length}'),
      ChatFact('budget_limit_minor_vnd', '${dashboard.budgetLimitMinor}'),
      for (final budget in budgets)
        ChatFact(
          'budget_${budget.categoryId}_limit_minor_vnd',
          '${budget.limitMinor}',
        ),
    ];
  }

  List<ChatFact> _insightFacts(SpendingInsights insights, DateTime month) {
    return [
      ChatFact('period', MonthUtils.label(month)),
      ChatFact('forecast_total_minor_vnd', '${insights.forecastTotalMinor}'),
      ChatFact('recurring_count', '${insights.recurringExpenses.length}'),
      ChatFact('anomaly_count', '${insights.anomalies.length}'),
    ];
  }

  List<ChatFact> _recurringFacts(SpendingInsights insights) => [
    for (final (index, item) in insights.recurringExpenses.take(3).indexed) ...[
      ChatFact('recurring_${index + 1}_merchant', item.merchant),
      ChatFact('recurring_${index + 1}_cadence', item.cadenceLabel),
      ChatFact(
        'recurring_${index + 1}_average_minor_vnd',
        '${item.averageMinor}',
      ),
    ],
  ];

  List<ChatFact> _categoryFacts(DashboardSnapshot dashboard) {
    const ids = [
      'food',
      'transport',
      'shopping',
      'utilities',
      'health',
      'education',
      'entertainment',
      'other',
    ];
    return [
      for (final id in ids)
        if (dashboard.categoryTotals.containsKey(id))
          ChatFact(
            'category_${id}_minor_vnd',
            '${dashboard.categoryTotals[id]}',
          ),
    ];
  }

  List<ChatFact> _resultFacts(Iterable<InvoiceEntity> invoices) {
    final items = invoices.toList(growable: false);
    return [
      ChatFact('result_count', '${items.length}'),
      ChatFact(
        'result_total_minor_vnd',
        '${items.fold<int>(0, (total, invoice) => total + invoice.totalMinor)}',
      ),
    ];
  }

  String _budgetAnswer(
    DashboardSnapshot dashboard,
    List<BudgetEntity> budgets,
    DateTime month,
  ) {
    if (budgets.isEmpty || dashboard.budgetLimitMinor <= 0) {
      return 'Trong ${MonthUtils.label(month)}, bạn chưa đặt hạn mức ngân sách nào.';
    }
    final progress = (dashboard.budgetProgress * 100).toStringAsFixed(1);
    final evaluation = dashboard.budgetProgress >= 1.0
        ? '⚠️ Chi tiêu đã vượt hạn mức rồi! Bạn hãy cân nhắc thắt chặt chi tiêu trong những ngày tới nhé.'
        : dashboard.budgetProgress >= 0.8
        ? '⚠️ Chi tiêu đã chạm mức $progress% ngân sách rồi, bạn nên cẩn thận với các khoản chi lớn.'
        : '✅ Chi tiêu vẫn đang nằm trong tầm kiểm soát rất tốt!';

    return 'Tình hình ngân sách ${MonthUtils.label(month)}:\n'
        '• Đã chi ${MoneyFormatter.format(dashboard.totalMinor)} trên tổng ngân sách ${MoneyFormatter.format(dashboard.budgetLimitMinor)} ($progress%).\n'
        '• Bạn đang theo dõi ${budgets.length} danh mục có hạn mức.\n'
        '$evaluation';
  }

  String _recurringAnswer(SpendingInsights insights) {
    if (insights.recurringExpenses.isEmpty) {
      return 'Hiện tại mình chưa thấy khoản chi nào lặp lại đều đặn để xác định là chi định kỳ cả.';
    }
    final items = insights.recurringExpenses
        .take(3)
        .map((item) {
          return '• ${item.merchant} (${item.cadenceLabel}, trung bình ${MoneyFormatter.format(item.averageMinor)})';
        })
        .join('\n');
    return 'Dưới đây là các khoản chi định kỳ nổi bật của bạn:\n$items';
  }

  String _categoryAnswer(
    DashboardSnapshot dashboard,
    Map<String, String> categoryNames,
    DateTime month, {
    required bool ranking,
  }) {
    final totals = dashboard.categoryTotals.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    if (totals.isEmpty) {
      return 'Trong ${MonthUtils.label(month)}, bạn chưa có dữ liệu chi tiêu theo danh mục.';
    }
    final visible = ranking ? totals.take(3) : totals.take(1);
    if (!ranking) {
      final top = visible.first;
      final name = categoryNames[top.key] ?? top.key;
      return 'Danh mục chi nhiều nhất ${MonthUtils.label(month)} là $name với ${MoneyFormatter.format(top.value)}.';
    }
    final items = visible
        .map((entry) {
          return '• ${categoryNames[entry.key] ?? entry.key}: ${MoneyFormatter.format(entry.value)}';
        })
        .join('\n');
    return 'Các danh mục chi nhiều nhất ${MonthUtils.label(month)} gồm:\n$items';
  }

  String _comparisonAnswer(DashboardSnapshot dashboard, DateTime month) {
    final previous = dashboard.previousMonthTotalMinor;
    if (previous <= 0) {
      return 'Chưa có đủ dữ liệu tháng trước để so sánh với ${MonthUtils.label(month)}.';
    }
    final difference = dashboard.totalMinor - previous;
    final percent = (difference.abs() / previous * 100).toStringAsFixed(1);
    final direction = difference == 0
        ? 'tương đương'
        : difference > 0
        ? 'tăng $percent%'
        : 'giảm $percent%';
    final remark = difference < 0
        ? '👏 Thật tuyệt vời! Bạn đang chi tiêu tiết kiệm hơn tháng trước đấy.'
        : difference > 0
        ? '💡 Chi tiêu đang có xu hướng tăng hơn, bạn thử kiểm tra các danh mục phát sinh nhé.'
        : 'Mức chi tiêu duy trì ổn định so với tháng trước.';

    return 'So sánh chi tiêu với tháng trước (${MoneyFormatter.format(previous)}):\n'
        'Trong ${MonthUtils.label(month)}, bạn chi ${MoneyFormatter.format(dashboard.totalMinor)}, $direction so với tháng trước.\n'
        '$remark';
  }

  String _recentInvoiceAnswer(List<InvoiceEntity> invoices) {
    if (invoices.isEmpty) {
      return 'Bạn chưa có hóa đơn nào được lưu trên thiết bị.';
    }
    final items = invoices
        .take(5)
        .map((invoice) {
          return '• ${invoice.sellerName}: ${MoneyFormatter.format(invoice.totalMinor)}';
        })
        .join('\n');
    return 'Mình tìm thấy các hóa đơn gần đây này:\n$items';
  }

  String _anomalyAnswer(SpendingInsights insights) {
    if (insights.anomalies.isEmpty) {
      return 'Mọi thứ đều ổn! Mình chưa phát hiện khoản chi nào cao bất thường so với thói quen hàng ngày của bạn.';
    }
    final items = insights.anomalies
        .take(3)
        .map((item) {
          return '• ${item.merchant}: ${MoneyFormatter.format(item.amountMinor)} (${item.explanation})';
        })
        .join('\n');
    return 'Mình nhận thấy một số khoản chi cao hơn mức bình thường, bạn kiểm tra lại nhé:\n$items';
  }

  List<ChatCitation> _invoiceCitations(
    ChatCitation periodCitation,
    Iterable<InvoiceEntity> invoices,
  ) {
    return [
      periodCitation,
      ...invoices
          .take(5)
          .map(
            (invoice) => ChatCitation(
              label: _invoiceCitationLabel(invoice),
              sourceType: 'invoice',
              sourceId: invoice.id,
            ),
          ),
    ];
  }

  List<ChatCitation> _anomalyCitations(
    ChatCitation periodCitation,
    Iterable<SpendingAnomaly> anomalies,
  ) {
    return [
      periodCitation,
      ...anomalies
          .take(5)
          .map(
            (item) => ChatCitation(
              label:
                  'Mở ${item.merchant} · ${MoneyFormatter.format(item.amountMinor)}',
              sourceType: 'invoice',
              sourceId: item.invoiceId,
            ),
          ),
    ];
  }

  String _invoiceCitationLabel(InvoiceEntity invoice) {
    return 'Mở ${invoice.sellerName} · '
        '${MoneyFormatter.format(invoice.totalMinor)}';
  }

  String _searchAnswer(List<InvoiceEntity> invoices, String query) {
    if (invoices.isEmpty) {
      return 'Không tìm thấy hóa đơn nào phù hợp với “$query”.';
    }
    final items = invoices
        .take(5)
        .map((invoice) {
          return '• ${invoice.sellerName}: ${MoneyFormatter.format(invoice.totalMinor)}';
        })
        .join('\n');
    return 'Mình tìm thấy ${invoices.length} hóa đơn phù hợp với “$query”:\n$items';
  }

  String _searchLabel({
    required String? merchantQuery,
    required (int?, int?)? amountBounds,
    required String? categoryId,
    required Map<String, String> categoryNames,
    required DateTime month,
    required bool includeMonth,
  }) {
    final parts = <String>[
      if (merchantQuery != null) merchantQuery.trim(),
      if (categoryId != null)
        'danh mục ${categoryNames[categoryId] ?? categoryId}',
      if (amountBounds != null) _amountLabel(amountBounds),
      if (includeMonth) MonthUtils.label(month),
    ];
    return parts.isEmpty ? 'bộ lọc đã chọn' : parts.join(' · ');
  }

  String _amountLabel((int?, int?) bounds) {
    final min = bounds.$1;
    final max = bounds.$2;
    if (min != null && max != null) {
      return '${MoneyFormatter.format(min)} đến ${MoneyFormatter.format(max)}';
    }
    if (min != null) return 'từ ${MoneyFormatter.format(min)}';
    return 'dưới ${MoneyFormatter.format(max ?? 0)}';
  }

  bool _isBudgetQuestion(String value) =>
      value.contains('ngan sach') ||
      value.contains('budget') ||
      value.contains('han muc');

  bool _isIncomeQuestion(String value) => RegExp(
    r'\b(thu nhap|khoan thu|tong thu|da thu|tien thu|nguon thu|nhan duoc|luong|tien thuong|income|thu)\b',
  ).hasMatch(value);

  bool _isCashflowBalanceQuestion(String value) =>
      value.contains('chenh lech') &&
      value.contains('thu') &&
      value.contains('chi');

  bool _isRecurringQuestion(String value) =>
      value.contains('dinh ky') ||
      value.contains('lap lai') ||
      value.contains('hang thang');

  bool _isForecastQuestion(String value) =>
      value.contains('du bao') ||
      value.contains('cuoi thang') ||
      value.contains('du kien');

  bool _isAnomalyQuestion(String value) =>
      value.contains('bat thuong') ||
      value.contains('tang dot bien') ||
      value.contains('khoan nao cao');

  bool _isCategoryQuestion(String value) =>
      value.contains('danh muc') ||
      value.contains('an uong') ||
      value.contains('mua sam');

  bool _isRankingQuestion(String value) =>
      value.contains('nhieu nhat') ||
      value.contains('lon nhat') ||
      value.contains('top');

  bool _isComparisonQuestion(String value) =>
      value.contains('so sanh') ||
      value.contains('thang truoc') ||
      value.contains('tang') ||
      value.contains('giam');

  bool _isRecentInvoiceQuestion(String value) =>
      value.contains('hoa don') &&
      (value.contains('gan day') ||
          value.contains('moi nhat') ||
          value.contains('danh sach') ||
          value.contains('liet ke'));

  String? _merchantQuery(String value) {
    final normalized = _normalize(value);
    final hasInvoiceSearch =
        normalized.contains('hoa don') &&
        (normalized.contains('tim ') ||
            normalized.contains('loc ') ||
            normalized.contains('hoa don cua'));
    final hasSpendingSearch = RegExp(
      r'(chi|mua|giao dich)\s+(tai|o|cho)\s+',
    ).hasMatch(normalized);
    if (!hasInvoiceSearch && !hasSpendingSearch) {
      return null;
    }
    var query = value;
    if (hasInvoiceSearch) {
      query = query.replaceFirst(
        RegExp(
          r'.*?(?:tìm|tim|lọc|loc)\s+hóa đơn(?:\s+của|\s+cua)?\s*',
          caseSensitive: false,
        ),
        '',
      );
      query = query.replaceFirst(
        RegExp(r'.*?hóa đơn\s+của\s*', caseSensitive: false),
        '',
      );
    } else {
      query = query.replaceFirst(
        RegExp(
          r'.*?(?:chi|mua|giao dịch)\s+(?:tại|tai|ở|o|cho)\s+',
          caseSensitive: false,
        ),
        '',
      );
    }
    query = query.replaceFirst(
      RegExp(
        r'\s+(trong|tháng|thang|trên|tren|dưới|duoi|từ|tu)(?:\s|$).*',
        caseSensitive: false,
      ),
      '',
    );
    query = query.trim();
    if (_normalize(query).contains('danh muc')) return null;
    if (RegExp(
      r'^(trên|tren|dưới|duoi|từ|tu|gần đây|gan day|mới nhất|moi nhat|danh sách|danh sach|liệt kê|liet ke)\b',
      caseSensitive: false,
    ).hasMatch(query)) {
      return null;
    }
    return query.length >= 2 ? query : null;
  }

  String? _categoryQuery(String normalized, Map<String, String> categoryNames) {
    if (!normalized.contains('hoa don') || !normalized.contains('danh muc')) {
      return null;
    }
    for (final entry in categoryNames.entries) {
      final category = _normalize(entry.value);
      if (category.isNotEmpty && normalized.contains(category)) {
        return entry.key;
      }
    }
    return null;
  }

  (int?, int?)? _amountBounds(String value) {
    final normalized = _normalize(value);
    if (!normalized.contains('hoa don')) return null;
    final range = RegExp(
      r'tu\s+([0-9][0-9\s.,]*)(?:\s*(trieu|m))?\s+den\s+([0-9][0-9\s.,]*)(?:\s*(trieu|m))?',
    ).firstMatch(normalized);
    if (range != null) {
      final min = _parseAmount(range.group(1), range.group(2));
      final max = _parseAmount(range.group(3), range.group(4));
      if (min != null && max != null) return (min, max);
    }
    final single = RegExp(
      r'(tren|duoi)\s+([0-9][0-9\s.,]*)(?:\s*(trieu|m))?',
    ).firstMatch(normalized);
    if (single == null) return null;
    final amount = _parseAmount(single.group(2), single.group(3));
    if (amount == null) return null;
    return single.group(1) == 'tren' ? (amount, null) : (null, amount);
  }

  int? _parseAmount(String? raw, String? unit) {
    if (raw == null) return null;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final amount = int.tryParse(digits);
    if (amount == null || amount <= 0) return null;
    return switch (unit) {
      'trieu' || 'm' => amount * 1000000,
      _ => amount,
    };
  }

  bool _isTotalQuestion(String value) =>
      value.contains('tong') ||
      value.contains('bao nhieu') ||
      value.contains('chi tieu');

  DateTime _monthFromQuestion(String value, DateTime reference) {
    if (value.contains('thang truoc')) return MonthUtils.shift(reference, -1);
    if (value.contains('thang sau')) return MonthUtils.shift(reference, 1);
    final match = RegExp(
      r'thang\s+(\d{1,2})(?:\s*[/-]\s*(\d{4}))?',
    ).firstMatch(value);
    if (match == null) return MonthUtils.normalize(reference);
    final month = int.parse(match.group(1)!);
    final year = int.tryParse(match.group(2) ?? '') ?? reference.year;
    if (month < 1 || month > 12) return MonthUtils.normalize(reference);
    return DateTime(year, month);
  }

  String _normalize(String value) {
    var result = value.toLowerCase();
    const replacements = {
      'à': 'a',
      'á': 'a',
      'ạ': 'a',
      'ả': 'a',
      'ã': 'a',
      'ă': 'a',
      'ằ': 'a',
      'ắ': 'a',
      'ặ': 'a',
      'ẳ': 'a',
      'ẵ': 'a',
      'â': 'a',
      'ầ': 'a',
      'ấ': 'a',
      'ậ': 'a',
      'ẩ': 'a',
      'ẫ': 'a',
      'đ': 'd',
      'è': 'e',
      'é': 'e',
      'ẹ': 'e',
      'ẻ': 'e',
      'ẽ': 'e',
      'ê': 'e',
      'ề': 'e',
      'ế': 'e',
      'ệ': 'e',
      'ể': 'e',
      'ễ': 'e',
      'ì': 'i',
      'í': 'i',
      'ị': 'i',
      'ỉ': 'i',
      'ĩ': 'i',
      'ò': 'o',
      'ó': 'o',
      'ọ': 'o',
      'ỏ': 'o',
      'õ': 'o',
      'ô': 'o',
      'ồ': 'o',
      'ố': 'o',
      'ộ': 'o',
      'ổ': 'o',
      'ỗ': 'o',
      'ơ': 'o',
      'ờ': 'o',
      'ớ': 'o',
      'ợ': 'o',
      'ở': 'o',
      'ỡ': 'o',
      'ù': 'u',
      'ú': 'u',
      'ụ': 'u',
      'ủ': 'u',
      'ũ': 'u',
      'ư': 'u',
      'ừ': 'u',
      'ứ': 'u',
      'ự': 'u',
      'ử': 'u',
      'ữ': 'u',
      'ỳ': 'y',
      'ý': 'y',
      'ỵ': 'y',
      'ỷ': 'y',
      'ỹ': 'y',
    };
    for (final entry in replacements.entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }
}
