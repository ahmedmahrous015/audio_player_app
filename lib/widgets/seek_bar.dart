import 'package:flutter/material.dart';
import '../audio_manager.dart';
import '../utils/format_utils.dart';

/// iOS-style scrubber: a thin bar without a thumb that thickens while
/// dragging. It only moves locally during the drag and seeks once on release,
/// instead of flooding the player with seeks and fighting live updates.
class SeekBar extends StatefulWidget {
  final Color activeColor;
  final Color inactiveColor;
  final TextStyle? labelStyle;
  final EdgeInsetsGeometry padding;

  const SeekBar({
    super.key,
    required this.activeColor,
    required this.inactiveColor,
    this.labelStyle,
    this.padding = const EdgeInsets.symmetric(horizontal: 28),
  });

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final player = AudioManager().player;
    return StreamBuilder<Duration?>(
      stream: player.durationStream,
      initialData: player.duration,
      builder: (context, durSnap) {
        final dur = durSnap.data;
        final totalMs = dur?.inMilliseconds ?? 0;
        return StreamBuilder<Duration>(
          stream: player.positionStream,
          initialData: player.position,
          builder: (context, posSnap) {
            final pos = posSnap.data ?? Duration.zero;
            final progress = totalMs > 0
                ? (pos.inMilliseconds / totalMs).clamp(0.0, 1.0)
                : 0.0;
            final drag = _dragValue;
            final dragging = drag != null;
            final shownPos = dragging && dur != null ? dur * drag : pos;
            final remaining = dur != null && dur > shownPos
                ? dur - shownPos
                : Duration.zero;

            // Timelines run left-to-right even in RTL locales.
            return Directionality(
              textDirection: TextDirection.ltr,
              child: Padding(
                padding: widget.padding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 28,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: dragging ? 12 : 6,
                          trackShape: const _FullWidthTrackShape(),
                          thumbShape: SliderComponentShape.noThumb,
                          overlayShape: SliderComponentShape.noOverlay,
                          activeTrackColor: widget.activeColor,
                          inactiveTrackColor: widget.inactiveColor,
                        ),
                        child: Slider(
                          value: drag ?? progress,
                          onChanged: totalMs > 0
                              ? (v) => setState(() => _dragValue = v)
                              : null,
                          onChangeEnd: (v) {
                            if (dur != null) player.seek(dur * v);
                            setState(() => _dragValue = null);
                          },
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          formatDuration(shownPos),
                          style: widget.labelStyle,
                        ),
                        Text(
                          dur != null
                              ? '-${formatDuration(remaining)}'
                              : '--:--',
                          style: widget.labelStyle,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Rounded track that spans the full width (no thumb/overlay insets).
class _FullWidthTrackShape extends RoundedRectSliderTrackShape {
  const _FullWidthTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final height = sliderTheme.trackHeight ?? 6;
    final top = offset.dy + (parentBox.size.height - height) / 2;
    return Rect.fromLTWH(offset.dx, top, parentBox.size.width, height);
  }
}
