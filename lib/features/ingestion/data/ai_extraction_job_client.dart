import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/supabase_function_client.dart';
import '../domain/extraction.dart';

const _aiJobStatuses = {
  'queued',
  'processing',
  'succeeded',
  'failed',
  'cancelled',
};
const _aiJobInputKinds = {'text', 'image'};

bool _isAiJobUuid(String value) => RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
).hasMatch(value);

class AiExtractionJob {
  const AiExtractionJob({
    required this.id,
    required this.requestId,
    required this.status,
    this.inputKind,
    this.inputMimeType,
    this.attemptCount,
    this.maxAttempts,
    this.availableAt,
    this.result,
    this.errorCode,
    this.createdAt,
    this.updatedAt,
    this.completedAt,
  });

  final String id;
  final String requestId;
  final String status;
  final String? inputKind;
  final String? inputMimeType;
  final int? attemptCount;
  final int? maxAttempts;
  final DateTime? availableAt;
  final Map<String, dynamic>? result;
  final String? errorCode;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? completedAt;

  bool get isTerminal =>
      status == 'succeeded' || status == 'failed' || status == 'cancelled';

  factory AiExtractionJob.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final requestId = json['requestId'];
    final status = json['status'];
    if (id is! String ||
        !_isAiJobUuid(id) ||
        requestId is! String ||
        requestId.isEmpty ||
        requestId.length > 128 ||
        status is! String ||
        !_aiJobStatuses.contains(status)) {
      throw const FormatException('Dữ liệu job AI không hợp lệ.');
    }
    final result = json['result'];
    final inputKind = json['inputKind'];
    final inputMimeType = json['inputMimeType'];
    final attemptCountValue = json['attemptCount'];
    final maxAttemptsValue = json['maxAttempts'];
    final attemptCount = _integer(attemptCountValue);
    final maxAttempts = _integer(maxAttemptsValue);
    Map<String, dynamic>? resultMap;
    if (result != null) {
      if (result is! Map || result.keys.any((key) => key is! String)) {
        throw const FormatException('Dữ liệu job AI không hợp lệ.');
      }
      resultMap = Map<String, dynamic>.from(result);
    }
    final availableAt = _optionalDate(json['availableAt']);
    final createdAt = _optionalDate(json['createdAt']);
    final updatedAt = _optionalDate(json['updatedAt']);
    final completedAt = _optionalDate(json['completedAt']);
    if (inputKind != null &&
            (inputKind is! String || !_aiJobInputKinds.contains(inputKind)) ||
        inputMimeType != null && inputMimeType is! String ||
        attemptCountValue != null && attemptCount == null ||
        attemptCount != null && attemptCount < 0 ||
        maxAttemptsValue != null && maxAttempts == null ||
        maxAttempts != null && (maxAttempts < 1 || maxAttempts > 5) ||
        json['errorCode'] != null && json['errorCode'] is! String ||
        json['availableAt'] != null && availableAt == null ||
        json['createdAt'] != null && createdAt == null ||
        json['updatedAt'] != null && updatedAt == null ||
        json['completedAt'] != null && completedAt == null) {
      throw const FormatException('Dữ liệu job AI không hợp lệ.');
    }
    return AiExtractionJob(
      id: id,
      requestId: requestId,
      status: status,
      inputKind: inputKind as String?,
      inputMimeType: inputMimeType as String?,
      attemptCount: attemptCount,
      maxAttempts: maxAttempts,
      availableAt: availableAt,
      result: resultMap,
      errorCode: json['errorCode'] as String?,
      createdAt: createdAt,
      updatedAt: updatedAt,
      completedAt: completedAt,
    );
  }

  static DateTime? _optionalDate(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  static int? _integer(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    return null;
  }
}

class AiExtractionJobClient {
  AiExtractionJobClient({
    SupabaseClient? supabaseClient,
    Uuid? uuid,
    this.enabled = true,
  }) : _supabaseFunctions = supabaseClient == null
           ? null
           : SupabaseFunctionClient(client: supabaseClient),
       _uuid = uuid ?? const Uuid();

