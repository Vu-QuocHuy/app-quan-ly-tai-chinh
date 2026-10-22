abstract final class ChatPrivacyPolicy {
  static const outOfScopeMessage =
      'Mình chỉ hỗ trợ câu hỏi về dữ liệu tài chính của bạn trong ứng dụng, '
      'như khoản thu, chi tiêu, hóa đơn và ngân sách.';

  static const _financeTopics = [
    'thu nhap',
    'thu bao nhieu',
    'thu duoc',
    'khoan thu',
    'tong thu',
    'da thu',
    'tien thu',
    'nguon thu',
    'nhan duoc',
    'luong',
    'tien thuong',
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
    'spend',
    'spent',
    'spending',
    'income',
    'earn',
    'earned',
    'earnings',
    'expense',
    'expenses',
    'budget',
    'budgets',
    'category',
    'categories',
    'invoice',
    'invoices',
    'bill',
    'bills',
    'transaction',
    'transactions',
    'forecast',
    'recurring',
    'unusual',
    'save',
    'saving',
    'savings',
    'balance',
    'cost',
    'money',
    'compare',
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
}
