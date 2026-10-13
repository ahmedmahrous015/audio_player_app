import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../metadata_cache.dart';

/// A vintage vinyl record that spins at 33⅓ rpm while [playing], with a
/// tonearm that lowers onto it when playback starts. Tracks with embedded
/// artwork become a "picture disc" printed edge to edge with the cover; tracks
/// without one get a classic black record.
class VinylRecord extends StatefulWidget {
  final String? path;
  final double size;
  final bool playing;

  const VinylRecord({
    super.key,
    required this.path,
    required this.size,
    required this.playing,
  });

  @override
  State<VinylRecord> createState() => _VinylRecordState();
}

class _VinylRecordState extends State<VinylRecord>
    with SingleTickerProviderStateMixin {
  // 33⅓ revolutions per minute = one turn every 1.8 seconds.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  Uint8List? _cover;
  bool _coverLoaded = false;

  /// The whole record face (grooves, artwork, label) rendered once into a
  /// bitmap. Spinning then only rotates one image per frame instead of
  /// re-drawing hundreds of grooves, which keeps the animation smooth.
  ui.Image? _face;
  Object? _faceKey;
  int _renderToken = 0;

  @override
  void initState() {
    super.initState();
    if (widget.playing) _spin.repeat();
    _loadCover();
  }

  void _loadCover() {
    final path = widget.path;
    _coverLoaded = false;
    if (path == null) {
      _cover = null;
      _coverLoaded = true;
      return;
    }
    final cached = MetadataCache().peek(path);
    if (cached != null) {
      _cover = cached.coverArt;
      _coverLoaded = true;
      return;
    }
    _cover = null;
    MetadataCache().getCoverArt(path).then((bytes) {
      if (!mounted || widget.path != path) return;
      setState(() {
        _cover = bytes;
        _coverLoaded = true;
      });
    });
  }

  @override
  void didUpdateWidget(VinylRecord old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _loadCover();
    if (widget.playing && !_spin.isAnimating) {
      // Resume from the current angle instead of jumping back to zero.
      _spin.repeat();
    } else if (!widget.playing && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _face?.dispose();
    super.dispose();
  }

  void _ensureFace(double disc, double dpr, Color c1, Color c2) {
    if (!_coverLoaded) return;
    final key = (identityHashCode(_cover), disc, dpr, c1, c2);
    if (key == _faceKey) return;
    _faceKey = key;
    final token = ++_renderToken;
    _renderFace(_cover, disc, dpr, [c1, c2]).then((img) {
      if (!mounted || token != _renderToken) {
        img?.dispose();
        return;
      }
      final old = _face;
      setState(() => _face = img);
      // The outgoing RawImage may still be cross-fading; free it afterwards.
      if (old != null) {
        Future.delayed(const Duration(seconds: 1), old.dispose);
      }
    });
  }

  static Future<ui.Image?> _renderFace(
    Uint8List? cover,
    double disc,
    double dpr,
    List<Color> labelColors,
  ) async {
    final px = (disc * dpr).round();
    if (px <= 0) return null;
    ui.Image? art;
    if (cover != null) {
      try {
        final codec = await ui.instantiateImageCodec(cover, targetWidth: px);
        art = (await codec.getNextFrame()).image;
        codec.dispose();
      } catch (_) {}
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(dpr);
    final size = Size.square(disc);
    final c = size.center(Offset.zero);
    final r = disc / 2;

    if (art != null) {
      // Picture disc: artwork printed edge to edge (centre-cropped).
      final w = art.width.toDouble(), h = art.height.toDouble();
      final side = math.min(w, h);
      final src = Rect.fromLTWH((w - side) / 2, (h - side) / 2, side, side);
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
      canvas.drawImageRect(
        art,
        src,
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
      art.dispose();
      const _PictureDiscPainter().paint(canvas, size);
      final hub = disc * 0.085;
      canvas.drawCircle(c, hub, Paint()..color = const Color(0xC7000000));
      canvas.drawCircle(
        c,
        hub,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.25),
      );
    } else {
      // Classic black record with a gradient label and a note, like the
      // app's artwork placeholder.
      const _VinylPainter().paint(canvas, size);
      final lr = disc * 0.19;
      final labelRect = Rect.fromCircle(center: c, radius: lr);
      canvas.drawCircle(
        c,
        lr,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: labelColors,
          ).createShader(labelRect),
      );
      canvas.drawCircle(
        c,
        lr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.black.withValues(alpha: 0.6),
      );
      const icon = Icons.music_note_rounded;
      final note = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: lr * 0.85,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      note.paint(canvas, c + Offset(-note.width / 2, -note.height / 2));
      note.dispose();
    }

    // Spindle hole.
    final sr = disc * 0.019;
    canvas.drawCircle(c, sr, Paint()..color = const Color(0xFF0D0D0D));
    canvas.drawCircle(
      c,
      sr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.5),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(px, px);
    picture.dispose();
    return image;
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final disc = size * 0.92;
    final cs = Theme.of(context).colorScheme;
    _ensureFace(
      disc,
      MediaQuery.devicePixelRatioOf(context),
      cs.primary,
      cs.tertiary,
    );
    final face = _face;

    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft drop shadow under the record.
          Container(
            width: disc,
            height: disc,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF141414),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 40,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
          ),
          RotationTransition(
            turns: _spin,
            child: SizedBox.square(
              dimension: disc,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: face == null
                    ? const SizedBox.shrink()
                    : RawImage(
                        key: ValueKey(face),
                        image: face,
                        width: disc,
                        height: disc,
                        filterQuality: FilterQuality.medium,
                      ),
              ),
            ),
          ),
          // Light reflections stay still while the disc turns underneath,
          // which is what makes the spinning read as real.
          IgnorePointer(
            child: SizedBox.square(
              dimension: disc,
              child: const CustomPaint(painter: _SheenPainter()),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: widget.playing ? 0.0 : -0.34),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeInOutCubic,
                builder: (_, angle, _) =>
                    CustomPaint(painter: _TonearmPainter(angle: angle)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Translucent grooves, rim and edge shading printed over the artwork of a
/// picture disc so it still reads as vinyl.
class _PictureDiscPainter extends CustomPainter {
  const _PictureDiscPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r);

    // Darken towards the edge, like light falling off a curved surface.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.black.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.12),
            Colors.black.withValues(alpha: 0.42),
          ],
          stops: const [0.0, 0.7, 1.0],
        ).createShader(rect),
    );

    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    var i = 0;
    for (var gr = r * 0.2; gr < r * 0.965; gr += 2.2, i++) {
      groove.color = i.isEven
          ? Colors.black.withValues(alpha: 0.10)
          : Colors.white.withValues(alpha: 0.05);
      canvas.drawCircle(c, gr, groove);
    }

    final gap = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = Colors.black.withValues(alpha: 0.22);
    for (final t in [0.45, 0.6, 0.74, 0.87]) {
      canvas.drawCircle(c, r * t, gap);
    }

    canvas.drawCircle(
      c,
      r * 0.985,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.03
        ..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawCircle(
      c,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.18),
    );
  }

  @override
  bool shouldRepaint(_PictureDiscPainter oldDelegate) => false;
}

