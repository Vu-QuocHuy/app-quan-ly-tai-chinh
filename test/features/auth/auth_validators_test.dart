import 'package:flutter_test/flutter_test.dart';

import 'package:hoadon_insight/features/auth/domain/auth_validators.dart';

void main() {
  test('accepts normal email addresses containing digits', () {
    expect(AuthValidators.email('test123@gmail.com'), isNull);
    expect(AuthValidators.email(' user.name+tag@example.co.uk '), isNull);
  });

  test('rejects malformed email addresses before calling Supabase', () {
    for (final value in [
      '',
      'test@',
      '@gmail.com',
      'test@gmail',
      'test..name@gmail.com',
      'test name@gmail.com',
      'test@gmail..com',
    ]) {
      expect(AuthValidators.email(value), isNotNull, reason: value);
    }
  });
}
