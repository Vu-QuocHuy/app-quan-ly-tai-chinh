import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

/// Encrypts the versioned invoice export without persisting the user's
/// password or the derived key.
///
/// The envelope intentionally keeps only non-secret parameters in JSON. The
/// invoice export remains inside AES-GCM ciphertext, while the outer checksum
/// lets us report a damaged file before doing the more expensive KDF step.
class EncryptedBackupService {
  const EncryptedBackupService();

  static const format = 'hoadon-insight.encrypted-backup';
  static const version = 1;
  static const kdfName = 'PBKDF2-HMAC-SHA256';
  static const pbkdf2Iterations = 100000;
  static const _minimumPasswordLength = 8;
  static const _saltLength = 16;

  Future<String> encrypt(String plaintext, String password) async {
    _validatePassword(password);
    if (plaintext.isEmpty) {
      throw ArgumentError.value(plaintext, 'plaintext', 'Không được để trống.');
    }

    final salt = _randomBytes(_saltLength);
    final cipher = AesGcm.with256bits();
    final nonce = cipher.newNonce();
    final key = await _deriveKey(password, salt, pbkdf2Iterations);
    final secretBox = await cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
      aad: utf8.encode(_aad),
    );

    final envelope = <String, Object?>{
      'format': format,
      'version': version,
      'kdf': kdfName,
      'iterations': pbkdf2Iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(secretBox.nonce),
      'cipherText': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    };
    envelope['checksumSha256'] = _checksum(envelope);
    return jsonEncode(envelope);
  }

  Future<String> decrypt(String content, String password) async {
    _validatePassword(password);

    final decoded = _decodeEnvelope(content);
    _verifyEnvelopeChecksum(decoded);
    if (decoded['format'] != format || decoded['version'] != version) {
      throw const FormatException('Không đúng định dạng backup mã hóa.');
    }
    if (decoded['kdf'] != kdfName) {
      throw const FormatException(
        'Thuật toán dẫn xuất khóa không được hỗ trợ.',
      );
    }

    final iterations = decoded['iterations'];
    if (iterations is! int || iterations < 10000 || iterations > 500000) {
      throw const FormatException('Thông số KDF của backup không hợp lệ.');
    }
    final salt = _decodeBase64(decoded, 'salt', expectedLength: _saltLength);
    final nonce = _decodeBase64(decoded, 'nonce', expectedLength: 12);
    final cipherText = _decodeBase64(decoded, 'cipherText');
    final mac = _decodeBase64(decoded, 'mac', expectedLength: 16);

    try {
      final key = await _deriveKey(password, salt, iterations);
      final clearText = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
        aad: utf8.encode(_aad),
      );
      return utf8.decode(clearText);
    } on SecretBoxAuthenticationError {
      throw const FormatException(
        'Mật khẩu không đúng hoặc backup đã bị thay đổi.',
      );
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException(
        'Không thể giải mã backup. Mật khẩu có thể không đúng.',
      );
    }
  }

  static bool isEncrypted(String content) {
    try {
      final decoded = jsonDecode(content);
      return decoded is Map && decoded['format'] == format;
    } on Object {
      return false;
    }
  }

  static String get _aad => '$format:$version';

  Future<SecretKey> _deriveKey(
    String password,
    List<int> salt,
    int iterations,
  ) {
    final kdf = Pbkdf2.hmacSha256(iterations: iterations, bits: 256);
    return kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  static List<int> _randomBytes(int length) {
    final cipher = AesGcm.with256bits();
    final bytes = <int>[];
    while (bytes.length < length) {
      bytes.addAll(cipher.newNonce());
    }
    return bytes.sublist(0, length);
  }

  static void _validatePassword(String password) {
    if (password.length < _minimumPasswordLength) {
      throw ArgumentError.value(
        password,
        'password',
        'Mật khẩu backup phải có ít nhất $_minimumPasswordLength ký tự.',
      );
    }
  }

  static Map<String, Object?> _decodeEnvelope(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        throw const FormatException('Backup mã hóa phải có cấu trúc object.');
      }
      return Map<String, Object?>.from(decoded);
    } on FormatException {
      rethrow;
    } on Object {
      throw const FormatException('Backup mã hóa không phải JSON hợp lệ.');
    }
  }

  static void _verifyEnvelopeChecksum(Map<String, Object?> decoded) {
    final expected = decoded['checksumSha256'];
    if (expected is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(expected)) {
      throw const FormatException('Checksum backup mã hóa không hợp lệ.');
    }
    final withoutChecksum = Map<String, Object?>.from(decoded)
      ..remove('checksumSha256');
    if (_checksum(withoutChecksum) != expected) {
      throw const FormatException(
        'Checksum không khớp; backup có thể đã hỏng hoặc bị thay đổi.',
      );
    }
  }

  static List<int> _decodeBase64(
    Map<String, Object?> decoded,
    String field, {
    int? expectedLength,
  }) {
    final encoded = decoded[field];
    if (encoded is! String || encoded.isEmpty) {
      throw FormatException('Trường $field của backup không hợp lệ.');
    }
    try {
      final bytes = base64Decode(encoded);
      if (expectedLength != null && bytes.length != expectedLength) {
        throw FormatException('Trường $field của backup không hợp lệ.');
      }
      if (bytes.isEmpty) {
        throw FormatException('Trường $field của backup không được để trống.');
      }
      return bytes;
    } on FormatException {
      rethrow;
    } on Object {
      throw FormatException('Trường $field của backup không hợp lệ.');
    }
  }

  static String _checksum(Map<String, Object?> envelope) {
    return sha256.convert(utf8.encode(jsonEncode(envelope))).toString();
  }
}
