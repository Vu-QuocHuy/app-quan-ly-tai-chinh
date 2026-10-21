import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/groups/domain/invite_link.dart';

String? _groupCode(String raw) => switch (InviteLink.parse(raw)) {
  GroupInviteLink(:final code) => code,
  BillInviteLink() || null => null,
};

String? _billCode(String raw) => switch (InviteLink.parse(raw)) {
  BillInviteLink(:final code) => code,
  GroupInviteLink() || null => null,
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

  test('đọc mã từ URI mời vào bill', () {
    expect(
      _billCode('hoadoninsight://join-bill?code=ABCDEF1234'),
      'ABCDEF1234',
    );
    expect(
      _billCode('hoadoninsight://join-bill?code=abcdef1234'),
      'ABCDEF1234',
    );
  });

  test('mã trơn 10 ký tự là mã bill, không phải mã nhóm', () {
    expect(_billCode('  abcdef1234 \n'), 'ABCDEF1234');
    expect(_groupCode('ABCDEF1234'), isNull);
  });

  test('mã bill 9 hoặc 11 ký tự bị từ chối', () {
    expect(InviteLink.parse('ABCDEF123'), isNull);
    expect(InviteLink.parse('ABCDEF12345'), isNull);
    expect(_billCode('hoadoninsight://join-bill?code=ABCD1234'), isNull);
    expect(_billCode('hoadoninsight://join-bill?code=ABCDEF12345'), isNull);
    expect(_billCode('hoadoninsight://join-bill?code=ABCDEF123G'), isNull);
  });

  test('URI nhóm vẫn ra GroupInviteLink', () {
    expect(
      InviteLink.parse('hoadoninsight://join-group?code=ABCD1234'),
      isA<GroupInviteLink>(),
    );
    expect(_groupCode('hoadoninsight://join-group?code=ABCDEF1234'), isNull);
  });

  test('billUri rồi parse cho lại đúng mã', () {
    final uri = InviteLink.billUri('ABCDEF1234');
    expect(uri, 'hoadoninsight://join-bill?code=ABCDEF1234');
    expect(_billCode(uri), 'ABCDEF1234');
  });
}
