import 'package:flutter/material.dart';
import '../audio_manager.dart';
import '../metadata_cache.dart';
import '../utils/format_utils.dart';
import '../utils/song_actions.dart';
import 'animated_equalizer.dart';
import 'cover_art.dart';
import 'glass.dart';

class SongCard extends StatefulWidget {
  final String name;
  final String filePath;
  final VoidCallback onTap;
  final bool isActive;

  /// Long-press handler; when null, long-press opens the options sheet.
  final VoidCallback? onLongPress;

  /// Multi-select mode: shows a check circle instead of the ⋯ button.
  final bool selectionMode;
  final bool selected;

  const SongCard({
    super.key,
    required this.name,
    required this.filePath,
    required this.onTap,
    this.isActive = false,
    this.onLongPress,
    this.selectionMode = false,
    this.selected = false,
  });

  @override
  State<SongCard> createState() => _SongCardState();
}

class _SongCardState extends State<SongCard> {
  Duration? _duration;
  int? _fileSize;

  @override
  void initState() {
    super.initState();
    _loadMetadataInfo();
  }

  @override
  void didUpdateWidget(SongCard old) {
    super.didUpdateWidget(old);
    if (old.filePath != widget.filePath) {
      _duration = null;
      _fileSize = null;
      _loadMetadataInfo();
    }
  }

  void _loadMetadataInfo() {
    final path = widget.filePath;
    final cached = MetadataCache().peek(path);
    if (cached != null) {
      _duration = cached.duration;
      _fileSize = cached.fileSize;
      return;
    }
    MetadataCache().getMetadataInfo(path).then((info) {
      if (!mounted || widget.filePath != path) return;
      setState(() {
        _duration = info.duration;
        _fileSize = info.fileSize;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isActive = widget.isActive;
    final subtitle = [
      if (_duration != null) formatDuration(_duration),
      if (_fileSize != null) formatSize(_fileSize!),
    ].join(' • ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassTile(
        highlighted: isActive || widget.selected,
        onTap: widget.onTap,
        onLongPress:
            widget.onLongPress ??
            () => showSongOptions(context, widget.filePath),
        padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 6, 8),
        child: Row(
          children: [
            CoverArt(path: widget.filePath, size: 52, borderRadius: 14),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isActive ? cs.primary : cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    // "01:20 • 517.5 KB" must not be reordered by Arabic bidi.
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            if (isActive)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: StreamBuilder<bool>(
                  stream: AudioManager().player.playingStream,
                  initialData: AudioManager().player.playing,
                  builder: (_, snap) =>
                      AnimatedEqualizer(playing: snap.data ?? false),
                ),
              ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: widget.selectionMode
                  ? _SelectionCheck(
                      key: const ValueKey('check'),
                      selected: widget.selected,
                    )
                  : GlassIconButton(
                      key: const ValueKey('more'),
                      icon: Icons.more_horiz_rounded,
                      size: 36,
                      blur: 0,
                      shadow: false,
                      iconColor: cs.onSurfaceVariant,
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).showMenuTooltip,
                      onPressed: () =>
                          showSongOptions(context, widget.filePath),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round check mark shown on each row while selecting.
class _SelectionCheck extends StatelessWidget {
  final bool selected;

  const _SelectionCheck({super.key, required this.selected});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 36,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? cs.primary : Colors.transparent,
            border: Border.all(
              color: selected ? cs.primary : cs.onSurfaceVariant,
              width: 2,
            ),
          ),
          child: selected
              ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}
