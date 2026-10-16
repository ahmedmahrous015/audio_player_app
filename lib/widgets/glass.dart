import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// "Liquid glass" building blocks: translucent, blurred surfaces with a soft
/// specular rim, in the spirit of the latest iOS design language.
///
/// Performance notes (measured on device): a live backdrop blur is by far the
/// most expensive effect, so surfaces over scrolling content pause their blur
/// while a list moves, list rows use a clip-free "lite" glass, and the
/// ambient glow is rendered once into a bitmap.

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// Default translucent fill for glass on the current theme.
Color glassFill(BuildContext context) => _isDark(context)
    ? Colors.white.withValues(alpha: 0.10)
    : Colors.white.withValues(alpha: 0.58);

/// Fill used instead of a live blur while content scrolls underneath.
Color _scrollingFill(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  return _isDark(context)
      ? Color.alphaBlend(
          Colors.white.withValues(alpha: 0.08),
          cs.surface.withValues(alpha: 0.86),
        )
      : cs.surface.withValues(alpha: 0.92);
}

/// True while any watched list is scrolling.
final ValueNotifier<bool> glassScrolling = ValueNotifier<bool>(false);

/// Reports scrolling of the lists below it to [glassScrolling], so live blurs
/// can pause during motion (when they cost the most and are least visible).
class GlassScrollWatcher extends StatefulWidget {
  final Widget child;

  const GlassScrollWatcher({super.key, required this.child});

  @override
  State<GlassScrollWatcher> createState() => _GlassScrollWatcherState();
}

class _GlassScrollWatcherState extends State<GlassScrollWatcher> {
  Timer? _settle;

  @override
  void dispose() {
    _settle?.cancel();
    glassScrolling.value = false;
    super.dispose();
  }

  bool _onNotification(ScrollNotification n) {
    if (n is ScrollStartNotification) {
      _settle?.cancel();
      glassScrolling.value = true;
    } else if (n is ScrollEndNotification) {
      _settle?.cancel();
      _settle = Timer(const Duration(milliseconds: 150), () {
        glassScrolling.value = false;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onNotification,
      child: widget.child,
    );
  }
}

class GlassSurface extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final bool circle;

  /// Backdrop blur sigma. Use 0 for items inside scrolling lists, where a
  /// per-row backdrop blur would be too expensive.
  final double blur;

  /// Swap the live blur for an opaque-ish tint while [glassScrolling].
  final bool pauseBlurWhileScrolling;
  final Color? tint;

  /// Coloured glass: replaces the flat [tint] with a translucent gradient.
  final Gradient? gradient;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final bool shadow;

  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.circle = false,
    this.blur = 20,
    this.pauseBlurWhileScrolling = false,
    this.tint,
    this.gradient,
    this.width,
    this.height,
    this.padding,
    this.shadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    final shape = circle ? BoxShape.circle : BoxShape.rectangle;
    final radius = circle ? null : borderRadius;
    final inner = padding != null
        ? Padding(padding: padding!, child: child)
        : child;

    // Lite glass for list rows: one decorated box (fill + sheen gradient +
    // hairline rim), no clip layer and no custom painting.
    if (blur == 0 && !shadow) {
      final fill = tint ?? glassFill(context);
      return SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: shape,
            borderRadius: radius,
            gradient:
                gradient ??
                LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(
                      Colors.white.withValues(alpha: dark ? 0.07 : 0.25),
                      fill,
                    ),
                    fill,
                  ],
                  stops: const [0.0, 0.55],
                ),
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? 0.14 : 0.7),
              width: 0.8,
            ),
          ),
          child: inner,
        ),
      );
    }

    Widget glass(Color? fillOverride, {required bool liveBlur}) {
      Widget content = CustomPaint(
        foregroundPainter: _GlassRimPainter(
          circle: circle,
          borderRadius: borderRadius,
          dark: dark,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: gradient == null
                ? (fillOverride ?? tint ?? glassFill(context))
                : null,
            gradient: gradient,
            shape: shape,
            borderRadius: radius,
          ),
          child: inner,
        ),
      );
      if (blur > 0) {
        // Grouped: every glass surface under the same [BackdropGroup] (one
        // per page) shares a single read of the screen instead of one each.
        // Pausing toggles `enabled` rather than removing the widget, so the
        // tree shape never changes and the content (e.g. the mini player's
        // play button) is not torn down and rebuilt at every scroll.
        content = BackdropFilter.grouped(
          enabled: liveBlur,
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: content,
        );
      }
      return circle
          ? ClipOval(child: content)
          : ClipRRect(borderRadius: borderRadius, child: content);
    }

    final Widget body = blur > 0 && pauseBlurWhileScrolling
        ? ValueListenableBuilder<bool>(
            valueListenable: glassScrolling,
            builder: (context, scrolling, _) => scrolling
                ? glass(_scrollingFill(context), liveBlur: false)
                : glass(null, liveBlur: true),
          )
        : glass(null, liveBlur: blur > 0);

    return Container(
      width: width,
      height: height,
      decoration: shadow
          ? BoxDecoration(
              shape: shape,
              borderRadius: radius,
              boxShadow: [
                // BlurStyle.normal has an analytic fast path in Impeller
                // (BlurStyle.outer fell back to a full Gaussian pass).
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.22 : 0.07),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            )
          : null,
      child: body,
    );
  }
}

