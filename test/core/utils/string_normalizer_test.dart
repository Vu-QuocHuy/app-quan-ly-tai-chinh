import 'package:flutter_test/flutter_test.dart';

import 'package:hoadon_insight/core/utils/string_normalizer.dart';

void main() {
  test(
    'normalizes Vietnamese merchant names consistently with and without dấu',
    () {
      expect(StringNormalizer.merchant('Cửa hàng Ánh Đèn'), 'cua hang anh den');
      expect(
        StringNormalizer.merchant('  CUA-HANG   ANH DEN  '),
        'cua hang anh den',
      );
    },
  );
}
