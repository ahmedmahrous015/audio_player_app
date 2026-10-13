import 'package:flutter/material.dart';

class FallbackIcon extends StatelessWidget {
  final double size;
  final double iconSize;
  final double borderRadius;

  const FallbackIcon({
    super.key,
    this.size = 44,
    this.iconSize = 22,
    this.borderRadius = 14,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, cs.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: iconSize,
        color: cs.onPrimary,
      ),
    );
  }
}
