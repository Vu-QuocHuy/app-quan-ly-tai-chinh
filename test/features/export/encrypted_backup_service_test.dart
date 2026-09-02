import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:hoadon_insight/features/export/application/encrypted_backup_service.dart';

void main() {
  const service = EncryptedBackupService();

  test('mã hóa và giải mã lại đúng nội dung, không lộ plaintext', () async {
    const plaintext = '{"sellerName":"Nha hang Bao Mat","totalMinor":123456}';

    final encrypted = await service.encrypt(plaintext, 'mat-khau-an-toan');

    expect(encrypted, isNot(contains('Nha hang Bao Mat')));
    expect(EncryptedBackupService.isEncrypted(encrypted), isTrue);
    expect(await service.decrypt(encrypted, 'mat-khau-an-toan'), plaintext);
  });

  test('từ chối mật khẩu sai', () async {
    final encrypted = await service.encrypt('invoice-data', 'mat-khau-dung');

    expect(
      () => service.decrypt(encrypted, 'mat-khau-sai'),
      throwsA(isA<FormatException>()),
    );
  });

  test('từ chối envelope bị thay đổi dù chưa cần giải mã', () async {
    final encrypted = await service.encrypt('invoice-data', 'mat-khau-dung');
    final envelope = jsonDecode(encrypted) as Map<String, dynamic>;
    envelope['cipherText'] = base64Encode(utf8.encode('tampered'));

    expect(
      () => service.decrypt(jsonEncode(envelope), 'mat-khau-dung'),
      throwsA(isA<FormatException>()),
    );
  });
}
