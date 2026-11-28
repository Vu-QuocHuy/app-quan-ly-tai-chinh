import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hoadon_insight/core/errors/app_exception.dart';
import 'package:hoadon_insight/core/network/function_error.dart';

void main() {
  test('reads the code from a FunctionException body', () {
    final error = FunctionException(
      status: 503,
      details: {'code': 'AI_DEGRADED', 'message': 'busy'},
    );

    expect(functionErrorCode(error), 'AI_DEGRADED');
  });

  test('finds the code through the cause of a NetworkException', () {
    final error = NetworkException(
      'Không thể kết nối chatbot AI lúc này.',
      cause: FunctionException(status: 429, details: {'code': 'MODEL_RATE_LIMITED'}),
    );

    expect(functionErrorCode(error), 'MODEL_RATE_LIMITED');
  });

  test('returns null when there is no structured code', () {
    expect(functionErrorCode(FunctionException(status: 500, details: 'boom')), isNull);
    expect(functionErrorCode(FunctionException(status: 500)), isNull);
    expect(functionErrorCode(StateError('x')), isNull);
    expect(functionErrorCode(const NetworkException('plain')), isNull);
  });

  test('ignores a non-string code', () {
    expect(
      functionErrorCode(FunctionException(status: 500, details: {'code': 42})),
      isNull,
    );
  });
}
