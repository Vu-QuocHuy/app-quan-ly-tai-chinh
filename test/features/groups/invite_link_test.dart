import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/groups/domain/invite_link.dart';

String? _groupCode(String raw) => switch (InviteLink.parse(raw)) {
  GroupInviteLink(:final code) => code,
  null => null,
};

void main() {
  test('đọc mã từ URI mời nhóm', () {
    expect(_groupCode('hoadoninsight://join-group?code=ABCD1234'), 'ABCD1234');
  });

  test('chấp nhận mã trơn, chữ thường và khoảng trắng', () {
    expect(_groupCode('  abcd1234 \n'), 'ABCD1234');
    expect(_groupCode('hoadoninsight://join-group?code=abcd1234'), 'ABCD1234');
  });

  test('từ chối scheme hoặc host lạ', () {
    expect(_groupCode('https://join-group?code=ABCD1234'), isNull);
    expect(_groupCode('hoadoninsight://payment-return?code=ABCD1234'), isNull);
    expect(_groupCode('hoadoninsight://join-group'), isNull);
  });

  test('từ chối mã sai độ dài hoặc ký tự', () {
    expect(_groupCode('ABCD123'), isNull);
    expect(_groupCode('ABCD12345'), isNull);
    expect(_groupCode('ABCD123G'), isNull);
    expect(_groupCode(''), isNull);
  });

  test('từ chối payload VietQR', () {
    expect(
      _groupCode(
        '00020101021138570010A000000727012700069704220113VQRQ00000000020208QRIBFTTA53037045802VN6304ABCD',
      ),
      isNull,
    );
  });

  test('groupUri rồi parse cho lại đúng mã', () {
    final uri = InviteLink.groupUri('ABCD1234');
    expect(uri, 'hoadoninsight://join-group?code=ABCD1234');
    expect(_groupCode(uri), 'ABCD1234');
  });
}
