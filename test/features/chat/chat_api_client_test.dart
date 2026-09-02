import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/errors/app_exception.dart';
import 'package:hoadon_insight/features/chat/data/chat_api_client.dart';

void main() {
  test('fails explicitly when no chatbot backend is configured', () async {
    final client = ChatApiClient(baseUrl: '');

    await expectLater(
      client.ask(question: 'Chi tiêu tháng này?', history: [], facts: []),
      throwsA(
        isA<NetworkException>().having(
          (error) => error.message,
          'message',
          contains('chưa được cấu hình'),
        ),
      ),
    );
  });

  test('maps a network timeout to the offline-friendly error', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionTimeout,
            ),
          ),
        ),
      );
    final client = ChatApiClient(baseUrl: 'https://example.invalid', dio: dio);

    await expectLater(
      client.ask(question: 'Chi tiêu tháng này?', history: [], facts: []),
      throwsA(
        isA<NetworkException>().having(
          (error) => error.message,
          'message',
          contains('dữ liệu đã lưu offline'),
        ),
      ),
    );
  });
}
