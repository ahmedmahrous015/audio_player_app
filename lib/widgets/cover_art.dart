import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../metadata_cache.dart';
import 'fallback_icon.dart';

/// Embedded artwork for [path], decoded at display size (not full
/// resolution) to keep memory low in long lists.
class CoverArt extends StatefulWidget {
  final String? path;
  final double size;
  final double borderRadius;
  final double? iconSize;

  const CoverArt({
    super.key,
    required this.path,
    this.size = 44,
    this.borderRadius = 14,
    this.iconSize,
  });

  @override
  State<CoverArt> createState() => _CoverArtState();
}

class _CoverArtState extends State<CoverArt> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CoverArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _load();
  }

  void _load() {
    final path = widget.path;
    if (path == null) {
      _bytes = null;
      return;
    }
    final cached = MetadataCache().peek(path);
    if (cached != null) {
      _bytes = cached.coverArt;
      return;
    }
    _bytes = null;
    MetadataCache().getCoverArt(path).then((bytes) {
      if (mounted && widget.path == path) setState(() => _bytes = bytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final fallback = FallbackIcon(
      size: size,
      iconSize: widget.iconSize ?? size / 2,
      borderRadius: widget.borderRadius,
    );
    final bytes = _bytes;
    final cachePx = (size * MediaQuery.devicePixelRatioOf(context)).round();

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: bytes == null
              ? KeyedSubtree(key: const ValueKey('fallback'), child: fallback)
              : Image.memory(
                  bytes,
                  key: ValueKey(widget.path),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  cacheWidth: cachePx,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}
