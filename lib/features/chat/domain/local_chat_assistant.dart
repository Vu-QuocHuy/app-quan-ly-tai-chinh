import '../../../core/utils/money_formatter.dart';
import '../../../core/utils/month_utils.dart';
import '../../invoices/domain/invoice_filters.dart';
import '../../invoices/domain/invoice_models.dart';
import '../../invoices/domain/invoice_repository.dart';
import 'chat_models.dart';
import 'local_chat_tools.dart';

class LocalChatAssistant {
  const LocalChatAssistant(this._repository);

  final InvoiceRepository _repository;

  Future<ChatReply> answer(String question, {DateTime? now}) async {
    final tools = LocalChatTools(_repository);
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
        facts: _insightFacts(insights),
      );
    }
    if (_isForecastQuestion(normalized)) {
      final insights = await tools.spendingInsights(monthKey);
      return ChatReply(
        text:
            'Dự báo tổng chi ${MonthUtils.label(month)} là '
            '${MoneyFormatter.format(insights.forecastTotalMinor)} '
            '(đã ghi nhận ${MoneyFormatter.format(insights.currentTotalMinor)}).',
        citations: [citation],
        facts: _insightFacts(insights),
      );
    }
    if (_isAnomalyQuestion(normalized)) {
      final insights = await tools.spendingInsights(monthKey);
      return ChatReply(
        text: _anomalyAnswer(insights),
        citations: _anomalyCitations(citation, insights.anomalies),
        facts: _insightFacts(insights),
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
        facts: _summaryFacts(dashboard),
      );
    }
    if (_isComparisonQuestion(normalized)) {
      final dashboard = await tools.monthSummary(monthKey);
      return ChatReply(
        text: _comparisonAnswer(dashboard, month),
        citations: [citation],
        facts: _summaryFacts(dashboard),
      );
    }
    if (_isRecentInvoiceQuestion(normalized)) {
      final recentInvoices = await tools.recentTransactions();
      return ChatReply(
        text: _recentInvoiceAnswer(recentInvoices.items),
        citations: _invoiceCitations(citation, recentInvoices.items),
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
      );
    }
    if (_isTotalQuestion(normalized)) {
      final dashboard = await tools.monthSummary(monthKey);
      return ChatReply(
        text:
            '${MonthUtils.label(month)} bạn đã ghi nhận '
            '${dashboard.invoiceCount} hóa đơn, tổng chi '
            '${MoneyFormatter.format(dashboard.totalMinor)}.',
        citations: [citation],
        facts: _summaryFacts(dashboard),
      );
    }

    return ChatReply(
      text:
          'Mình có thể trả lời về tổng chi, ngân sách, danh mục, so sánh '
          'tháng, dự báo và khoản chi định kỳ. Bạn có thể hỏi cụ thể hơn.',
      citations: const [],
    );
  }

  List<ChatFact> _summaryFacts(DashboardSnapshot dashboard) {
    return [
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
      ChatFact('period', MonthUtils.label(month)),
      ..._summaryFacts(dashboard),
      ChatFact('budget_count', '${budgets.length}'),
      ChatFact('budget_limit_minor_vnd', '${dashboard.budgetLimitMinor}'),
    ];
  }

  List<ChatFact> _insightFacts(SpendingInsights insights) {
    return [
      ChatFact('forecast_total_minor_vnd', '${insights.forecastTotalMinor}'),
      ChatFact('recurring_count', '${insights.recurringExpenses.length}'),
      ChatFact('anomaly_count', '${insights.anomalies.length}'),
    ];
  }

  String _budgetAnswer(
    DashboardSnapshot dashboard,
    List<BudgetEntity> budgets,
    DateTime month,
  ) {
    if (budgets.isEmpty || dashboard.budgetLimitMinor <= 0) {
      return '${MonthUtils.label(month)} chưa có ngân sách được đặt.';
    }
    final progress = (dashboard.budgetProgress * 100).toStringAsFixed(1);
    return '${MonthUtils.label(month)} đã chi '
        '${MoneyFormatter.format(dashboard.totalMinor)} trên '
        '${MoneyFormatter.format(dashboard.budgetLimitMinor)} '
        '($progress%). ${budgets.length} danh mục có hạn mức.';
  }

  String _recurringAnswer(SpendingInsights insights) {
    if (insights.recurringExpenses.isEmpty) {
      return 'Chưa đủ dữ liệu để nhận diện khoản chi định kỳ ổn định.';
    }
    final top = insights.recurringExpenses
        .take(3)
        .map((item) {
          return '${item.merchant} (${item.cadenceLabel}, '
              'trung bình ${MoneyFormatter.format(item.averageMinor)})';
        })
        .join('; ');
    return 'Các khoản chi định kỳ nổi bật: $top.';
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
      return '${MonthUtils.label(month)} chưa có dữ liệu danh mục.';
    }
    final visible = ranking ? totals.take(3) : totals.take(1);
    final result = visible
        .map((entry) {
          return '${categoryNames[entry.key] ?? entry.key}: '
              '${MoneyFormatter.format(entry.value)}';
        })
        .join('; ');
    return ranking
        ? 'Các danh mục chi nhiều nhất ${MonthUtils.label(month)}: $result.'
        : 'Danh mục chi nhiều nhất ${MonthUtils.label(month)} là $result.';
  }

  String _comparisonAnswer(DashboardSnapshot dashboard, DateTime month) {
    final previous = dashboard.previousMonthTotalMinor;
    if (previous <= 0) {
      return 'Chưa có dữ liệu tháng trước để so sánh với ${MonthUtils.label(month)}.';
    }
    final difference = dashboard.totalMinor - previous;
    final percent = (difference.abs() / previous * 100).toStringAsFixed(1);
    final direction = difference == 0
        ? 'không thay đổi'
        : difference > 0
        ? 'tăng $percent%'
        : 'giảm $percent%';
    return 'Chi tiêu ${MonthUtils.label(month)} '
        '${MoneyFormatter.format(dashboard.totalMinor)}, $direction '
        'so với tháng trước (${MoneyFormatter.format(previous)}).';
  }

  String _recentInvoiceAnswer(List<InvoiceEntity> invoices) {
    if (invoices.isEmpty) return 'Chưa có hóa đơn nào được lưu trên thiết bị.';
    final visible = invoices
        .take(5)
        .map((invoice) {
          final number = invoice.invoiceNumber == null
              ? ''
              : ' · Số ${invoice.invoiceNumber}';
          return '${invoice.sellerName}$number: '
              '${MoneyFormatter.format(invoice.totalMinor)}';
        })
        .join('; ');
    return 'Các hóa đơn gần đây: $visible.';
  }

  String _anomalyAnswer(SpendingInsights insights) {
    if (insights.anomalies.isEmpty) {
      return 'Chưa phát hiện khoản chi nào cao bất thường so với lịch sử đã lưu.';
    }
    final visible = insights.anomalies
        .take(3)
        .map((item) {
          return '${item.merchant}: ${MoneyFormatter.format(item.amountMinor)} '
              '(${item.explanation})';
        })
        .join('; ');
    return 'Các khoản chi cần kiểm tra: $visible.';
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
    final number = invoice.invoiceNumber == null
        ? ''
        : ' · Số ${invoice.invoiceNumber}';
    return 'Mở ${invoice.sellerName}$number · '
        '${MoneyFormatter.format(invoice.totalMinor)}';
  }

  String _searchAnswer(List<InvoiceEntity> invoices, String query) {
    if (invoices.isEmpty) return 'Không tìm thấy hóa đơn phù hợp với “$query”.';
    final visible = invoices
        .take(5)
        .map((invoice) {
          return '${invoice.sellerName}: ${MoneyFormatter.format(invoice.totalMinor)}';
        })
        .join('; ');
    return 'Tìm thấy ${invoices.length} hóa đơn phù hợp với “$query”: $visible.';
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
