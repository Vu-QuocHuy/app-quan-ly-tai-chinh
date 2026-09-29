import 'dart:convert';

class VietQrPayload {
  const VietQrPayload({
    required this.bankBin,
    required this.accountNumber,
    required this.recipientName,
    required this.memo,
    this.amountVnd,
  });

  final String bankBin;
  final String accountNumber;
  final String recipientName;
  final String memo;
  final int? amountVnd;
}

/// Parses the NAPAS VietQR account-transfer profile from an EMVCo QR payload.
///
/// This deliberately rejects generic URLs and non-transfer QR codes. It never
/// contacts a bank or payment provider and validates the EMV CRC before using
/// any embedded payment details.
abstract final class VietQrParser {
  static VietQrPayload parse(String rawPayload) {
    final bytes = utf8.encode(rawPayload.trim());
    if (bytes.length > 4096) {
      throw const FormatException('Nội dung mã QR vượt quá giới hạn hỗ trợ.');
    }
    final root = _parseTlv(bytes);
    final crc = root['63'];
    if (crc == null || crc.length != 4 || _crcTagOffset(bytes) < 0) {
      throw const FormatException('Mã QR thiếu mã kiểm tra hợp lệ.');
    }
    final expectedCrc = _crc16(
      bytes,
      0,
      bytes.length - 4,
    ).toRadixString(16).padLeft(4, '0').toUpperCase();
    if (utf8.decode(crc).toUpperCase() != expectedCrc) {
      throw const FormatException('Mã QR bị lỗi hoặc không hợp lệ.');
    }
    if (_text(root, '00') != '01') {
      throw const FormatException('Định dạng mã QR không được hỗ trợ.');
    }
    if (_text(root, '53') != '704' || _text(root, '58') != 'VN') {
      throw const FormatException(
        'Chỉ hỗ trợ mã VietQR thanh toán tại Việt Nam.',
      );
    }

    final merchantTemplate = _parseMerchantTemplate(root);
    final beneficiary = merchantTemplate['01'];
    if (beneficiary == null) {
      throw const FormatException(
        'QR này không chứa thông tin chuyển khoản VietQR được hỗ trợ.',
      );
    }
    final paymentAccount = _parseTlv(beneficiary);
    if (_text(paymentAccount, '00') == null ||
        _text(paymentAccount, '01') == null) {
      throw const FormatException(
        'QR này không chứa thông tin tài khoản VietQR được hỗ trợ.',
      );
    }

    final service = _text(merchantTemplate, '02');
    if (service != 'QRIBFTTA' && service != 'QRIBFTTC') {
      throw const FormatException(
        'QR không phải mã chuyển khoản tài khoản/thẻ VietQR.',
      );
    }

    final bankBin = _text(paymentAccount, '00') ?? '';
    final accountNumber = _text(paymentAccount, '01') ?? '';
    if (!RegExp(r'^\d{6}$').hasMatch(bankBin) ||
        !RegExp(r'^[A-Za-z0-9]{1,34}$').hasMatch(accountNumber)) {
      throw const FormatException('Thông tin ngân hàng trong QR không hợp lệ.');
    }

    final amountText = _text(root, '54');
    final amount = amountText == null ? null : _parseAmount(amountText);
    final additionalData = root['62'];
    final additional = additionalData == null
        ? const <String, List<int>>{}
        : _parseTlv(additionalData);
    final memo =
        _text(additional, '08') ??
        _text(additional, '05') ??
        _text(additional, '01') ??
        '';

    final recipientName = (_text(root, '59') ?? '').trim();
    if (recipientName.length > 140 || memo.length > 140) {
      throw const FormatException('Thông tin người nhận trong QR quá dài.');
    }
    return VietQrPayload(
      bankBin: bankBin,
      accountNumber: accountNumber,
      recipientName: recipientName,
      memo: memo.trim(),
      amountVnd: amount,
    );
  }

  static Map<String, List<int>> _parseMerchantTemplate(
    Map<String, List<int>> root,
  ) {
    for (var tag = 26; tag <= 51; tag++) {
      final value = root[tag.toString().padLeft(2, '0')];
      if (value == null) continue;
      try {
        final template = _parseTlv(value);
        if (_text(template, '00') == 'A000000727') return template;
      } on FormatException {
        // Skip unrelated merchant-account templates.
      }
    }
    throw const FormatException('Không tìm thấy thông tin VietQR.');
  }

  static Map<String, List<int>> _parseTlv(List<int> bytes) {
    final fields = <String, List<int>>{};
    var offset = 0;
    while (offset < bytes.length) {
      if (bytes.length - offset < 4) {
        throw const FormatException('Cấu trúc QR không hợp lệ.');
      }
      final tagBytes = bytes.sublist(offset, offset + 2);
      final lengthBytes = bytes.sublist(offset + 2, offset + 4);
      if (!_isAsciiDigits(tagBytes) || !_isAsciiDigits(lengthBytes)) {
        throw const FormatException('Cấu trúc QR không hợp lệ.');
      }
      final tag = String.fromCharCodes(tagBytes);
      final length = int.parse(String.fromCharCodes(lengthBytes));
      final valueStart = offset + 4;
      final valueEnd = valueStart + length;
      if (valueEnd > bytes.length || fields.containsKey(tag)) {
        throw const FormatException('Cấu trúc QR không hợp lệ.');
      }
      fields[tag] = bytes.sublist(valueStart, valueEnd);
      offset = valueEnd;
    }
    return fields;
  }

  static String? _text(Map<String, List<int>> fields, String tag) {
    final value = fields[tag];
    if (value == null) return null;
    try {
      return utf8.decode(value, allowMalformed: false);
    } on FormatException {
      throw const FormatException('Nội dung QR không phải UTF-8 hợp lệ.');
    }
  }

  static bool _isAsciiDigits(List<int> bytes) =>
      bytes.every((byte) => byte >= 0x30 && byte <= 0x39);

  static int _parseAmount(String value) {
    if (!RegExp(r'^\d{1,12}$').hasMatch(value)) {
      throw const FormatException('Số tiền trong QR không hợp lệ.');
    }
    final amount = int.parse(value);
    if (amount < 1) {
      throw const FormatException('Số tiền trong QR phải lớn hơn 0.');
    }
    return amount;
  }

  static int _crcTagOffset(List<int> bytes) {
    if (bytes.length < 8) return -1;
    final start = bytes.length - 8;
    if (String.fromCharCodes(bytes.sublist(start, start + 4)) != '6304') {
      return -1;
    }
    return start;
  }

  static int _crc16(List<int> bytes, int start, int end) {
    var crc = 0xFFFF;
    for (var index = start; index < end; index++) {
      crc ^= bytes[index] << 8;
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1;
        crc &= 0xFFFF;
      }
    }
    return crc;
  }
}
