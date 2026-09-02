import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/network/supabase_function_client.dart';
import '../../invoices/domain/invoice_models.dart';
import '../domain/extraction.dart';
import '../domain/invoice_validator.dart';
import '../domain/source_hasher.dart';

class AiExtractionClient implements InvoiceExtractor {
  AiExtractionClient({
    required String baseUrl,
    SupabaseClient? supabaseClient,
    Future<String?> Function()? appCheckTokenProvider,
    Dio? dio,
    Uuid? uuid,
    InvoiceValidator? validator,
  }) : _baseUrl = baseUrl,
       _supabaseFunctions = supabaseClient == null
           ? null
           : SupabaseFunctionClient(client: supabaseClient),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 8),
               receiveTimeout: const Duration(seconds: 15),
             ),
           ),
       _appCheckTokenProvider = appCheckTokenProvider,
       _uuid = uuid ?? const Uuid(),
       _validator = validator ?? const InvoiceValidator();

  final String _baseUrl;
  final SupabaseFunctionClient? _supabaseFunctions;
  final Dio _dio;
  final Future<String?> Function()? _appCheckTokenProvider;
  final Uuid _uuid;
  final InvoiceValidator _validator;

  bool get isConfigured =>
      _supabaseFunctions?.isConfigured == true || _baseUrl.trim().isNotEmpty;

  @override
  String get adapterName => 'backend-ai-structured-output';

  @override
  String get adapterVersion => 'v1';

  @override
  bool canHandle(ExtractionInput input) =>
      isConfigured && (input.ocrText?.trim().isNotEmpty ?? false);

  @override
  Future<ExtractionResult> extract(ExtractionInput input) async {
    if (!isConfigured) {
      throw const NetworkException('Backend AI chưa được cấu hình.');
    }
    try {
      final body = {
        'action': 'extract',
        'requestId': _uuid.v4(),
        'locale': 'vi-VN',
        'text': input.ocrText,
      };
      final data = _supabaseFunctions != null
          ? await _supabaseFunctions.invoke(
              body,
              errorMessage:
                  'Không thể kết nối dịch vụ trích xuất. Dữ liệu OCR vẫn được giữ để thử lại.',
            )
          : await _invokeLegacy('v1/extractions/ocr-text', body);
      return _fromJson(data, input);
    } on DioException catch (error) {
      throw NetworkException(
        'Không thể kết nối dịch vụ trích xuất. Dữ liệu OCR vẫn được giữ để thử lại.',
        cause: error,
      );
    }
  }

  Future<String?> classifyMerchant(String merchant) async {
    if (!isConfigured || merchant.trim().isEmpty) return null;
    try {
      final body = {
        'action': 'classify',
        'requestId': _uuid.v4(),
        'locale': 'vi-VN',
        'merchant': merchant.trim(),
      };
      final data = _supabaseFunctions != null
          ? await _supabaseFunctions.invoke(
              body,
              errorMessage: 'Không thể phân loại merchant từ backend.',
            )
          : await _invokeLegacy('v1/classifications', body);
      final categoryId = data['categoryId'];
      return categoryId is String && categoryId.isNotEmpty ? categoryId : null;
    } on DioException catch (error) {
      throw NetworkException(
        'Không thể phân loại merchant từ backend.',
        cause: error,
      );
    }
  }

  Future<Map<String, dynamic>> _invokeLegacy(
    String path,
    Map<String, Object?> body,
  ) async {
    final appCheckToken = await _appCheckTokenProvider?.call();
    final response = await _dio.post<Map<String, dynamic>>(
      '$_baseUrl/$path',
      data: body,
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          if (appCheckToken != null && appCheckToken.isNotEmpty)
            'X-Firebase-AppCheck': appCheckToken,
        },
      ),
    );
    final data = response.data;
    if (data == null) {
      throw const ExtractionException('Backend trả về dữ liệu rỗng.');
    }
    return data;
  }

  ExtractionResult _fromJson(Map<String, dynamic> json, ExtractionInput input) {
    final now = DateTime.now();
    final id = _uuid.v4();
    final invoiceJson =
        (json['invoice'] as Map?)?.cast<String, dynamic>() ?? json;
    int money(String key) => (invoiceJson[key] as num?)?.round() ?? 0;
    final invoice = InvoiceEntity(
      id: id,
      sellerName: invoiceJson['sellerName'] as String? ?? '',
      sellerTaxCode: invoiceJson['sellerTaxCode'] as String?,
      invoiceNumber: invoiceJson['invoiceNumber'] as String?,
      invoiceSymbol: invoiceJson['invoiceSymbol'] as String?,
      issuedAt: DateTime.tryParse(invoiceJson['invoiceDate'] as String? ?? ''),
      currencyCode:
          invoiceJson['currencyCode'] as String? ??
          AppConstants.defaultCurrency,
      subtotalMinor: money('subtotalMinor'),
      taxMinor: money('taxMinor'),
      totalMinor: money('totalMinor'),
      sourceType: input.sourceType,
      sourceHash: input.bytes.isEmpty
          ? null
          : SourceHasher.sha256Of(input.bytes),
      status: InvoiceStatus.needsReview,
      categoryId: invoiceJson['categoryId'] as String?,
      createdAt: now,
      updatedAt: now,
      lines: ((invoiceJson['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((raw) {
            final item = raw.cast<String, dynamic>();
            return InvoiceLineEntity(
              id: _uuid.v4(),
              description: item['description'] as String? ?? 'Hàng hóa/dịch vụ',
              quantity: (item['quantity'] as num?)?.toDouble(),
              unitPriceMinor: (item['unitPriceMinor'] as num?)?.round(),
              taxRate: (item['taxRate'] as num?)?.toDouble(),
              totalMinor: (item['totalMinor'] as num?)?.round() ?? 0,
            );
          })
          .toList(growable: false),
      evidence: ((json['evidence'] as List?) ?? const [])
          .whereType<Map>()
          .map((raw) {
            final item = raw.cast<String, dynamic>();
            return FieldEvidenceEntity(
              id: _uuid.v4(),
              fieldName: item['field'] as String? ?? 'unknown',
              rawValue: item['rawValue']?.toString(),
              normalizedValue: item['value']?.toString() ?? '',
              source: input.sourceType,
              confidence: ((item['confidence'] as num?)?.toDouble() ?? 0.5)
                  .clamp(0, 1),
            );
          })
          .toList(growable: false),
    );
    final validation = _validator.validate(invoice);
    return ExtractionResult(
      invoice: invoice,
      adapterName: adapterName,
      adapterVersion: adapterVersion,
      warnings: [...validation.errors, ...validation.warnings],
    );
  }
}
