import 'package:flutter/foundation.dart';

import 'ai_lab_chat_driver.dart';
import 'ai_lab_question.dart';

/// CSV columns, in the order `tool/benchmark/summarize_chat.py` expects.
const aiLabBatchCsvColumns = [
  'question_id',
  'group',
  'flag_profile',
  'run',
  'route',
  'llm_calls',
  'cloud_calls',
  'duration_ms',
  'contains_expected',
  'misrouted_write',
];

/// One measured turn (one CSV line).
@immutable
class AiLabBatchRow {
  const AiLabBatchRow({
    required this.questionId,
    required this.group,
    required this.flagProfile,
    required this.run,
    required this.route,
    required this.llmCalls,
    required this.cloudCalls,
    required this.durationMs,
    required this.containsExpected,
    required this.misroutedWrite,
  });

  final String questionId;
  final String group;
  final String flagProfile;
  final int run;
  final String route;
  final int llmCalls;
  final int cloudCalls;
  final int durationMs;

  /// `true`, `false`, or empty when the question has nothing to check.
  final String containsExpected;
  final bool misroutedWrite;

  AiLabBatchRow copyWith({
    String? route,
    int? llmCalls,
    int? cloudCalls,
    int? durationMs,
    String? containsExpected,
    bool? misroutedWrite,
  }) => AiLabBatchRow(
    questionId: questionId,
    group: group,
    flagProfile: flagProfile,
    run: run,
    route: route ?? this.route,
    llmCalls: llmCalls ?? this.llmCalls,
    cloudCalls: cloudCalls ?? this.cloudCalls,
    durationMs: durationMs ?? this.durationMs,
    containsExpected: containsExpected ?? this.containsExpected,
    misroutedWrite: misroutedWrite ?? this.misroutedWrite,
  );

  List<Object> get _cells => [
    questionId,
    group,
    flagProfile,
    run,
    route,
    llmCalls,
    cloudCalls,
    durationMs,
    containsExpected,
    misroutedWrite,
  ];
}

/// Runs the benchmark questions one by one through an [AiLabChatDriver].
class AiLabBatchRunner {
  AiLabBatchRunner({
    required this.driver,
    required this.seedExpectations,
    required this.flagProfile,
    this.pause = const Duration(milliseconds: 400),
  });

  final AiLabChatDriver driver;
  final Map<String, String> seedExpectations;
  final String flagProfile;

  /// Breather between two questions so the chat screen can settle.
  final Duration pause;

  Stream<AiLabBatchRow> run({
    required List<AiLabQuestion> questions,
    int repeats = 1,
  }) async* {
    var first = true;
    for (var run = 1; run <= repeats; run++) {
      for (final question in questions) {
        if (!first && pause > Duration.zero) await Future<void>.delayed(pause);
        first = false;
        yield await _measure(question, run);
      }
    }
  }

  Future<AiLabBatchRow> _measure(AiLabQuestion question, int run) async {
    AiLabChatOutcome outcome;
    try {
      outcome = await driver.ask(question.text);
    } on Object {
      outcome = const AiLabChatOutcome(route: 'error');
    }
    return AiLabBatchRow(
      questionId: question.id,
      group: question.group,
      flagProfile: flagProfile,
      run: run,
      route: outcome.route,
      llmCalls: outcome.llmCalls,
      cloudCalls: outcome.cloudCalls,
      durationMs: outcome.durationMs,
      containsExpected: _containsExpected(question, outcome.answerText),
      misroutedWrite: question.group == 'write' && outcome.route == 'local',
    );
  }

  String _containsExpected(AiLabQuestion question, String? answer) {
    if (question.expectedKeys.isEmpty) return '';
    final expected = <String>[];
    for (final key in question.expectedKeys) {
      final value = seedExpectations[key];
      if (value == null || value == 'MANUAL') return '';
      expected.add(_fold(value));
    }
    if (answer == null) return 'false';
    final folded = _fold(answer);
    return expected.every(folded.contains) ? 'true' : 'false';
  }

  /// Currency output uses NBSP / NNBSP before the symbol; compare as spaces.
  static String _fold(String text) =>
      text.replaceAll(' ', ' ').replaceAll(' ', ' ');
}

String _csvCell(Object value) {
  final text = '$value';
  if (text.contains(RegExp('[,"\r\n]'))) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}

/// CSV text for `summarize_chat.py` (header + one line per row).
String aiLabBatchCsv(List<AiLabBatchRow> rows) {
  final buffer = StringBuffer(aiLabBatchCsvColumns.join(','))..write('\n');
  for (final row in rows) {
    buffer
      ..write(row._cells.map(_csvCell).join(','))
      ..write('\n');
  }
  return buffer.toString();
}

@immutable
class AiLabBatchSummary {
  const AiLabBatchSummary({
    required this.turns,
    required this.averageLlmCalls,
    required this.localShare,
  });

  final int turns;
  final double averageLlmCalls;

  /// 0..1, share of turns with route `local`.
  final double localShare;
}

AiLabBatchSummary aiLabBatchSummary(List<AiLabBatchRow> rows) {
  if (rows.isEmpty) {
    return const AiLabBatchSummary(
      turns: 0,
      averageLlmCalls: 0,
      localShare: 0,
    );
  }
  final calls = rows.fold<int>(0, (sum, row) => sum + row.llmCalls);
  final local = rows.where((row) => row.route == 'local').length;
  return AiLabBatchSummary(
    turns: rows.length,
    averageLlmCalls: calls / rows.length,
    localShare: local / rows.length,
  );
}
