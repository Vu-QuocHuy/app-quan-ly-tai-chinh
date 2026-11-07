import 'chat_models.dart';

/// Standard lookups that [LocalChatAssistant] (or the local debt reader) can
/// answer exactly from on-device SQLite, without any LLM call (H3).
enum LocalChatIntent {
  expenseTotal,
  incomeTotal,
  budget,
  debt,
  topCategory,
  comparison,
  forecast,
  recurring,
  anomaly,
  recentInvoices,
  scenario,
}

/// Deterministic, client-side routing rules for the chatbot.
///
/// Every rule is deliberately conservative: when in doubt the caller falls
/// back to the previous (LLM) path, so a write command is never answered as a
/// question and an analytical question is never answered with a canned number.
abstract final class ChatRoutingRules {
  /// Tools the `chat` action accepts (mirrors `answerChat` on the server).
  static const supportedTools = {
    'get_cashflow_summary',
    'get_expense_summary',
    'get_income_summary',
    'get_budget_status',
    'get_spending_insights',
    'get_recent_invoices',
    'get_debt_summary',
    'get_recurring_schedules',
    'get_group_summary',
  };

  // Questions that need reasoning/explanation rather than a lookup.
  static const _analyticMarkers = [
    ' tai sao ',
    ' vi sao ',
    ' goi y ',
    ' tu van ',
    ' phan tich ',
    ' danh gia ',
    ' lam sao ',
    ' lam the nao ',
    ' the nao ',
    ' cach ',
    ' meo ',
    ' ke hoach ',
    ' giai thich ',
    ' nen ',
    ' khuyen ',
    ' y kien ',
    ' thang nao ',
    ' ngay nao ',
    ' khi nao ',
    ' chenh lech ',
    ' va ',
    ' why ',
    ' how can ',
    ' should ',
    ' advice ',
  ];

  // Anything that may ask the assistant to change data.
  static const _writeMarkers = [
    ' ghi ',
    ' them ',
    ' tao ',
    ' luu ',
    ' xoa ',
    ' sua ',
    ' cap nhat ',
    ' dat ngan sach ',
    ' dat han muc ',
    ' dat lich ',
    ' nhac toi ',
    ' cho vay ',
    ' tra no ',
    ' gop ',
    ' chuyen ',
    ' huy ',
    ' nhap ',
    ' thanh toan ',
    ' dong tien ',
    ' nop ',
    ' hoan tien ',
    ' tra lai ',
    ' add ',
    ' record ',
    ' log ',
    ' create ',
    ' save ',
    ' delete ',
    ' remove ',
    ' update ',
    ' set ',
    ' paid ',
    ' spent ',
    ' bought ',
    ' lent ',
    ' borrowed ',
    ' cancel ',
  ];

  static const _questionMarkers = [
    ' bao nhieu ',
    ' nhieu nhat ',
    ' it nhat ',
    ' lon nhat ',
    ' nao ',
    ' gi ',
    ' sao ',
    ' ai ',
    ' o dau ',
    ' liet ke ',
    ' xem ',
    ' cho toi biet ',
    ' tom tat ',
    ' tong ket ',
    ' so sanh ',
    ' du bao ',
    ' con lai ',
    ' how much ',
    ' how many ',
    ' what ',
    ' which ',
    ' who ',
    ' show ',
    ' list ',
  ];

  // Runs on normalized text ("500.000đ" → "500 000d"). Years such as
  // "tháng 8/2026" must not count as an amount, hence \d{5,} for bare numbers.
  static final _amountPattern = RegExp(
    r'\d+\s*(?:k|nghin|ngan|trieu|tr|dong|d|vnd)\b|\d{5,}|\b\d{1,3}(?: \d{3})+\b',
  );

  /// H2: `true` when [question] is a read-only question, so the
  /// `assistant_command` interpretation call can be skipped safely.
  static bool isReadOnlyQuestion(String question) {
    final padded = ' ${normalize(question)} ';
    if (padded.trim().isEmpty) return false;
    if (_writeMarkers.any(padded.contains)) return false;
    if (_amountPattern.hasMatch(padded)) return false;
    final endsAsQuestion =
        question.trim().endsWith('?') ||
        RegExp(r' (khong|chua|ha|a|nhi) $').hasMatch(padded);
    return endsAsQuestion || _questionMarkers.any(padded.contains);
  }

