import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Loudness samples for [VoiceWaveform]. Unlike [ValueNotifier] it notifies on
/// every sample, so repeated equal values (steady silence) keep scrolling.
class VoiceLevelSamples extends ChangeNotifier
    implements ValueListenable<double> {
  double _value = 0;

  @override
  double get value => _value;

  void add(double level) {
    _value = level;
    notifyListeners();
  }
}

/// Scrolling loudness bars shown while the assistant is listening.
///
/// Every new [level] sample (normalised 0–1) slides in as a bar on the right.
class VoiceWaveform extends StatefulWidget {
  const VoiceWaveform({
    required this.level,
    required this.color,
    this.height = 24,
    this.barCount = 32,
    this.sampleInterval = const Duration(milliseconds: 200),
    super.key,
  });

  final ValueListenable<double> level;
  final Color color;
  final double height;
  final int barCount;

  /// Expected time between samples; each bar scrolls in over this duration.
  final Duration sampleInterval;

  @override
  State<VoiceWaveform> createState() => _VoiceWaveformState();
}

class _VoiceWaveformState extends State<VoiceWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scroll = AnimationController(
    vsync: this,
    duration: widget.sampleInterval,
    value: 1,
  );
  late List<double> _history = List.filled(widget.barCount, 0);

  @override
  void initState() {
    super.initState();
    widget.level.addListener(_onLevel);
  }

  @override
  void didUpdateWidget(VoiceWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.barCount != widget.barCount) {
      _history = List.filled(widget.barCount, 0);
    }
    _scroll.duration = widget.sampleInterval;
    if (oldWidget.level != widget.level) {
      oldWidget.level.removeListener(_onLevel);
      widget.level.addListener(_onLevel);
    }
  }

  void _onLevel() {
    if (!mounted) return;
    setState(() {
      _history = [..._history.skip(1), widget.level.value.clamp(0.0, 1.0)];
    });
    _scroll.forward(from: 0);
  }

  @override
  void dispose() {
    widget.level.removeListener(_onLevel);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _scroll,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _WaveformPainter(
            levels: _history,
            progress: _scroll.value,
            color: widget.color,
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.levels,
    required this.progress,
    required this.color,
  });

  final List<double> levels;

  /// 0 right after a sample arrives, 1 once its bar has fully slid in.
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty || size.width <= 0) return;
    final slot = size.width / levels.length;
    final barWidth = math.max(2.0, slot * 0.5);
    final minHeight = barWidth;
    final centerY = size.height / 2;
    final offset = (1 - progress) * slot;
    final paint = Paint()..color = color;

    for (var i = 0; i < levels.length; i++) {
      final x = i * slot + (slot - barWidth) / 2 + offset;
      if (x + barWidth > size.width) continue;
      final height = minHeight + (size.height - minHeight) * levels[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, centerY - height / 2, barWidth, height),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      !identical(oldDelegate.levels, levels) ||
      oldDelegate.progress != progress ||
      oldDelegate.color != color;
}
