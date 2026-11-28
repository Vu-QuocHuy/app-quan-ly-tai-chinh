import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_tokens.dart';
import '../application/ai_lab_batch_providers.dart';
import '../application/ai_lab_batch_runner.dart';

/// "Chạy 40 câu" section of the AI Lab control panel: runs the benchmark
/// questions through the mounted chat screen and copies the CSV.
class AiLabBatchSection extends ConsumerStatefulWidget {
  const AiLabBatchSection({super.key});

  @override
  ConsumerState<AiLabBatchSection> createState() => _AiLabBatchSectionState();
}

class _AiLabBatchSectionState extends ConsumerState<AiLabBatchSection> {
  final List<AiLabBatchRow> _rows = [];
  StreamSubscription<AiLabBatchRow>? _subscription;
  bool _running = false;
  int _repeats = 1;
  int _total = 0;
  Object? _error;

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _running = true;
      _error = null;
      _total = 0;
      _rows.clear();
    });
    try {
      final questions = await ref.read(aiLabQuestionsProvider.future);
      final seeds = await ref.read(aiLabSeedExpectationsProvider.future);
      if (!mounted) return;
      final runner = AiLabBatchRunner(
        driver: ref.read(aiLabChatDriverProvider),
        seedExpectations: seeds,
        flagProfile: ref.read(aiLabFlagProfileProvider),
        pause: ref.read(aiLabBatchPauseProvider),
      );
      setState(() => _total = questions.length * _repeats);
      _subscription = runner
          .run(questions: questions, repeats: _repeats)
          .listen(
            (row) {
              if (mounted) setState(() => _rows.add(row));
            },
            onError: (Object error) {
              if (mounted) {
                setState(() {
                  _error = error;
                  _running = false;
                });
              }
            },
            onDone: () {
              if (mounted) setState(() => _running = false);
            },
          );
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _running = false;
        });
      }
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: aiLabBatchCsv(_rows)));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('Đã sao chép CSV')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final questionCount =
        ref.watch(aiLabQuestionsProvider).valueOrNull?.length ?? 40;
    final total = _total > 0 ? _total : questionCount * _repeats;
    final finished = !_running && _rows.isNotEmpty;
    final summary = aiLabBatchSummary(_rows);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Chạy 40 câu', style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        Text('Mở màn Chat trước khi chạy', style: theme.textTheme.bodySmall),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 1, label: Text('1 lần')),
            ButtonSegment(value: 3, label: Text('3 lần')),
          ],
          selected: {_repeats},
          onSelectionChanged: _running
              ? null
              : (value) => setState(() {
                  _repeats = value.first;
                  _total = 0;
                }),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton(
              onPressed: _running ? null : _start,
              child: const Text('Chạy'),
            ),
            OutlinedButton(
              onPressed: _rows.isEmpty ? null : _copy,
              child: const Text('Sao chép CSV'),
            ),
            Text('${_rows.length}/$total', style: theme.textTheme.labelLarge),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Lỗi: không chạy được bộ câu hỏi.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        if (finished) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${summary.turns} lượt · TB '
            '${_decimal(summary.averageLlmCalls, 2)} lượt gọi LLM · '
            '${_decimal(summary.localShare * 100, 1)}% cục bộ',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  static String _decimal(double value, int digits) =>
      value.toStringAsFixed(digits).replaceAll('.', ',');
}
