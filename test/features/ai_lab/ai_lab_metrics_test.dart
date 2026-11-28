import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hoadon_insight/core/config/ai_flag_profile.dart';
import 'package:hoadon_insight/core/config/feature_flags.dart';
import 'package:hoadon_insight/core/monitoring/ai_lab_store.dart';
import 'package:hoadon_insight/features/ai_lab/data/ai_lab_metrics.dart';

final _now = DateTime.fromMillisecondsSinceEpoch(1764300000000, isUtc: true);

Map<String, Object?> _build({
  Set<AiOptimizationFlag> flags = const {},
  AiFlagProfileKind profile = AiFlagProfileKind.b0,
  AiLabCall? lastExtract,
  List<AiLabTurn> turns = const [],
  List<AiLabCall> calls = const [],
  String? serverFlagSet,
  AiLabTotals totals = const AiLabTotals(),
}) => buildAiLabMetrics(
  now: _now,
  launchProfile: AiFlagProfileKind.b0,
  profile: profile,
  flags: flags,
  serverFlagSet: serverFlagSet,
  totals: totals,
  lastExtract: lastExtract,
  turns: turns,
  calls: calls,
);

/// Fake clock + fake timers: [advance] moves time and fires due timers.
class _FakeScheduler {
  DateTime now = DateTime.fromMillisecondsSinceEpoch(0);
  final timers = <_FakeTimer>[];

  Timer create(Duration delay, void Function() run) {
    final timer = _FakeTimer(now.add(delay), delay, run);
    timers.add(timer);
    return timer;
  }

  void advance(int ms) {
    final target = now.add(Duration(milliseconds: ms));
    while (true) {
      final due = timers.where((t) => t.isActive && !t.due.isAfter(target));
      if (due.isEmpty) break;
      final next = due.reduce((a, b) => a.due.isBefore(b.due) ? a : b);
      now = next.due;
      next.fire();
    }
    now = target;
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this.due, this.delay, this.run);
  final DateTime due;
  final Duration delay;
  final void Function() run;
  bool cancelled = false;
  bool fired = false;

  void fire() {
    if (cancelled || fired) return;
    fired = true;
    run();
  }

  @override
  void cancel() => cancelled = true;
  @override
  bool get isActive => !cancelled && !fired;
  @override
  int get tick => 0;
}

