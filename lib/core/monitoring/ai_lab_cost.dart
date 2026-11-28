import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'ai_lab_store.dart';

/// Tokens of one baseline (B0) request, used to price what an optimisation
/// saved.
@immutable
final class AiLabTokenBaseline {
  const AiLabTokenBaseline({
    this.inputTokens,
    this.thinkingTokens = 0,
    this.outputTokens,
  });

  final int? inputTokens;
  final int thinkingTokens;
  final int? outputTokens;
}

/// Prices and baselines for the AI Lab cost line, read from
/// `assets/ai_lab/pricing.json`. Every value may be missing: the overlay then
/// shows no cost instead of inventing one.
@immutable
final class AiLabPricing {
  const AiLabPricing({
    this.inputUsdPerMillion,
    this.outputUsdPerMillion,
    this.vndPerUsd,
    this.ocrBaseline,
    this.chatInputTokensPerCall,
    this.chatOutputTokensPerCall,
  });

  /// Tolerant parser: wrong types are ignored, never thrown.
  factory AiLabPricing.fromJson(Object? json) {
    final root = json is Map ? json : const <Object?, Object?>{};
    double? number(Object? value) => value is num ? value.toDouble() : null;
    int? integer(Object? value) => value is num ? value.toInt() : null;
    Map<Object?, Object?> section(String key) {
      final value = root[key];
      return value is Map ? value : const <Object?, Object?>{};
    }

    final prices = section('usd_per_million_tokens');
    final ocr = section('ocr_baseline_b0');
    final chat = section('chat_baseline_b0');
    final hasOcr = ocr.isNotEmpty;
    return AiLabPricing(
      inputUsdPerMillion: number(prices['input']),
      outputUsdPerMillion: number(prices['output']),
      vndPerUsd: number(root['vnd_per_usd']),
      ocrBaseline: hasOcr
          ? AiLabTokenBaseline(
              inputTokens: integer(ocr['input_tokens']),
              thinkingTokens: integer(ocr['thinking_tokens']) ?? 0,
              outputTokens: integer(ocr['output_tokens']),
            )
          : null,
      chatInputTokensPerCall: integer(chat['input_tokens_per_call']),
      chatOutputTokensPerCall: integer(chat['output_tokens_per_call']),
    );
  }

  final double? inputUsdPerMillion;

  /// Output price; thinking tokens are billed at this price too.
  final double? outputUsdPerMillion;
  final double? vndPerUsd;
  final AiLabTokenBaseline? ocrBaseline;
  final int? chatInputTokensPerCall;
  final int? chatOutputTokensPerCall;

  bool get hasPrices => inputUsdPerMillion != null && outputUsdPerMillion != null;
}

/// Loads `assets/ai_lab/pricing.json`; a missing or broken file yields an
/// empty [AiLabPricing] (no cost line).
Future<AiLabPricing> loadAiLabPricing(AssetBundle bundle) async {
  try {
    final text = await bundle.loadString('assets/ai_lab/pricing.json');
    return AiLabPricing.fromJson(jsonDecode(text));
  } on Object {
    return const AiLabPricing();
  }
}

class AiLabCostModel {
  const AiLabCostModel(this.pricing);

  final AiLabPricing pricing;

  double? _usd({int? input, int? thinking, int? output}) {
    final inputPrice = pricing.inputUsdPerMillion;
    final outputPrice = pricing.outputUsdPerMillion;
    if (inputPrice == null || outputPrice == null) return null;
    if (input == null && thinking == null && output == null) return null;
    return (input ?? 0) * inputPrice / 1e6 +
        ((output ?? 0) + (thinking ?? 0)) * outputPrice / 1e6;
  }

  /// Cost of one call, or `null` without prices or token data.
  double? costUsd(AiLabCall call) => _usd(
    input: call.inputTokens,
    thinking: call.thinkingTokens,
    output: call.outputTokens,
  );

  /// What one B0 OCR image costs (published TV1 token split).
  double? get ocrBaselineUsd {
    final baseline = pricing.ocrBaseline;
    if (baseline == null) return null;
    return _usd(
      input: baseline.inputTokens,
      thinking: baseline.thinkingTokens,
      output: baseline.outputTokens,
    );
  }

  /// What one B0 chat LLM call costs, once measured (T3.3).
  double? get chatCallUsd {
    final input = pricing.chatInputTokensPerCall;
    final output = pricing.chatOutputTokensPerCall;
    if (input == null && output == null) return null;
    return _usd(input: input, output: output);
  }
}

/// Money line of the AI Lab counters.
@immutable
final class AiLabCostSummary {
  const AiLabCostSummary({
    required this.usd,
    required this.savedUsd,
    required this.vndPerUsd,
  });

  /// `null` unless prices and the VND rate are both configured.
  static AiLabCostSummary? fromTotals(AiLabTotals totals, AiLabPricing pricing) {
    final rate = pricing.vndPerUsd;
    if (!pricing.hasPrices || rate == null) return null;
    return AiLabCostSummary(
      usd: totals.costUsd,
      savedUsd: totals.savedUsd,
      vndPerUsd: rate,
    );
  }

  final double usd;
  final double savedUsd;
  final double vndPerUsd;
}
