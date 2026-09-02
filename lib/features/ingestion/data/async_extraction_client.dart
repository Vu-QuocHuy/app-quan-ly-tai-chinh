import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/app_exception.dart';
import '../../invoices/domain/invoice_models.dart';
import '../domain/async_extraction_job.dart';

class HttpAsyncExtractionGateway implements AsyncExtractionGateway {
  HttpAsyncExtractionGateway({required String baseUrl, Dio? dio, Uuid? uuid})
    : _baseUrl = baseUrl,
      _dio = dio ?? Dio(),
      _uuid = uuid ?? const Uuid();

  final String _baseUrl;
  final Dio _dio;
  final Uuid _uuid;

  @override
  bool get isConfigured => _baseUrl.trim().isNotEmpty;

  @override
  Future<AsyncExtractionJob> submit({
    required Uint8List bytes,
    required String ocrText,
    required String sourceName,
  }) async {
    _ensureConfigured();
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$_baseUrl/v1/extractions/jobs',
        data: {
          'requestId': _uuid.v4(),
          'locale': 'vi-VN',
          'text': ocrText,
          'sourceName': sourceName,
        },
      );
      return _fromJson(response.data ?? const {});
    } on DioException catch (error) {
      throw NetworkException('Không thể xếp hàng tác vụ AI.', cause: error);
    }
  }

  @override
  Future<AsyncExtractionJob> status(String jobId) async {
    _ensureConfigured();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$_baseUrl/v1/extractions/jobs/$jobId',
      );
      return _fromJson(response.data ?? const {});
    } on DioException catch (error) {
      throw NetworkException(
        'Không thể đọc trạng thái tác vụ AI.',
        cause: error,
      );
    }
  }

  @override
  Future<void> cancel(String jobId) async {
    _ensureConfigured();
    try {
      await _dio.delete<void>('$_baseUrl/v1/extractions/jobs/$jobId');
    } on DioException catch (error) {
      throw NetworkException('Không thể hủy tác vụ AI.', cause: error);
    }
  }

  void _ensureConfigured() {
    if (!isConfigured) {
      throw const NetworkException('Backend AI chưa được cấu hình.');
    }
  }

  AsyncExtractionJob _fromJson(Map<String, dynamic> json) {
    final rawResult = json['result'];
    return AsyncExtractionJob(
      id: _requiredString(json, 'jobId'),
      state: _state(json['state']),
      createdAt: _date(json['createdAt']) ?? DateTime.now(),
      updatedAt: _date(json['updatedAt']),
      result: rawResult is Map<String, dynamic>
          ? _invoiceFromJson(rawResult)
          : null,
      errorCode: json['errorCode'] as String?,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  InvoiceEntity _invoiceFromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    int money(String key) => (json[key] as num?)?.round() ?? 0;
    return InvoiceEntity(
      id: (json['id'] as String?) ?? _uuid.v4(),
      sellerName: (json['sellerName'] as String?) ?? '',
      sellerTaxCode: json['sellerTaxCode'] as String?,
      invoiceNumber: json['invoiceNumber'] as String?,
      invoiceSymbol: json['invoiceSymbol'] as String?,
      issuedAt: _date(json['issuedAt']),
      currencyCode: (json['currencyCode'] as String?) ?? 'VND',
      subtotalMinor: money('subtotalMinor'),
      taxMinor: money('taxMinor'),
      totalMinor: money('totalMinor'),
      sourceType: _enum(InvoiceSourceType.values, json['sourceType']),
      sourceHash: json['sourceHash'] as String?,
      status: _enum(InvoiceStatus.values, json['status']),
      categoryId: json['categoryId'] as String?,
      notes: json['notes'] as String?,
      tags: (json['tags'] as List?)?.whereType<String>().toList() ?? const [],
      createdAt: _date(json['createdAt']) ?? now,
      updatedAt: _date(json['updatedAt']) ?? now,
      confirmedAt: _date(json['confirmedAt']),
    );
  }

  String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw const ExtractionException('Backend trả về job không hợp lệ.');
    }
    return value;
  }

  DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  AsyncExtractionJobState _state(Object? value) {
    for (final state in AsyncExtractionJobState.values) {
      if (state.name == value) return state;
    }
    throw const ExtractionException('Trạng thái job AI không hợp lệ.');
  }

  T _enum<T extends Enum>(List<T> values, Object? value) {
    for (final item in values) {
      if (item.name == value) return item;
    }
    throw const ExtractionException('Dữ liệu hóa đơn AI không hợp lệ.');
  }
}