/// Paints the glossy top sheen and the light-catching rim.
class _GlassRimPainter extends CustomPainter {
  final bool circle;
  final BorderRadius borderRadius;
  final bool dark;

  _GlassRimPainter({
    required this.circle,
    required this.borderRadius,
    required this.dark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = circle
        ? RRect.fromRectAndRadius(rect, Radius.circular(size.shortestSide / 2))
        : borderRadius.toRRect(rect);

    // Soft highlight across the upper half (an rrect fill, no clip needed).
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [
            Colors.white.withValues(alpha: dark ? 0.10 : 0.35),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );

    // Rim: brighter where light hits (top-start), fading towards the bottom.
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: dark ? 0.40 : 0.90),
          Colors.white.withValues(alpha: dark ? 0.06 : 0.25),
          Colors.white.withValues(alpha: dark ? 0.18 : 0.55),
        ],
        stops: const [0.0, 0.6, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect.deflate(0.5), rim);
  }

  @override
  bool shouldRepaint(_GlassRimPainter old) =>
      old.circle != circle ||
      old.borderRadius != borderRadius ||
      old.dark != dark;
}

/// Round, translucent icon button that shrinks slightly while pressed.
class GlassIconButton extends StatefulWidget {
  final IconData? icon;
  final Widget? child;
  final VoidCallback? onPressed;
  final double size;
  final double? iconSize;
  final String? tooltip;
  final bool selected;
  final Color? iconColor;
  final Color? tint;
  final Gradient? gradient;
  final double blur;
  final bool shadow;

  const GlassIconButton({
    super.key,
    this.icon,
    this.child,
    required this.onPressed,
    this.size = 44,
    this.iconSize,
    this.tooltip,
    this.selected = false,
    this.iconColor,
    this.tint,
    this.gradient,
    this.blur = 16,
    this.shadow = true,
  }) : assert(icon != null || child != null);

  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = widget.onPressed != null;
    var color =
        widget.iconColor ?? (widget.selected ? cs.primary : cs.onSurface);
    if (!enabled) color = color.withValues(alpha: 0.35);
    final tint =
        widget.tint ??
        (widget.selected
            ? cs.primary.withValues(alpha: _isDark(context) ? 0.28 : 0.16)
            : null);