class _VinylPainter extends CustomPainter {
  const _VinylPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    // Base: near-black vinyl with a faint radial depth.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF242424), Color(0xFF0E0E0E), Color(0xFF171717)],
          stops: [0.0, 0.7, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Grooves.
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    final inner = r * 0.42;
    final outer = r * 0.965;
    var i = 0;
    for (var gr = inner; gr < outer; gr += 1.6, i++) {
      groove.color = Colors.white.withValues(alpha: i.isEven ? 0.045 : 0.02);
      canvas.drawCircle(c, gr, groove);
    }

    // Track gaps: slightly glossier bands between "songs".
    final gap = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = Colors.black.withValues(alpha: 0.55);
    for (final t in [0.55, 0.68, 0.8, 0.9]) {
      canvas.drawCircle(c, r * t, gap);
    }

    // Lead-in rim and edge.
    canvas.drawCircle(
      c,
      r * 0.985,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.03
        ..color = const Color(0xFF1E1E1E),
    );
    canvas.drawCircle(
      c,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.12),
    );
  }

  @override
  bool shouldRepaint(_VinylPainter oldDelegate) => false;
}

/// Two opposing light wedges, like a lamp reflecting off the grooves.
class _SheenPainter extends CustomPainter {
  const _SheenPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    final clear = Colors.white.withValues(alpha: 0);
    final glint = Colors.white.withValues(alpha: 0.13);

    final paint = Paint()
      ..shader = SweepGradient(
        colors: [clear, glint, clear, clear, glint, clear, clear],
        stops: const [0.0, 0.08, 0.17, 0.5, 0.58, 0.67, 1.0],
        transform: const GradientRotation(-math.pi / 3),
      ).createShader(rect);

    // Only over the grooved area, not the label.
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(rect)
      ..addOval(Rect.fromCircle(center: c, radius: r * 0.4));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SheenPainter oldDelegate) => false;
}

/// Turntable arm pivoting at the top-right; [angle] 0 rests the stylus on
/// the record, negative values swing it off to the side.
class _TonearmPainter extends CustomPainter {
  final double angle;

  const _TonearmPainter({required this.angle});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final pivot = Offset(size.width * 0.95, size.height * 0.07);

    canvas.save();
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(angle);

    // Arm from the pivot down to the headshell (stylus lands on the outer
    // grooves when angle == 0).
    final stylus = Offset(-s * 0.2, s * 0.55);
    final armPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.022
      ..shader = const LinearGradient(
        colors: [Color(0xFFF5F5F7), Color(0xFF9A9AA0), Color(0xFFE5E5EA)],
      ).createShader(Rect.fromPoints(Offset.zero, stylus));

    // Shadow cast onto the record.
    canvas.drawLine(
      const Offset(4, 8),
      stylus + const Offset(4, 8),
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = s * 0.022
        ..color = Colors.black.withValues(alpha: 0.22),
    );
    canvas.drawLine(Offset.zero, stylus, armPaint);

    // Counterweight behind the pivot.
    final back = Offset(-stylus.dx, -stylus.dy) * 0.16;
    canvas.drawLine(
      Offset.zero,
      back,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = s * 0.05
        ..color = const Color(0xFF3A3A3C),
    );

    // Headshell, aligned with the arm.
    canvas.save();
    canvas.translate(stylus.dx, stylus.dy);
    canvas.rotate(math.atan2(stylus.dy, stylus.dx) - math.pi / 2);
    final head = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: s * 0.06, height: s * 0.1),
      Radius.circular(s * 0.012),
    );
    canvas.drawRRect(head, Paint()..color = const Color(0xFF2C2C2E));
    canvas.drawRRect(
      head,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.25),
    );
    canvas.restore();

    canvas.restore();

    // Pivot base (does not rotate).
    final baseR = s * 0.055;
    canvas.drawCircle(
      pivot,
      baseR,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFE5E5EA), Color(0xFF636366)],
        ).createShader(Rect.fromCircle(center: pivot, radius: baseR)),
    );
    canvas.drawCircle(
      pivot,
      baseR * 0.35,
      Paint()..color = const Color(0xFF2C2C2E),
    );
  }

  @override
  bool shouldRepaint(_TonearmPainter old) => old.angle != angle;
}