  final SupabaseFunctionClient? _supabaseFunctions;
  final Uuid _uuid;
  final bool enabled;

  bool get isConfigured => enabled && _supabaseFunctions?.isConfigured == true;

  Future<AiExtractionJob> submit(ExtractionInput input) async {
    final body = <String, Object?>{
      'action': 'extract_submit',
      'requestId': _uuid.v4(),
      'locale': 'vi-VN',
      if (input.ocrText?.trim().isNotEmpty == true)
        'text': input.ocrText!.trim()
      else ...{
        'imageBase64': base64Encode(input.bytes),
        'mimeType': _mimeType(input.fileName),
      },
    };
    final data = await _invoke(body);
    return _jobFromResponse(data);
  }

  Future<AiExtractionJob> status(String jobId) async {
    _validateJobId(jobId);
    final data = await _invoke({
      'action': 'extract_status',
      'requestId': _uuid.v4(),
      'locale': 'vi-VN',
      'jobId': jobId,
    });
    return _jobFromResponse(data);
  }

  Future<AiExtractionJob> cancel(String jobId) async {
    _validateJobId(jobId);
    final data = await _invoke({
      'action': 'extract_cancel',
      'requestId': _uuid.v4(),
      'locale': 'vi-VN',
      'jobId': jobId,
    });
    return _actionResult(jobId, data);
  }

  Future<AiExtractionJob> retry(String jobId) async {
    _validateJobId(jobId);
    final data = await _invoke({
      'action': 'extract_retry',
      'requestId': _uuid.v4(),
      'locale': 'vi-VN',
      'jobId': jobId,
    });
    return _actionResult(jobId, data);
  }

  Future<AiExtractionJob> waitForResult(
    String jobId, {
    Duration timeout = const Duration(minutes: 2),
    Duration interval = const Duration(seconds: 2),
  }) async {
    _validateJobId(jobId);
    if (timeout <= Duration.zero || interval <= Duration.zero) {
      throw ArgumentError('Timeout và interval phải lớn hơn 0.');
    }
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final job = await status(jobId);
      if (job.isTerminal) return job;
      if (DateTime.now().isAfter(deadline)) {
        throw const NetworkException(
          'Job AI chưa hoàn tất trong thời gian cho phép.',
        );
      }
      await Future<void>.delayed(interval);
    }
  }

  Future<Map<String, dynamic>> _invoke(Map<String, Object?> body) async {
    final functions = _supabaseFunctions;
    if (!enabled || functions == null || !functions.isConfigured) {
      throw const NetworkException('Backend AI chưa được cấu hình.');
    }
    return functions.invoke(
      body,
      errorMessage: 'Không thể kết nối hàng đợi AI. Vui lòng thử lại sau.',
    );
  }

  AiExtractionJob _jobFromResponse(Map<String, dynamic> data) {
    final rawJob = data['job'];
    if (rawJob is! Map) {
      throw const ExtractionException('Backend trả job AI không hợp lệ.');
    }
    return AiExtractionJob.fromJson(Map<String, dynamic>.from(rawJob));
  }

  AiExtractionJob _actionResult(String jobId, Map<String, dynamic> data) {
    if (!_isAiJobUuid(jobId) ||
        data['status'] is! String ||
        !_aiJobStatuses.contains(data['status'])) {
      throw const ExtractionException(
        'Backend trả trạng thái job AI không hợp lệ.',
      );
    }
    return AiExtractionJob(
      id: jobId,
      requestId: '',
      status: data['status'] as String,
    );
  }

  void _validateJobId(String jobId) {
    if (!_isAiJobUuid(jobId)) {
      throw ArgumentError.value(jobId, 'jobId', 'jobId không hợp lệ.');
    }
  }

  String _mimeType(String fileName) =>
      switch (fileName.toLowerCase().split('.').last) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
}