    Widget button = AnimatedScale(
      scale: _pressed ? 0.88 : 1.0,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: GlassSurface(
        circle: true,
        blur: widget.blur,
        tint: tint,
        gradient: widget.gradient,
        shadow: widget.shadow,
        width: widget.size,
        height: widget.size,
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onPressed,
            onHighlightChanged: enabled
                ? (v) => setState(() => _pressed = v)
                : null,
            child: Center(
              child: IconTheme.merge(
                data: IconThemeData(
                  color: color,
                  size: widget.iconSize ?? widget.size * 0.48,
                ),
                child: widget.child ?? Icon(widget.icon),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      child: button,
    );
  }
}

/// Glass list row (no backdrop blur, for use inside scrolling lists).
class GlassTile extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool highlighted;
  final EdgeInsetsGeometry padding;

  const GlassTile({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.highlighted = false,
    this.padding = const EdgeInsets.all(10),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(Radius.circular(20));
    return GlassSurface(
      blur: 0,
      shadow: false,
      borderRadius: radius,
      tint: highlighted
          ? cs.primary.withValues(alpha: _isDark(context) ? 0.22 : 0.12)
          : null,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Frosted navigation-bar background for an [AppBar.flexibleSpace].
class GlassBarBackground extends StatelessWidget {
  const GlassBarBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final border = Border(
      bottom: BorderSide(
        color: cs.onSurface.withValues(alpha: 0.06),
        width: 0.5,
      ),
    );
    // Without a child the box sizes to zero under the app bar's loose
    // constraints and nothing (neither blur nor tint) gets painted.
    const fill = SizedBox.expand();
    return ValueListenableBuilder<bool>(
      valueListenable: glassScrolling,
      builder: (context, scrolling, _) {
        return ClipRect(
          child: BackdropFilter.grouped(
            enabled: !scrolling,
            filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scrolling
                    ? _scrollingFill(context)
                    : cs.surface.withValues(alpha: 0.62),
                border: border,
              ),
              child: fill,
            ),
          ),
        );
      },
    );
  }
}

/// Soft colour glow behind the content so the glass has something to refract.
///
/// Rendered once into a half-resolution bitmap (the glow is soft, so the
/// upscale is invisible); per frame it is then a single image draw instead of
/// four screen-sized gradient fills.
class AmbientBackground extends StatefulWidget {
  final double intensity;

  const AmbientBackground({super.key, this.intensity = 1});

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground> {
  ui.Image? _image;
  Object? _key;

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  ui.Image _render(Size screen, ColorScheme cs, bool dark, bool rtl) {
    const scale = 0.5;
    final w = screen.width, h = screen.height;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    canvas.drawRect(Offset.zero & screen, Paint()..color = cs.surface);

    final a = (dark ? 0.38 : 0.26) * widget.intensity;
    // (colour, size, top, start-or-end offset, anchored at end?)
    final blobs = <(Color, double, double, double, bool)>[
      (cs.primary.withValues(alpha: a), w * 1.25, -w * 0.5, -w * 0.4, false),
      (
        cs.tertiary.withValues(alpha: a * 0.95),
        w * 1.1,
        -w * 0.15,
        -w * 0.55,
        true,
      ),
      (
        cs.secondary.withValues(alpha: a * 0.6),
        w * 1.2,
        w * 0.9,
        -w * 0.6,
        false,
      ),
      (
        cs.tertiary.withValues(alpha: a * 0.55),
        w * 1.2,
        h + w * 0.55 - w * 1.2,
        -w * 0.3,
        true,
      ),
    ];
    for (final (color, size, top, offset, atEnd) in blobs) {
      final fromLeft = atEnd != rtl;
      final left = fromLeft ? offset : w - offset - size;
      final rect = Rect.fromLTWH(left, top, size, size);
      canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ).createShader(rect),
      );
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      (w * scale).ceil().clamp(1, 4096),
      (h * scale).ceil().clamp(1, 4096),
    );
    picture.dispose();
    return image;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = _isDark(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // Screen size, not the (keyboard-shrinkable) layout size, so the bitmap
    // isn't re-rendered on every frame of the keyboard animation.
    final screen = MediaQuery.sizeOf(context);
    final key = (screen, cs.surface, cs.primary, cs.tertiary, dark, rtl);
    if (key != _key || _image == null) {
      final old = _image;
      _image = _render(screen, cs, dark, rtl);
      _key = key;
      if (old != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
    }
    return IgnorePointer(
      child: ColoredBox(
        color: cs.surface,
        // Always fill the available space: under loose constraints (e.g.
        // inside an AnimatedSwitcher) a bare RawImage shrinks to the bitmap's
        // own size and shows up as a rectangle.
        child: SizedBox.expand(
          child: RawImage(
            image: _image,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}
