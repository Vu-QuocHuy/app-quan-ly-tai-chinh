import 'chat_models.dart';

abstract final class ChatPrivacyPolicy {
  static const _publicFactKeys = {
    'period',
    'invoice_count',
    'total_minor_vnd',
    'previous_total_minor_vnd',
    'budget_count',
    'budget_limit_minor_vnd',
    'forecast_total_minor_vnd',
    'recurring_count',
    'anomaly_count',
  };
  static const _numericFactKeys = {
    'invoice_count',
    'total_minor_vnd',
    'previous_total_minor_vnd',
    'budget_count',
    'budget_limit_minor_vnd',
    'forecast_total_minor_vnd',
    'recurring_count',
    'anomaly_count',
  };

  static const outOfScopeMessage =
      'Mình chỉ hỗ trợ câu hỏi về dữ liệu tài chính của bạn trong ứng dụng, '
      'như chi tiêu, hóa đơn và ngân sách.';

  static const _financeTopics = [
    'chi tieu',
    'chi phi',
    'tong chi',
    'khoan chi',
    'da chi',
    'chi bao nhieu',
    'chi thang',
    'chi nhieu nhat',
    'chi vao dau',
    'tieu bao nhieu',
    'tieu nhieu nhat',
    'tieu vao dau',
    'hoa don',
    'bien lai',
    'giao dich',
    'ngan sach',
    'han muc',
    'danh muc',
    'an uong',
    'mua sam',
    'dinh ky',
    'lap lai',
    'du bao',
    'du kien',
    'bat thuong',
    'tiet kiem',
    'muc tieu',
    'so du',
    'dong tien',
    'con bao nhieu tien',
  ];

  static const _blockedTopics = [
    'prompt',
    'instruction',
    'instructions',
    'chi dan',
    'chi dan he thong',
    'developer',
    'cau hinh',
    'config',
    'settings',
    'configuration',
    'environment',
    'bien moi truong',
    'env',
    'api key',
    'khoa api',
    'secret',
    'bi mat',
    'token',
    'mat khau',
    'ma nguon',
    'source code',
    'database',
    'schema',
    'sql',
    'debug',
    'credentials',
    'thong tin noi bo',
    'bo qua chi dan',
    'bo qua quy tac',
    'ignore previous',
    'ignore all instructions',
    'jailbreak',
    'nguoi khac',
    'nguoi dung khac',
    'cua nguoi khac',
    'tai khoan khac',
    'tai khoan cua nguoi khac',
    'user khac',
    'other user',
    'another user',
    'other account',
    'all users',
    'tat ca nguoi dung',
    'tat ca tai khoan',
    'cua ban',
    'chong toi',
    'vo toi',
    'chong cua toi',
    'vo cua toi',
    'ban toi',
    'ban cua toi',
    'me toi',
    'bo toi',
    'me cua toi',
    'bo cua toi',
    'cua con toi',
    'cho con toi',
    'anh cua toi',
    'chi cua toi',
    'em cua toi',
    'my husband',
    'my wife',
    'my friend',
    'my mother',
    'my father',
    'my son',
    'my daughter',
    'my brother',
    'my sister',
  ];

  static bool isPersonalFinanceQuestion(String value) {
    final question = ' ${_normalizeQuestion(value)} ';
    if (_blockedTopics.any((topic) => question.contains(' $topic '))) {
      return false;
    }
    return _financeTopics.any((topic) => question.contains(' $topic '));
  }

  static List<ChatFact> factsForExternal(Iterable<ChatFact> facts) {
    return facts
        .where((fact) => _publicFactKeys.contains(fact.key))
        .where(_hasSafeValue)
        .map((fact) => ChatFact(fact.key, _clean(fact.value, 500)))
        .take(20)
        .toList(growable: false);
  }

  static List<ChatMessage> historyForExternal(Iterable<ChatMessage> history) {
    return history
        .where((message) => message.role == ChatMessageRole.user)
        .toList(growable: false)
        .reversed
        .take(4)
        .toList()
        .reversed
        .map(
          (message) => ChatMessage(
            id: '',
            role: message.role,
            text: redactPersonalData(message.text),
            createdAt: message.createdAt,
          ),
        )
        .toList(growable: false);
  }

  static String redactPersonalData(String value) {
    return value
        .replaceAll(RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'), '[email đã ẩn]')
        .replaceAll(
          RegExp(r'(?<!\d)(?:\+?84|0)\d{8,10}(?!\d)'),
          '[số điện thoại đã ẩn]',
        )
        .replaceAll(RegExp(r'(?<!\d)\d{10,14}(?!\d)'), '[mã số đã ẩn]');
  }

  static String _normalizeQuestion(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp('[àáạảãâầấậẩẫăằắặẳẵ]'), 'a')
        .replaceAll(RegExp('[èéẹẻẽêềếệểễ]'), 'e')
        .replaceAll(RegExp('[ìíịỉĩ]'), 'i')
        .replaceAll(RegExp('[òóọỏõôồốộổỗơờớợởỡ]'), 'o')
        .replaceAll(RegExp('[ùúụủũưừứựửữ]'), 'u')
        .replaceAll(RegExp('[ỳýỵỷỹ]'), 'y')
        .replaceAll('đ', 'd')
        .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
        .replaceAll(RegExp('[^a-z0-9]+'), ' ')
        .trim();
  }

  static bool _hasSafeValue(ChatFact fact) {
    final value = fact.value.trim();
    return fact.key == 'period'
        ? RegExp(r'^Tháng \d{1,2}/\d{4}$').hasMatch(value)
        : _numericFactKeys.contains(fact.key) &&
              RegExp(r'^\d{1,20}$').hasMatch(value);
  }

  static String _clean(String value, int maxLength) {
    final singleLine = value.replaceAll(RegExp(r'[\u0000-\u001F]'), ' ').trim();
    return singleLine.length <= maxLength
        ? singleLine
        : '${singleLine.substring(0, maxLength)}…';
  }
}
