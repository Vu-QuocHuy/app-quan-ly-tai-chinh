import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';

import '../../invoices/domain/invoice_models.dart';
import '../../invoices/domain/invoice_repository.dart';
import 'encrypted_backup_service.dart';

class InvoiceRestorePreview {
  const InvoiceRestorePreview({
    required this.fileName,
    required this.totalCount,
    required this.duplicateCount,
    required this.invalidCount,
    required this.invoices,
    required this.issues,
  });

  final String fileName;
  final int totalCount;
  final int duplicateCount;
  final int invalidCount;
  final List<InvoiceEntity> invoices;
  final List<String> issues;

  int get readyCount => invoices.length;
  bool get canRestore => invoices.isNotEmpty;
}

class InvoiceRestoreService {
  const InvoiceRestoreService();

  Future<InvoiceRestorePreview?> pickAndPreview({
    required InvoiceRepository repository,
    required Iterable<String> categoryIds,
    Future<String?> Function()? requestPassword,
  }) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json', 'hdbak'],
    );
    if (files.isEmpty) return null;
    final file = files.single;
    final existing = await repository.watchInvoiceSummaries().first;
    return previewBytes(
      bytes: await file.readAsBytes(),
      fileName: file.name,
      existingIds: existing.map((invoice) => invoice.id).toSet(),
      existingSourceHashes: existing
          .map((invoice) => invoice.sourceHash)
          .whereType<String>()
          .toSet(),
      categoryIds: categoryIds.toSet(),
      requestPassword: requestPassword,
    );
  }

  Future<InvoiceRestorePreview?> previewBytes({
    required Uint8List bytes,
    required String fileName,
    Set<String> existingIds = const {},
    Set<String> existingSourceHashes = const {},
    Set<String> categoryIds = const {},
    Future<String?> Function()? requestPassword,
  }) async {
    if (bytes.isEmpty) {
      throw const FormatException('Không thể đọc nội dung tệp backup.');
    }
    String content;
    try {
      content = utf8.decode(bytes);
    } on FormatException {
      throw const FormatException('Backup không phải tệp UTF-8 hợp lệ.');
    }
    if (EncryptedBackupService.isEncrypted(content)) {
      final password = await requestPassword?.call();
      if (password == null) return null;
      content = await const EncryptedBackupService().decrypt(content, password);
    }
    return InvoiceRestoreParser.parse(
      content,
      fileName: fileName,
      existingIds: existingIds,
      existingSourceHashes: existingSourceHashes,
      categoryIds: categoryIds,
    );
  }

  Future<void> restore(
    InvoiceRestorePreview preview,
    InvoiceRepository repository,
  ) {
    if (!preview.canRestore) return Future.value();
    return repository.saveInvoices(preview.invoices);
  }
}

abstract final class InvoiceRestoreParser {
  static InvoiceRestorePreview parse(
    String content, {
    required String fileName,
    Set<String> existingIds = const {},
    Set<String> existingSourceHashes = const {},
    Set<String> categoryIds = const {},
  }) {
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Tệp JSON phải có cấu trúc object.');
    }
    if (decoded['format'] != 'hoadon-insight.invoice-export') {
      throw const FormatException('Không đúng định dạng bản sao lưu hóa đơn.');
    }
    if (decoded['version'] != 1) {
      throw FormatException(
        'Phiên bản bản sao lưu không được hỗ trợ: ${decoded['version']}.',
      );
    }
    _verifyChecksum(decoded);
    final rawInvoices = decoded['invoices'];
    if (rawInvoices is! List) {
      throw const FormatException('Bản sao lưu không có danh sách hóa đơn.');
    }

    final knownIds = {...existingIds};
    final knownHashes = {...existingSourceHashes};
    final invoices = <InvoiceEntity>[];
    final issues = <String>[];
    var duplicates = 0;
    var invalid = 0;

    for (var index = 0; index < rawInvoices.length; index++) {
      try {
        final raw = rawInvoices[index];
        if (raw is! Map<String, Object?>) {
          throw const FormatException('Dữ liệu hóa đơn không phải object.');
        }
        final invoice = _invoiceFromMap(raw, categoryIds);
        final sourceHash = invoice.sourceHash;
        if (knownIds.contains(invoice.id) ||
            (sourceHash != null && knownHashes.contains(sourceHash))) {
          duplicates++;
          continue;
        }
        knownIds.add(invoice.id);
        if (sourceHash != null) knownHashes.add(sourceHash);
        invoices.add(invoice);
      } on Object catch (error) {
        invalid++;
        if (issues.length < 20) {
          issues.add('Mục ${index + 1}: ${_message(error)}');
        }
      }
    }

