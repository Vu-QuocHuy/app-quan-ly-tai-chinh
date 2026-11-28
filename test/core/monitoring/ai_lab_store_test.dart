import 'package:hoadon_insight/core/monitoring/ai_lab_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiLabCall.fromMeta', () {
    test('thiếu _meta (server không bật AI_EXPOSE_USAGE_META) -> các ô null, không crash',
        () {
      final call = AiLabCall.fromMeta(null, action: 'chat', durationMs: 120);

      expect(call.action, 'chat');
      expect(call.durationMs, 120);
      expect(call.llmCalls, 0);
      expect(call.inputTokens, isNull);
      expect(call.thinkingTokens, isNull);
      expect(call.totalTokens, isNull);
      expect(call.provider, isNull);
      expect(call.failover, isFalse);
    });

    test('đọc đủ các khóa mà ai-api trả trong _meta', () {
      final call = AiLabCall.fromMeta(
        {
          'provider': 'gemini',
          'inputTokens': 2100,
          'outputTokens': 190,
          'thinkingTokens': 0,
          'llmCalls': 1,
          'failover': true,
          'flagSet': 'ai.extract.thinking_low',
          'model': 'gemini-3.6-flash',
        },
        action: 'extract',
        durationMs: 7000,
      );

      expect(call.provider, 'gemini');
      expect(call.inputTokens, 2100);
      expect(call.outputTokens, 190);
      expect(call.thinkingTokens, 0);
      expect(call.llmCalls, 1);
      expect(call.failover, isTrue);
      expect(call.serverFlagSet, 'ai.extract.thinking_low');
      expect(call.model, 'gemini-3.6-flash');
      expect(call.totalTokens, 2290);
    });

    test('kiểu dữ liệu sai trong _meta bị bỏ qua thay vì ném lỗi', () {
      final call = AiLabCall.fromMeta(
        {'inputTokens': '2100', 'llmCalls': 'một', 'failover': 'yes'},
        action: 'chat',
        durationMs: 1,
      );

      expect(call.inputTokens, isNull);
      expect(call.llmCalls, 0);
      expect(call.failover, isFalse);
    });

    test('totalTokens chỉ cộng các phần có mặt', () {
      final call = AiLabCall(
        action: 'chat',
        durationMs: 1,
        inputTokens: 100,
        outputTokens: 20,
      );
      expect(call.totalTokens, 120);
    });
  });

  group('AiLabStore', () {
    late AiLabStore store;
    setUp(() => store = AiLabStore());

    test('recordCall cộng dồn lượt gọi LLM và token; token null tính là 0', () {
      store.recordCall(AiLabCall(
        action: 'chat',
        durationMs: 1,
        llmCalls: 1,
        inputTokens: 100,
        outputTokens: 20,
      ));
      store.recordCall(AiLabCall(action: 'chat', durationMs: 1, llmCalls: 1));
      store.recordCall(AiLabCall(
        action: 'extract',
        durationMs: 1,
        llmCalls: 1,
        inputTokens: 2000,
        outputTokens: 190,
        thinkingTokens: 0,
      ));

      expect(store.totals.llmCalls, 3);
      expect(store.totals.tokens, 2310);
    });

    test('lastExtract lưu lần OCR gần nhất có token, bỏ qua lời gọi khác', () {
      store.recordCall(AiLabCall(
        action: 'extract',
        durationMs: 1,
        inputTokens: 2000,
        outputTokens: 190,
        thinkingTokens: 900,
      ));
      store.recordCall(AiLabCall(
        action: 'chat',
        durationMs: 1,
        inputTokens: 50,
      ));
      store.recordCall(AiLabCall(action: 'extract', durationMs: 1));

      expect(store.lastExtract?.thinkingTokens, 900);
    });

    test('lastExtract nhận cả extract_status khi OCR chạy bằng job', () {
      store.recordCall(AiLabCall(
        action: 'extract_status',
        durationMs: 1,
        inputTokens: 2000,
        outputTokens: 190,
        thinkingTokens: 0,
      ));
      expect(store.lastExtract?.inputTokens, 2000);
    });

    test('recordTurn: tra cứu 0 lượt tiết kiệm 3 lượt so với B0', () {
      store.recordTurn(const AiLabTurn(
        messageId: 'm1',
        route: AiLabRoute.local,
        llmCalls: 0,
        durationMs: 40,
      ));
      expect(store.totals.savedLlmCalls, 3);
    });

    test('recordTurn: 1 lượt tiết kiệm 2; 3 lượt tiết kiệm 0; nhiều hơn 3 không âm',
        () {
      for (final calls in [1, 3, 5]) {
        store.recordTurn(AiLabTurn(
          messageId: 'm$calls',
          route: AiLabRoute.cloud,
          llmCalls: calls,
          durationMs: 1,
        ));
      }
      expect(store.totals.savedLlmCalls, 2);
    });

    test('turnFor trả đúng lượt theo messageId, null nếu không có', () {
      store.recordTurn(const AiLabTurn(
        messageId: 'm1',
        route: AiLabRoute.fallback,
        llmCalls: 1,
        durationMs: 2100,
        provider: 'gemini',
      ));

      expect(store.turnFor('m1')?.provider, 'gemini');
      expect(store.turnFor('m1')?.route, AiLabRoute.fallback);
      expect(store.turnFor('khong-co'), isNull);
    });

    test('chỉ giữ tối đa capacity lượt, bỏ lượt cũ nhất', () {
      final small = AiLabStore(capacity: 2);
      for (final id in ['a', 'b', 'c']) {
        small.recordTurn(AiLabTurn(
          messageId: id,
          route: AiLabRoute.cloud,
          llmCalls: 1,
          durationMs: 1,
        ));
      }
      expect(small.turnFor('a'), isNull);
      expect(small.turnFor('b'), isNotNull);
      expect(small.turnFor('c'), isNotNull);
    });

    test('thông báo cho listener khi ghi, đổi lỗi giả lập và reset', () {
      var notified = 0;
      store.addListener(() => notified++);

      store.recordCall(AiLabCall(action: 'chat', durationMs: 1));
      store.recordTurn(const AiLabTurn(
        messageId: 'm1',
        route: AiLabRoute.local,
        llmCalls: 0,
        durationMs: 1,
      ));
      store.fault = '429';
      store.tamperExtractTotal = true;
      store.reset();

      expect(notified, 5);
    });

    test('đặt lại cùng giá trị không thông báo thừa', () {
      var notified = 0;
      store.addListener(() => notified++);
      store.fault = null;
      store.tamperExtractTotal = false;
      expect(notified, 0);
    });

    test('reset xóa số liệu và các công tắc giả lập', () {
      store.recordCall(AiLabCall(
        action: 'extract',
        durationMs: 1,
        llmCalls: 1,
        inputTokens: 10,
      ));
      store.recordTurn(const AiLabTurn(
        messageId: 'm1',
        route: AiLabRoute.local,
        llmCalls: 0,
        durationMs: 1,
      ));
      store.fault = '500';
      store.tamperExtractTotal = true;

      store.reset();

      expect(store.totals.llmCalls, 0);
      expect(store.totals.tokens, 0);
      expect(store.totals.savedLlmCalls, 0);
      expect(store.lastExtract, isNull);
      expect(store.turnFor('m1'), isNull);
      expect(store.fault, isNull);
      expect(store.tamperExtractTotal, isFalse);
    });

    test('failover của server được nhớ cho lượt chat hiện tại, đọc một lần', () {
      store.recordCall(AiLabCall(
        action: 'chat',
        durationMs: 1,
        provider: 'gemini',
        failover: true,
      ));

      expect(store.takeTurnSignals().failoverProvider, 'gemini');
      expect(store.takeTurnSignals().failoverProvider, isNull);
    });

    test('markDegraded được báo đúng một lần', () {
      store.markDegraded();

      expect(store.takeTurnSignals().degraded, isTrue);
      expect(store.takeTurnSignals().degraded, isFalse);
    });

    test('reset xóa cả tín hiệu lượt đang chờ', () {
      store.markDegraded();
      store.recordCall(AiLabCall(
        action: 'chat',
        durationMs: 1,
        provider: 'gemini',
        failover: true,
      ));

      store.reset();

      final signals = store.takeTurnSignals();
      expect(signals.degraded, isFalse);
      expect(signals.failoverProvider, isNull);
    });

    test('fault chỉ nhận 429, 500, timeout hoặc null', () {
      expect(() => store.fault = '404', throwsArgumentError);
      store.fault = 'timeout';
      expect(store.fault, 'timeout');
    });

    test('lastServerFlagSet lấy flagSet của lời gọi gần nhất có giá trị, reset xóa', () {
      expect(store.lastServerFlagSet, isNull);
      store.recordCall(const AiLabCall(
          action: 'chat', durationMs: 1, serverFlagSet: 'none'));
      expect(store.lastServerFlagSet, 'none');
      store.recordCall(const AiLabCall(action: 'chat', durationMs: 1));
      expect(store.lastServerFlagSet, 'none');
      store.recordCall(const AiLabCall(
          action: 'chat', durationMs: 1, serverFlagSet: 'a,b'));
      expect(store.lastServerFlagSet, 'a,b');

      store.reset();
      expect(store.lastServerFlagSet, isNull);
    });
  });
}
