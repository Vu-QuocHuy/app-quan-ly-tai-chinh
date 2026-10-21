import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/features/groups/domain/external_bill.dart';

Map<String, dynamic> _json() => {
  'id': '6f1c2b8e-4a1d-4c3e-9b2a-1d2e3f4a5b6c',
  'description': 'Ăn tối',
  'total_minor': 600000,
  'created_at': '2026-10-21T12:00:00+00:00',
  'payer_name': 'Huy',
  'is_open': true,
  'my_amount_minor': 200000,
  'my_settled_at': null,
  'participants': [
    {'name': 'Huy', 'amount_minor': 200000, 'settled': false, 'is_me': false},
    {'name': 'Lan', 'amount_minor': 200000, 'settled': true, 'is_me': false},
    {'name': 'Dũng', 'amount_minor': 200000, 'settled': false, 'is_me': true},
  ],
};

void main() {
  test('đọc đủ trường của list_my_external_bills', () {
    final bill = ExternalBill.fromJson(_json());

    expect(bill.id, '6f1c2b8e-4a1d-4c3e-9b2a-1d2e3f4a5b6c');
    expect(bill.description, 'Ăn tối');
    expect(bill.totalMinor, 600000);
    expect(bill.createdAt, DateTime.utc(2026, 10, 21, 12).toLocal());
    expect(bill.payerName, 'Huy');
    expect(bill.isOpen, isTrue);
    expect(bill.myAmountMinor, 200000);
    expect(bill.mySettledAt, isNull);
    expect(bill.isMineSettled, isFalse);
    expect(bill.hasSettlement, isTrue);
    expect(bill.participants.map((item) => item.name), ['Huy', 'Lan', 'Dũng']);
    expect(bill.participants.last.isMe, isTrue);
    expect(bill.participants[1].settled, isTrue);
  });

  test('my_settled_at có giá trị thì bill đã được mình thanh toán', () {
    final json = _json()..['my_settled_at'] = '2026-10-21T13:00:00+00:00';

    expect(ExternalBill.fromJson(json).isMineSettled, isTrue);
  });

  test('thiếu trường bắt buộc thì FormatException', () {
    for (final key in [
      'id',
      'description',
      'total_minor',
      'created_at',
      'payer_name',
      'is_open',
      'my_amount_minor',
      'participants',
    ]) {
      final json = _json()..remove(key);
      expect(
        () => ExternalBill.fromJson(json),
        throwsFormatException,
        reason: key,
      );
    }
  });

  test('người tham gia thiếu tên hoặc số tiền âm thì FormatException', () {
    final missingName = _json()
      ..['participants'] = [
        {'amount_minor': 1, 'settled': false, 'is_me': false},
      ];
    final negative = _json()
      ..['participants'] = [
        {'name': 'Lan', 'amount_minor': -1, 'settled': false, 'is_me': false},
      ];

    expect(() => ExternalBill.fromJson(missingName), throwsFormatException);
    expect(() => ExternalBill.fromJson(negative), throwsFormatException);
  });

  test('dữ liệu không phải object thì FormatException', () {
    expect(() => ExternalBill.fromJson('bill'), throwsFormatException);
  });
}
