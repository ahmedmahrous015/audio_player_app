import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../audio_manager.dart';
import '../l10n/app_localizations.dart';
import '../metadata_cache.dart';
import '../utils/format_utils.dart';
import '../utils/song_actions.dart';
import 'cover_art.dart';
import 'glass.dart';

/// Floating frosted-glass capsule showing the current track.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final manager = AudioManager();
    const radius = BorderRadius.all(Radius.circular(28));

    return ValueListenableBuilder<String?>(
      valueListenable: manager.currentPath,
      builder: (context, path, _) {
        if (path == null) return const SizedBox.shrink();

        return GlassSurface(
          borderRadius: radius,
          blur: 30,
          pauseBlurWhileScrolling: true,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              onTap: () => openPlayerPage(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 4, 4),
                    child: Row(
                      children: [
                        CoverArt(path: path, size: 44, borderRadius: 12),
                        const SizedBox(width: 12),
                        Expanded(child: _TrackTitle(path: path)),
                        // Transport controls keep left-to-right order
                        // (previous, play, next) even in Arabic.
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          textDirection: TextDirection.ltr,
                          children: [
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: l10n.previous,
                              icon: Icon(
                                Icons.skip_previous_rounded,
                                color: cs.onSurface,
                                size: 28,
                              ),
                              onPressed: manager.skipToPrevious,
                            ),
                            StreamBuilder<PlayerState>(
                              stream: manager.player.playerStateStream,
                              initialData: manager.player.playerState,
                              builder: (context, snap) {
                                final isPlaying = isActuallyPlaying(snap.data);
                                return IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: isPlaying ? l10n.pause : l10n.play,
                                  icon: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    transitionBuilder: (child, a) =>
                                        ScaleTransition(scale: a, child: child),
                                    child: Icon(
                                      isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      key: ValueKey(isPlaying),
                                      color: cs.onSurface,
                                      size: 32,
                                    ),
                                  ),
                                  onPressed: isPlaying
                                      ? manager.player.pause
                                      : manager.resume,
                                );
                              },
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: l10n.next,
                              icon: Icon(
                                Icons.skip_next_rounded,
                                color: cs.onSurface,
                                size: 28,
                              ),
                              onPressed: manager.player.seekToNext,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: _ThinProgress(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TrackTitle extends StatelessWidget {
  final String path;

  const _TrackTitle({required this.path});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatName(path),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        FutureBuilder<String>(
          key: ValueKey(path),
          future: MetadataCache().getArtist(path),
          initialData: MetadataCache().getCachedArtist(path) ?? '',
          builder: (_, snap) {
            final artist = snap.data ?? '';
            if (artist.isEmpty) return const SizedBox();
            return Text(
              artist,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          },
        ),
      ],
    );
  }
}

/// Elapsed time, hairline progress bar and total duration along the bottom
/// of the capsule.
class _ThinProgress extends StatelessWidget {
  const _ThinProgress();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final player = AudioManager().player;
    final timeStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: cs.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return StreamBuilder<Duration?>(
      stream: player.durationStream,
      initialData: player.duration,
      builder: (context, durSnap) {
        final dur = durSnap.data;
        return StreamBuilder<Duration>(
          stream: player.positionStream,
          initialData: player.position,
          builder: (context, snap) {
            final total = dur?.inMilliseconds ?? 0;
            final position = snap.data ?? Duration.zero;
            final progress = total > 0
                ? (position.inMilliseconds / total).clamp(0.0, 1.0)
                : 0.0;
            // Timeline: left-to-right regardless of locale.
            return Row(
              textDirection: TextDirection.ltr,
              children: [
                Text(formatDuration(position), style: timeStyle),
                const SizedBox(width: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      height: 3,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(
                            color: cs.onSurface.withValues(alpha: 0.12),
                          ),
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: progress,
                            child: ColoredBox(color: cs.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  dur != null ? formatDuration(dur) : '--:--',
                  style: timeStyle,
                ),
              ],
            );
          },
        );
      },
    );
  }
}
