import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';

class InvoiceAttachment {
  const InvoiceAttachment({
    required this.id,
    required this.invoiceId,
    required this.fileName,
    required this.storagePath,
    required this.contentType,
    required this.sizeBytes,
    required this.createdAt,
  });

  final String id;
  final String invoiceId;
  final String fileName;
  final String storagePath;
  final String contentType;
  final int sizeBytes;
  final DateTime createdAt;

  factory InvoiceAttachment.fromJson(Map<String, dynamic> json) {
    return InvoiceAttachment(
      id: json['id'] as String,
      invoiceId: json['invoice_id'] as String,
      fileName: json['file_name'] as String,
      storagePath: json['storage_path'] as String,
      contentType: json['content_type'] as String,
      sizeBytes: (json['size_bytes'] as num).toInt(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class SupabaseInvoiceAttachmentStore {
  const SupabaseInvoiceAttachmentStore(this._client);

  static const bucketName = 'receipt-images';
  static const _allowedTypes = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'pdf': 'application/pdf',
  };

  final SupabaseClient _client;

  Future<List<InvoiceAttachment>> list(String invoiceId) async {
    final userId = _requireUserId();
    final rows = await _client
        .from('invoice_attachments')
        .select()
        .eq('user_id', userId)
        .eq('invoice_id', invoiceId)
        .order('created_at', ascending: false);
    return rows
        .whereType<Map<String, dynamic>>()
        .map(InvoiceAttachment.fromJson)
        .toList(growable: false);
  }

  Future<InvoiceAttachment> upload({
    required String invoiceId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final userId = _requireUserId();
    if (bytes.isEmpty || bytes.length > AppConstants.maxImportBytes) {
      throw const FormatException('Tệp phải có kích thước từ 1 đến 15 MB.');
    }
    final normalizedName = fileName.trim();
    if (normalizedName.isEmpty ||
        normalizedName.length > 200 ||
        normalizedName.contains(RegExp(r'[\u0000-\u001F\u007F]'))) {
      throw const FormatException('Tên tệp không hợp lệ.');
    }
    final extension = normalizedName.split('.').last.toLowerCase();
    final contentType = _allowedTypes[extension];
    if (contentType == null || !_matchesSignature(bytes, contentType)) {
      throw const FormatException('Định dạng hoặc nội dung tệp không hợp lệ.');
    }

    final invoice = await _client
        .from('invoices')
        .select('id')
        .eq('user_id', userId)
        .eq('id', invoiceId)
        .maybeSingle();
    if (invoice == null) {
      throw const FormatException(
        'Hóa đơn chưa có trên cloud. Hãy đồng bộ hóa đơn trước khi đính kèm.',
      );
    }

    final id = const Uuid().v4();
    final path = '$userId/$id.$extension';
    await _client.storage
        .from(bucketName)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    try {
      final row = await _client
          .from('invoice_attachments')
          .insert({
            'user_id': userId,
            'id': id,
            'invoice_id': invoiceId,
            'file_name': normalizedName,
            'storage_path': path,
            'content_type': contentType,
            'size_bytes': bytes.length,
            'sha256': sha256.convert(bytes).toString(),
          })
          .select()
          .single();
      return InvoiceAttachment.fromJson(row);
    } on Object {
      // Avoid an orphaned private object if its metadata row was rejected.
      await _client.storage.from(bucketName).remove([path]);
      rethrow;
    }
  }

  Future<Uri> signedUrl(InvoiceAttachment attachment) async {
    _validateOwnedPath(attachment.storagePath);
    final url = await _client.storage
        .from(bucketName)
        .createSignedUrl(attachment.storagePath, 120);
    return Uri.parse(url);
  }

  Future<void> delete(InvoiceAttachment attachment) async {
    _validateOwnedPath(attachment.storagePath);
    final userId = _requireUserId();
    await _client.storage.from(bucketName).remove([attachment.storagePath]);
    await _client
        .from('invoice_attachments')
        .delete()
        .eq('user_id', userId)
        .eq('id', attachment.id);
  }

  String _requireUserId() {
    if (_client.auth.currentSession == null) {
      throw const AuthException('Hãy đăng nhập để lưu chứng từ lên cloud.');
    }
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw const AuthException('Phiên đăng nhập đã hết hạn.');
    }
    return userId;
  }

  void _validateOwnedPath(String path) {
    final userId = _requireUserId();
    if (!path.startsWith('$userId/') || path.contains('..')) {
      throw const FormatException('Tệp đính kèm không thuộc tài khoản này.');
    }
  }

  bool _matchesSignature(Uint8List bytes, String contentType) {
    bool startsWith(List<int> signature) =>
        bytes.length >= signature.length &&
        signature.indexed.every((entry) => bytes[entry.$1] == entry.$2);

    return switch (contentType) {
      'application/pdf' => startsWith(const [0x25, 0x50, 0x44, 0x46, 0x2d]),
      'image/jpeg' => startsWith(const [0xff, 0xd8, 0xff]),
      'image/png' => startsWith(const [
        0x89,
        0x50,
        0x4e,
        0x47,
        0x0d,
        0x0a,
        0x1a,
        0x0a,
      ]),
      'image/webp' =>
        bytes.length >= 12 &&
            startsWith(const [0x52, 0x49, 0x46, 0x46]) &&
            bytes[8] == 0x57 &&
            bytes[9] == 0x45 &&
            bytes[10] == 0x42 &&
            bytes[11] == 0x50,
      _ => false,
    };
  }
}
