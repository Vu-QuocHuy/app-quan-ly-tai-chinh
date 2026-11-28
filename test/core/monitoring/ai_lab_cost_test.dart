import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/monitoring/ai_lab_cost.dart';
import 'package:hoadon_insight/core/monitoring/ai_lab_store.dart';

// Synthetic prices: they only make the arithmetic easy to check by hand.
const _json = {
  'version': 1,
  'vnd_per_usd': 25000,
  'usd_per_million_tokens': {'input': 1.0, 'output': 4.0},
  'ocr_baseline_b0': {
    'input_tokens': 2000,
    'thinking_tokens': 1000,
    'output_tokens': 200,
  },
  'chat_baseline_b0': {
    'input_tokens_per_call': 1000,
    'output_tokens_per_call': 100,
  },
};

AiLabCall _extract({int input = 2000, int thinking = 0, int output = 200}) =>
    AiLabCall(
      action: 'extract',
      durationMs: 1,
      llmCalls: 1,
      inputTokens: input,
      thinkingTokens: thinking,
      outputTokens: output,
    );

void main() {
  group('AiLabPricing.fromJson', () {
    test('reads prices, rate and both baselines', () {
      final pricing = AiLabPricing.fromJson(_json);

      expect(pricing.inputUsdPerMillion, 1.0);
      expect(pricing.outputUsdPerMillion, 4.0);
      expect(pricing.vndPerUsd, 25000);
      expect(pricing.ocrBaseline?.thinkingTokens, 1000);
      expect(pricing.chatInputTokensPerCall, 1000);
      expect(pricing.chatOutputTokensPerCall, 100);
      expect(pricing.hasPrices, isTrue);
    });

    test('null prices (not filled in yet) mean "no prices"', () {
      final pricing = AiLabPricing.fromJson({
        'usd_per_million_tokens': {'input': null, 'output': null},
        'vnd_per_usd': null,
      });

      expect(pricing.hasPrices, isFalse);
      expect(pricing.vndPerUsd, isNull);
    });

    test('garbage does not throw', () {
      final pricing = AiLabPricing.fromJson({
        'usd_per_million_tokens': 'free',
        'ocr_baseline_b0': [1, 2],
        'vnd_per_usd': 'lots',
      });

      expect(pricing.hasPrices, isFalse);
      expect(pricing.ocrBaseline, isNull);
      expect(pricing.vndPerUsd, isNull);
    });
  });

  group('AiLabCostModel', () {
    final model = AiLabCostModel(AiLabPricing.fromJson(_json));

    test('costs a call as input + (output + thinking) tokens', () {
      // 2000 * 1 / 1e6 + (200 + 1000) * 4 / 1e6 = 0.002 + 0.0048
      expect(model.costUsd(_extract(thinking: 1000)), closeTo(0.0068, 1e-9));
    });

    test('thinking tokens are billed as output tokens', () {
      final withThinking = model.costUsd(_extract(thinking: 1000))!;
      final without = model.costUsd(_extract(thinking: 0))!;

      expect(withThinking - without, closeTo(1000 * 4 / 1e6, 1e-9));
    });

    test('a call without token data has no cost', () {
      expect(model.costUsd(AiLabCall(action: 'chat', durationMs: 1)), isNull);
    });

    test('without prices nothing is costed', () {
      final empty = AiLabCostModel(AiLabPricing.fromJson({}));
      expect(empty.costUsd(_extract()), isNull);
      expect(empty.ocrBaselineUsd, isNull);
      expect(empty.chatCallUsd, isNull);
    });

    test('baseline OCR cost (B0) uses the published TV1 token split', () {
      // 2000 * 1 / 1e6 + (200 + 1000) * 4 / 1e6
      expect(model.ocrBaselineUsd, closeTo(0.0068, 1e-9));
    });

    test('baseline chat call cost', () {
      // 1000 * 1 / 1e6 + 100 * 4 / 1e6
      expect(model.chatCallUsd, closeTo(0.0014, 1e-9));
    });
  });

  group('AiLabStore with a cost model', () {
    late AiLabStore store;
    setUp(() {
      store = AiLabStore()
        ..costModel = AiLabCostModel(AiLabPricing.fromJson(_json));
    });

    test('accumulates cost and OCR savings against the B0 baseline', () {
      store.recordCall(_extract(thinking: 0)); // 0.0028 spent, 0.0040 saved

      expect(store.totals.costUsd, closeTo(0.0028, 1e-9));
      expect(store.totals.savedUsd, closeTo(0.0040, 1e-9));
    });

    test('a call as expensive as B0 saves nothing (never negative)', () {
      store.recordCall(_extract(thinking: 1000));
      store.recordCall(_extract(thinking: 2000));

      expect(store.totals.savedUsd, 0);
    });

    test('a blocked duplicate saves one whole B0 OCR call', () {
      store.recordDuplicateBlocked();

      expect(store.totals.savedUsd, closeTo(0.0068, 1e-9));
      expect(store.totals.savedOcrCalls, 1);
    });

    test('chat turns without LLM calls save the baseline chat cost', () {
      store.recordTurn(
        const AiLabTurn(
          messageId: 'm1',
          route: AiLabRoute.local,
          llmCalls: 0,
          durationMs: 1,
        ),
      );

      expect(store.totals.savedLlmCalls, 3);
      expect(store.totals.savedUsd, closeTo(3 * 0.0014, 1e-9));
    });

    test('without a cost model only counts are tracked', () {
      final plain = AiLabStore();
      plain.recordCall(_extract(thinking: 0));
      plain.recordDuplicateBlocked();

      expect(plain.totals.costUsd, 0);
      expect(plain.totals.savedUsd, 0);
      expect(plain.totals.savedOcrCalls, 1);
    });

    test('reset clears costs but keeps the model', () {
      store.recordCall(_extract(thinking: 0));
      store.reset();

      expect(store.totals.costUsd, 0);
      expect(store.costModel, isNotNull);
    });
  });

  group('AiLabCostSummary.fromTotals', () {
    test('needs prices and a VND rate', () {
      final pricing = AiLabPricing.fromJson(_json);
      final summary = AiLabCostSummary.fromTotals(
        const AiLabTotals(costUsd: 0.5, savedUsd: 0.25),
        pricing,
      );

      expect(summary?.usd, 0.5);
      expect(summary?.savedUsd, 0.25);
      expect(summary?.vndPerUsd, 25000);
    });

    test('is null when prices or the rate are missing', () {
      final noRate = AiLabPricing.fromJson({
        ..._json,
        'vnd_per_usd': null,
      });
      final noPrices = AiLabPricing.fromJson({});

      expect(AiLabCostSummary.fromTotals(const AiLabTotals(), noRate), isNull);
      expect(AiLabCostSummary.fromTotals(const AiLabTotals(), noPrices), isNull);
    });
  });
  group('costSummary and pricing asset', () {
    test('store.costSummary follows the cost model and totals', () {
      final store = AiLabStore()
        ..costModel = AiLabCostModel(AiLabPricing.fromJson(_json));
      store.recordCall(_extract(thinking: 0));

      final summary = store.costSummary!;
      expect(summary.usd, closeTo(0.0028, 1e-9));
      expect(summary.savedUsd, closeTo(0.0040, 1e-9));
      expect(AiLabStore().costSummary, isNull);
    });

    test('the shipped pricing.json parses and has no invented prices', () {
      final text = File('assets/ai_lab/pricing.json').readAsStringSync();
      final pricing = AiLabPricing.fromJson(jsonDecode(text));

      expect(pricing.hasPrices, isFalse, reason: 'prices come from Bảng 6.6');
      expect(pricing.vndPerUsd, isNull);
      expect(pricing.ocrBaseline?.inputTokens, 2094);
      expect(pricing.ocrBaseline?.thinkingTokens, 1025);
      expect(pricing.ocrBaseline?.outputTokens, 186);
    });
  });
}