    return InvoiceRestorePreview(
      fileName: fileName,
      totalCount: rawInvoices.length,
      duplicateCount: duplicates,
      invalidCount: invalid,
      invoices: List.unmodifiable(invoices),
      issues: List.unmodifiable(issues),
    );
  }

  static void _verifyChecksum(Map<String, Object?> decoded) {
    final expected = decoded['checksumSha256'];
    if (expected == null) return;
    if (expected is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(expected)) {
      throw const FormatException('Checksum bản sao lưu không hợp lệ.');
    }
    final withoutChecksum = Map<String, Object?>.from(decoded)
      ..remove('checksumSha256');
    final actual = sha256
        .convert(utf8.encode(jsonEncode(withoutChecksum)))
        .toString();
    if (actual != expected) {
      throw const FormatException(
        'Checksum không khớp; tệp có thể đã hỏng hoặc bị thay đổi.',
      );
    }
  }

  static InvoiceEntity _invoiceFromMap(
    Map<String, Object?> map,
    Set<String> categoryIds,
  ) {
    final categoryId = _optionalString(map, 'categoryId');
    final now = DateTime.now();
    return InvoiceEntity(
      id: _requiredString(map, 'id'),
      sellerName: _requiredString(map, 'sellerName'),
      sellerTaxCode: _optionalString(map, 'sellerTaxCode'),
      invoiceNumber: _optionalString(map, 'invoiceNumber'),
      invoiceSymbol: _optionalString(map, 'invoiceSymbol'),
      issuedAt: _optionalDate(map, 'issuedAt'),
      currencyCode: _requiredString(map, 'currencyCode'),
      subtotalMinor: _requiredInt(map, 'subtotalMinor'),
      taxMinor: _requiredInt(map, 'taxMinor'),
      totalMinor: _requiredInt(map, 'totalMinor'),
      sourceType: _enumValue(
        InvoiceSourceType.values,
        _requiredString(map, 'sourceType'),
        'sourceType',
      ),
      sourceHash: _optionalString(map, 'sourceHash'),
      status: _enumValue(
        InvoiceStatus.values,
        _requiredString(map, 'status'),
        'status',
      ),
      categoryId:
          categoryId == null ||
              categoryIds.isEmpty ||
              categoryIds.contains(categoryId)
          ? categoryId
          : 'other',
      notes: _optionalString(map, 'notes'),
      tags: _stringList(map['tags']),
      createdAt: _requiredDate(map, 'createdAt'),
      updatedAt: now,
      confirmedAt: _optionalDate(map, 'confirmedAt'),
      lines: _lines(map['lines']),
      evidence: _evidence(map['evidence']),
    );
  }

  static List<InvoiceLineEntity> _lines(Object? value) {
    if (value == null) return const [];
    if (value is! List) throw const FormatException('lines không hợp lệ.');
    return value
        .map((raw) {
          if (raw is! Map<String, Object?>) {
            throw const FormatException('Một dòng hàng không hợp lệ.');
          }
          return InvoiceLineEntity(
            id: _requiredString(raw, 'id'),
            description: _requiredString(raw, 'description'),
            quantity: _optionalDouble(raw, 'quantity'),
            unitPriceMinor: _optionalInt(raw, 'unitPriceMinor'),
            taxRate: _optionalDouble(raw, 'taxRate'),
            totalMinor: _requiredInt(raw, 'totalMinor'),
          );
        })
        .toList(growable: false);
  }

  static List<FieldEvidenceEntity> _evidence(Object? value) {
    if (value == null) return const [];
    if (value is! List) {
      throw const FormatException('evidence không hợp lệ.');
    }
    return value
        .map((raw) {
          if (raw is! Map<String, Object?>) {
            throw const FormatException('Một bằng chứng dữ liệu không hợp lệ.');
          }
          return FieldEvidenceEntity(
            id: _requiredString(raw, 'id'),
            fieldName: _requiredString(raw, 'fieldName'),
            rawValue: _optionalString(raw, 'rawValue'),
            normalizedValue: _requiredString(raw, 'normalizedValue'),
            source: _enumValue(
              InvoiceSourceType.values,
              _requiredString(raw, 'source'),
              'evidence.source',
            ),
            confidence: _requiredDouble(raw, 'confidence'),
            correctedByUser: raw['correctedByUser'] == true,
          );
        })
        .toList(growable: false);
  }

  static String _requiredString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$key bị thiếu hoặc không hợp lệ.');
    }
    return value.trim();
  }

  static String? _optionalString(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is! String) throw FormatException('$key không hợp lệ.');
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static int _requiredInt(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! num || !value.isFinite) {
      throw FormatException('$key không hợp lệ.');
    }
    return value.toInt();
  }

  static int? _optionalInt(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is! num || !value.isFinite) {
      throw FormatException('$key không hợp lệ.');
    }
    return value.toInt();
  }

  static double _requiredDouble(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! num || !value.isFinite) {
      throw FormatException('$key không hợp lệ.');
    }
    return value.toDouble();
  }

  static double? _optionalDouble(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is! num || !value.isFinite) {
      throw FormatException('$key không hợp lệ.');
    }
    return value.toDouble();
  }

  static DateTime _requiredDate(Map<String, Object?> map, String key) {
    final value = _optionalDate(map, key);
    if (value == null) throw FormatException('$key bị thiếu.');
    return value;
  }

  static DateTime? _optionalDate(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value == null) return null;
    if (value is! String) throw FormatException('$key không hợp lệ.');
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw FormatException('$key không hợp lệ.');
    return parsed;
  }

  static List<String> _stringList(Object? value) {
    if (value == null) return const [];
    if (value is! List || value.any((item) => item is! String)) {
      throw const FormatException('tags không hợp lệ.');
    }
    return value.cast<String>().toList(growable: false);
  }

  static T _enumValue<T extends Enum>(
    List<T> values,
    String name,
    String field,
  ) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    throw FormatException('$field không được hỗ trợ: $name.');
  }

  static String _message(Object error) {
    if (error is FormatException) return error.message.toString();
    return error.toString();
  }
}