void main() {
  group('buildAiLabMetrics', () {
    test('khung cơ bản đúng protocol §2 (B0, chưa có số liệu)', () {
      final m = _build();
      expect(m.keys.toSet(), {
        'ailab',
        'event',
        'ts',
        'launchProfile',
        'profile',
        'enabledCount',
        'flagSet',
        'flags',
        'serverFlagSet',
        'totals',
        'lastExtract',
        'turns',
        'calls',
      });
      expect(m['ailab'], 1);
      expect(m['event'], 'metrics');
      expect(m['ts'], 1764300000000);
      expect(m['launchProfile'], 'b0');
      expect(m['profile'], 'b0');
      expect(m['enabledCount'], 0);
      expect(m['flagSet'], 'none');
      expect(m['serverFlagSet'], isNull);
      expect(m['lastExtract'], isNull);
      expect(m['turns'], isEmpty);
      expect(m['calls'], isEmpty);
      expect(m['totals'], {
        'llmCalls': 0,
        'tokens': 0,
        'savedLlmCalls': 0,
        'costUsd': 0.0,
        'savedUsd': 0.0,
        'savedOcrCalls': 0,
      });
    });

    test('flags luôn đủ 10 khóa; flagSet sắp xếp; enabledCount khớp', () {
      final m = _build(
        profile: AiFlagProfileKind.custom,
        flags: {
          AiOptimizationFlag.chatMergeCalls,
          AiOptimizationFlag.chatLocalRouter,
        },
      );
      final flags = m['flags']! as Map<String, bool>;
      expect(flags, hasLength(10));
      expect(flags.keys.toList(), [
        for (final f in AiOptimizationFlag.values) f.key,
      ]);
      expect(flags['ai.chat.merge_calls'], isTrue);
      expect(flags['ai.chat.local_router'], isTrue);
      expect(flags.values.where((v) => v), hasLength(2));
      expect(m['flagSet'], 'ai.chat.local_router,ai.chat.merge_calls');
      expect(m['enabledCount'], 2);
      expect(m['profile'], 'custom');
    });

    test('totals, serverFlagSet và lastExtract', () {
      final m = _build(
        serverFlagSet: 'none',
        totals: const AiLabTotals(
          llmCalls: 12,
          tokens: 18450,
          savedLlmCalls: 9,
          costUsd: 0.5,
          savedUsd: 0.25,
          savedOcrCalls: 1,
        ),
        lastExtract: const AiLabCall(
          action: 'extract',
          durationMs: 7022,
          inputTokens: 2094,
          thinkingTokens: 0,
          outputTokens: 191,
          provider: 'gemini',
        ),
      );
      expect(m['serverFlagSet'], 'none');
      final totals = m['totals']! as Map;
      expect(totals['llmCalls'], 12);
      expect(totals['tokens'], 18450);
      expect(totals['savedUsd'], 0.25);
      expect(m['lastExtract'], {
        'inputTokens': 2094,
        'thinkingTokens': 0,
        'outputTokens': 191,
        'durationMs': 7022,
        'provider': 'gemini',
      });
    });

    test('turns và calls giữ thứ tự và trường protocol, null giữ nguyên', () {
      final m = _build(
        turns: const [
          AiLabTurn(
            messageId: 'a',
            route: AiLabRoute.local,
            llmCalls: 0,
            durationMs: 40,
          ),
          AiLabTurn(
            messageId: 'b',
            route: AiLabRoute.fallback,
            llmCalls: 1,
            durationMs: 900,
            provider: 'gemini',
          ),
        ],
        calls: const [
          AiLabCall(
            action: 'chat',
            durationMs: 2100,
            llmCalls: 1,
            provider: '9router',
            inputTokens: 900,
            outputTokens: 120,
          ),
        ],
      );
      expect(m['turns'], [
        {
          'messageId': 'a',
          'route': 'local',
          'llmCalls': 0,
          'durationMs': 40,
          'provider': null,
        },
        {
          'messageId': 'b',
          'route': 'fallback',
          'llmCalls': 1,
          'durationMs': 900,
          'provider': 'gemini',
        },
      ]);
      expect(m['calls'], [
        {
          'action': 'chat',
          'durationMs': 2100,
          'llmCalls': 1,
          'provider': '9router',
          'failover': false,
          'inputTokens': 900,
          'outputTokens': 120,
          'thinkingTokens': null,
        },
      ]);
    });
  });

  group('AiLabThrottle', () {
    late _FakeScheduler clock;
    late List<int> runTimes;
    late AiLabThrottle throttle;

    setUp(() {
      clock = _FakeScheduler();
      runTimes = [];
      throttle = AiLabThrottle(
        action: () => runTimes.add(clock.now.millisecondsSinceEpoch),
        now: () => clock.now,
        timerFactory: clock.create,
      );
    });

    test('lần đầu chạy ngay', () {
      throttle.request();
      expect(runTimes, [0]);
      expect(clock.timers, isEmpty);
    });

    test('yêu cầu dồn dập trong 250 ms cho đúng một lần chạy cuối (trailing)', () {
      throttle.request();
      clock.advance(10);
      for (var i = 0; i < 20; i++) {
        throttle.request();
      }
      expect(runTimes, [0]);
      expect(clock.timers, hasLength(1));
      expect(clock.timers.single.delay, const Duration(milliseconds: 240));
      clock.advance(240);
      expect(runTimes, [0, 250]);
      expect(throttle.hasPending, isFalse);
    });

    test('yêu cầu liên tục mỗi 10 ms trong 2 s: tối đa 4 lần/giây, có lần cuối', () {
      for (var t = 0; t < 2000; t += 10) {
        throttle.request();
        clock.advance(10);
      }
      // Đúng 250 ms giữa hai lần chạy liên tiếp = 4 lần/giây.
      expect(runTimes.first, 0);
      for (var i = 1; i < runTimes.length; i++) {
        expect(runTimes[i] - runTimes[i - 1], 250);
      }
      // Yêu cầu cuối (t = 1990) được giao bằng lần chạy cuối ở t = 2000.
      expect(runTimes.last, 2000);
      expect(throttle.hasPending, isFalse);
    });

    test('sau khoảng yên lặng 250 ms lại chạy ngay', () {
      throttle.request();
      clock.advance(250);
      throttle.request();
      expect(runTimes, [0, 250]);
      expect(clock.timers, isEmpty);
    });

    test('flush chạy ngay và hủy lượt chờ', () {
      throttle.request();
      clock.advance(5);
      throttle.request();
      expect(throttle.hasPending, isTrue);
      throttle.flush();
      expect(runTimes, [0, 5]);
      expect(throttle.hasPending, isFalse);
      expect(clock.timers.single.cancelled, isTrue);
    });

    test('dispose hủy lượt chờ và không chạy thêm', () {
      throttle.request();
      clock.advance(5);
      throttle.request();
      throttle.dispose();
      expect(clock.timers.single.cancelled, isTrue);
      throttle.request();
      throttle.flush();
      clock.advance(1000);
      expect(runTimes, [0]);
    });

    test('action ném lỗi không làm hỏng throttle', () {
      final bad = AiLabThrottle(
        action: () => throw StateError('x'),
        now: () => clock.now,
      );
      expect(bad.request, returnsNormally);
      expect(bad.flush, returnsNormally);
    });
  });
}
