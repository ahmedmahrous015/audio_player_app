import 'dart:math';
import 'package:flutter/material.dart';

class AnimatedEqualizer extends StatefulWidget {
  final bool playing;

  const AnimatedEqualizer({super.key, this.playing = true});

  @override
  State<AnimatedEqualizer> createState() => _AnimatedEqualizerState();
}

class _AnimatedEqualizerState extends State<AnimatedEqualizer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    if (widget.playing) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(AnimatedEqualizer old) {
    super.didUpdateWidget(old);
    if (widget.playing && !old.playing) {
      _controller.repeat(reverse: true);
    } else if (!widget.playing && old.playing) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, _) => CustomPaint(
        size: const Size(28, 28),
        painter: _EqualizerPainter(
          color: cs.primary,
          progress: _controller.value,
        ),
      ),
    );
  }
}

class _EqualizerPainter extends CustomPainter {
  final Color color;
  final double progress;

  _EqualizerPainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.5;

    final bars = 4;
    final totalWidth = size.width;
    const spacing = 2.0;
    final barWidth = (totalWidth - spacing * (bars - 1)) / bars;

    for (var i = 0; i < bars; i++) {
      final x = i * (barWidth + spacing) + barWidth / 2;
      final maxH = size.height * 0.85;
      final minH = size.height * 0.25;

      final phase = (i / bars) * 2 * 3.14159;
      final normalized = (progress * 2 * 3.14159 + phase);
      final sinVal = sin(normalized);
      final h = ((sinVal + 1) / 2) * (maxH - minH) + minH;

      final top = (size.height - h) / 2;
      canvas.drawLine(Offset(x, top), Offset(x, top + h), paint);
    }
  }

  @override
  bool shouldRepaint(_EqualizerPainter old) => old.progress != progress;
}