  /// H3: the local intent for a standard lookup, or `null` when the question
  /// must go to the LLM. Vietnamese only — local answers are Vietnamese.
  static LocalChatIntent? localIntent(String question) {
    final normalized = normalize(question);
    if (normalized.isEmpty || normalized.length > 160) return null;
    final padded = ' $normalized ';

    final isScenario =
        padded.contains(' neu ') &&
        (padded.contains(' giam chi ') ||
            padded.contains(' tang thu ') ||
            padded.contains(' tiet kiem ')) &&
        RegExp(r'\d').hasMatch(padded);
    if (isScenario) return LocalChatIntent.scenario;

    if (_analyticMarkers.any(padded.contains)) return null;
    if (_writeMarkers.any(padded.contains)) return null;
    if (_amountPattern.hasMatch(padded)) return null;

    bool has(String phrase) => padded.contains(' $phrase ');
    final mentionsIncome = RegExp(
      r' (thu nhap|khoan thu|tong thu|da thu|tien thu|nguon thu|nhan duoc|luong|tien thuong|thu) ',
    ).hasMatch(padded);
    final mentionsExpense =
        has('chi') || has('chi tieu') || has('tieu') || has('tieu xai');
    final asksAmount =
        has('bao nhieu') || has('tong') || has('het') || has('tong cong');

    if (has('no') ||
        has('cong no') ||
        has('vay') ||
        has('khoan no') ||
        has('ai no')) {
      final debtQuestion =
          has('dang no') ||
          has('no ai') ||
          has('ai no') ||
          has('khoan no') ||
          has('cong no') ||
          has('con no') ||
          has('tong no') ||
          has('no bao nhieu');
      return debtQuestion ? LocalChatIntent.debt : null;
    }
    if (has('ngan sach') || has('han muc')) return LocalChatIntent.budget;
    if (has('dinh ky')) {
      // "lịch định kỳ"/"nhắc" means configured schedules → LLM + schedule tool.
      return has('lich') || has('nhac') ? null : LocalChatIntent.recurring;
    }
    if (has('du bao') || has('cuoi thang')) return LocalChatIntent.forecast;
    if (has('bat thuong')) return LocalChatIntent.anomaly;
    if (has('hoa don') && (has('gan day') || has('moi nhat'))) {
      return LocalChatIntent.recentInvoices;
    }
    if (mentionsIncome && mentionsExpense) return null;
    if (has('so sanh')) {
      return mentionsExpense ? LocalChatIntent.comparison : null;
    }
    if (has('danh muc') && (has('nhieu nhat') || has('lon nhat'))) {
      return mentionsIncome ? null : LocalChatIntent.topCategory;
    }
    if (mentionsIncome && asksAmount) return LocalChatIntent.incomeTotal;
    if (mentionsExpense && asksAmount) return LocalChatIntent.expenseTotal;
    return null;
  }

  /// H4: local read-only tools whose FACTS should be attached to the first
  /// `chat` call. Returns at most two tools; empty means "let the LLM choose".
  static List<ChatToolCall> guessTools(String question, {DateTime? now}) {
    final padded = ' ${normalize(question)} ';
    bool has(String phrase) => padded.contains(' $phrase ');
    final period = periodFor(question, now: now);
    final names = <String>[];
    void add(String name) {
      if (!names.contains(name)) names.add(name);
    }

    final mentionsIncome = RegExp(
      r' (thu nhap|khoan thu|tong thu|da thu|tien thu|nguon thu|nhan duoc|luong|tien thuong|thu|income|earn|earned|salary) ',
    ).hasMatch(padded);
    final mentionsExpense =
        has('chi') ||
        has('chi tieu') ||
        has('tieu') ||
        has('danh muc') ||
        has('mua sam') ||
        has('an uong') ||
        has('spend') ||
        has('spent') ||
        has('spending') ||
        has('expense') ||
        has('expenses');

    if (has('no') ||
        has('cong no') ||
        has('vay') ||
        has('debt') ||
        has('owe')) {
      add('get_debt_summary');
    }
    if ((has('lich') || has('nhac')) && (has('dinh ky') || has('hang thang'))) {
      add('get_recurring_schedules');
    }
    if (has('nhom') || has('quy nhom') || has('group')) {
      add('get_group_summary');
    }
    if (has('ngan sach') || has('han muc') || has('budget')) {
      add('get_budget_status');
    }
    if (has('dinh ky') ||
        has('bat thuong') ||
        has('du bao') ||
        has('lap lai') ||
        has('xu huong') ||
        has('forecast') ||
        has('recurring') ||
        has('unusual')) {
      add('get_spending_insights');
    }
    if ((has('hoa don') || has('invoice') || has('invoices')) &&
        (has('gan day') ||
            has('moi nhat') ||
            has('liet ke') ||
            has('recent'))) {
      add('get_recent_invoices');
    }
    if ((mentionsIncome && mentionsExpense) ||
        has('chenh lech') ||
        has('tiet kiem') ||
        has('dong tien') ||
        has('savings') ||
        has('cashflow')) {
      add('get_cashflow_summary');
    } else if (mentionsIncome) {
      add('get_income_summary');
    } else if (mentionsExpense) {
      add('get_expense_summary');
    }
    return [
      for (final name in names.take(2))
        ChatToolCall(name: name, period: period),
    ];
  }

  /// `current` or `YYYY-MM` derived from "tháng trước" / "tháng 8/2026".
  static String periodFor(String question, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final normalized = normalize(question);
    DateTime? month;
    if (normalized.contains('thang truoc') ||
        normalized.contains('last month')) {
      month = DateTime(reference.year, reference.month - 1);
    } else {
      final match = RegExp(
        r'thang\s+(\d{1,2})(?:\s+(\d{4}))?',
      ).firstMatch(normalized);
      final value = int.tryParse(match?.group(1) ?? '');
      if (value != null && value >= 1 && value <= 12) {
        final year = int.tryParse(match?.group(2) ?? '') ?? reference.year;
        month = DateTime(year, value);
      }
    }
    if (month == null) return 'current';
    if (month.year == reference.year && month.month == reference.month) {
      return 'current';
    }
    return '${month.year.toString().padLeft(4, '0')}-'
        '${month.month.toString().padLeft(2, '0')}';
  }

  /// Lower-case, diacritics removed, punctuation collapsed to single spaces.
  static String normalize(String value) {
    final buffer = StringBuffer();
    for (final rune in value.toLowerCase().runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_fold[char] ?? char);
    }
    return buffer.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }

  static final Map<String, String> _fold = () {
    const groups = {
      'a': 'àáạảãâầấậẩẫăằắặẳẵ',
      'e': 'èéẹẻẽêềếệểễ',
      'i': 'ìíịỉĩ',
      'o': 'òóọỏõôồốộổỗơờớợởỡ',
      'u': 'ùúụủũưừứựửữ',
      'y': 'ỳýỵỷỹ',
      'd': 'đ',
    };
    return {
      for (final entry in groups.entries)
        for (final char in entry.value.split('')) char: entry.key,
    };
  }();
}
