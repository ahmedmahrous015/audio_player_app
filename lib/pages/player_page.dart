import 'dart:async';
import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../audio_manager.dart';
import '../l10n/app_localizations.dart';
import '../metadata_cache.dart';
import '../smooth_page_route.dart';
import '../theme/app_theme.dart';
import '../utils/app_messenger.dart';
import '../utils/format_utils.dart';
import '../utils/song_actions.dart';
import '../widgets/glass.dart';
import '../widgets/cover_art.dart';
import '../widgets/empty_view.dart';
import '../widgets/glass_sheet.dart';
import '../widgets/seek_bar.dart';
import '../widgets/vinyl_record.dart';
import 'folder_songs_page.dart';

const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

String _speedLabel(double s) {
  final text = s.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return '${text}x';
}

enum _MenuAction { delete, ringtone, sleep, speed, queue, details, share }

/// Right-hand (start-side in RTL) panel of the wide layout: the embedded
/// player, or a placeholder until something is played.
class NowPlayingPanel extends StatelessWidget {
  const NowPlayingPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: AudioManager().currentPath,
      builder: (context, path, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: path == null
            ? GlassMessage(
                key: const ValueKey('empty'),
                icon: Icons.music_note_rounded,
                message: AppLocalizations.of(context).noTrack,
              )
            : const PlayerPage(key: ValueKey('player'), embedded: true),
      ),
    );
  }
}

class PlayerPage extends StatefulWidget {
  /// Shown as a panel inside the wide (desktop) layout instead of as its own
  /// full screen.
  final bool embedded;

  const PlayerPage({super.key, this.embedded = false});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  String _currentArtist = '';
  Uint8List? _coverBytes;

  AudioManager get _manager => AudioManager();

  @override
  void initState() {
    super.initState();
    _manager.currentPath.addListener(_onTrackChanged);
    _loadMetadata();
  }

  @override
  void dispose() {
    _manager.currentPath.removeListener(_onTrackChanged);
    super.dispose();
  }

  void _onTrackChanged() {
    if (!mounted) return;
    if (!widget.embedded &&
        _manager.currentPath.value == null &&
        _manager.playlist.isEmpty) {
      // Everything in the queue was deleted.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) closeRouteOf(context);
      });
      return;
    }
    setState(_loadMetadata);
  }

  void _loadMetadata() {
    final path = _manager.currentPath.value;
    if (path == null) return;
    final cached = MetadataCache().peek(path);
    _currentArtist =
        cached?.artist ?? MetadataCache().getCachedArtist(path) ?? '';
    _coverBytes = cached?.coverArt;
    if (cached != null) return;
    MetadataCache().getMetadataInfo(path).then((info) {
      if (mounted && _manager.currentPath.value == path) {
        setState(() {
          _currentArtist = info.artist;
          _coverBytes = info.coverArt;
        });
      }
    });
  }

  Future<void> _showMenu() async {
    final path = _manager.currentPath.value;
    if (path == null) return;
    final l10n = AppLocalizations.of(context);
    final player = _manager.player;

    final action = await showGlassSheet<_MenuAction>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final loop = player.loopMode;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GlassSheetHeader(
                leading: CoverArt(path: path, size: 52, borderRadius: 12),
                title: formatName(path),
                subtitle: _currentArtist,
              ),
              GlassQuickActions(
                actions: [
                  GlassQuickAction(
                    icon: Icons.ios_share_rounded,
                    label: l10n.share,
                    onTap: () => Navigator.pop(ctx, _MenuAction.share),
                  ),
                  if (Platform.isAndroid)
                    GlassQuickAction(
                      icon: Icons.ring_volume_rounded,
                      label: l10n.ringtone,
                      onTap: () => Navigator.pop(ctx, _MenuAction.ringtone),
                    ),
                  GlassQuickAction(
                    icon: Icons.info_outline_rounded,
                    label: l10n.details,
                    onTap: () => Navigator.pop(ctx, _MenuAction.details),
                  ),
                  GlassQuickAction(
                    icon: Icons.format_list_bulleted_rounded,
                    label: l10n.queue,
                    onTap: () => Navigator.pop(ctx, _MenuAction.queue),
                  ),
                ],
              ),
              GlassMenuGroup(
                children: [
                  GlassMenuItem(
                    icon: Icons.speed_rounded,
                    label: l10n.speed,
                    value: _speedLabel(player.speed),
                    active: player.speed != 1.0,
                    onTap: () => Navigator.pop(ctx, _MenuAction.speed),
                  ),
                  // Toggles update in place without closing the sheet.
                  GlassMenuItem(
                    icon: Icons.shuffle_rounded,
                    label: l10n.shuffle,
                    value: player.shuffleModeEnabled ? l10n.on : l10n.off,
                    active: player.shuffleModeEnabled,
                    onTap: () async {
                      await _manager.toggleShuffle();
                      setSheetState(() {});
                    },
                  ),
                  GlassMenuItem(
                    icon: loop == LoopMode.one
                        ? Icons.repeat_one_rounded
                        : Icons.repeat_rounded,
                    label: l10n.repeat,
                    value: switch (loop) {
                      LoopMode.off => l10n.off,
                      LoopMode.all => l10n.repeatAllShort,
                      LoopMode.one => l10n.repeatOneShort,
                    },
                    active: loop != LoopMode.off,
                    onTap: () async {
                      await _manager.cycleLoopMode();
                      setSheetState(() {});
                    },
                  ),
                  StreamBuilder<int>(
                    stream: _manager.sleepTimerStream,
                    initialData: _manager.sleepSecondsRemaining,
                    builder: (_, snap) {
                      final s = snap.data ?? 0;
                      return GlassMenuItem(
                        icon: Icons.bedtime_outlined,
                        label: l10n.sleepTimer,
                        value: s == 0 ? l10n.off : _formatSleep(s, l10n),
                        active: s != 0,
                        onTap: () => Navigator.pop(ctx, _MenuAction.sleep),
                      );
                    },
                  ),
                ],
              ),
              GlassMenuGroup(
                children: [
                  GlassMenuItem(
                    icon: Icons.delete_outline_rounded,
                    label: l10n.delete,
                    destructive: true,
                    onTap: () => Navigator.pop(ctx, _MenuAction.delete),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case _MenuAction.delete:
        await confirmAndDeleteSongs(context, [path]);
      case _MenuAction.ringtone:
        await setAsRingtone(context, path);
      case _MenuAction.sleep:
        _showSleepTimerSheet();
      case _MenuAction.speed:
        _showSpeedSheet();
      case _MenuAction.queue:
        _showQueue();
      case _MenuAction.details:
        showSongDetails(context, path);
      case _MenuAction.share:
        await shareSongs([path]);
    }
  }

  void _showSleepTimerSheet() {
    final l10n = AppLocalizations.of(context);
    final options = <(String, Duration?)>[
      ('5 ${l10n.minutes}', const Duration(minutes: 5)),
      ('10 ${l10n.minutes}', const Duration(minutes: 10)),
      ('15 ${l10n.minutes}', const Duration(minutes: 15)),
      ('30 ${l10n.minutes}', const Duration(minutes: 30)),
      ('45 ${l10n.minutes}', const Duration(minutes: 45)),
      ('1 ${l10n.hour}', const Duration(hours: 1)),
      (l10n.endOfTrack, null),
    ];
    showGlassSheet<void>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassSheetTitle(l10n.sleepTimer),
          GlassMenuGroup(
            children: [
              for (final (label, duration) in options)
                GlassMenuItem(
                  icon: duration == null
                      ? Icons.music_off_outlined
                      : Icons.timer_outlined,
                  label: label,
                  checked:
                      duration == null &&
                      _manager.sleepSecondsRemaining == kSleepEndOfTrack,
                  onTap: () {
                    Navigator.pop(ctx);
                    if (duration == null) {
                      _manager.startSleepAtEndOfTrack();
                    } else {
                      _manager.startSleepTimer(duration);
                    }
                  },
                ),
            ],
          ),
          if (_manager.isSleepTimerActive)
            GlassMenuGroup(
              children: [
                GlassMenuItem(
                  icon: Icons.cancel_outlined,
                  label: l10n.cancelSleepTimer,
                  destructive: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    _manager.cancelSleepTimer();
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _showSpeedSheet() {
    final current = _manager.player.speed;
    final l10n = AppLocalizations.of(context);
    showGlassSheet<void>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassSheetTitle(l10n.speed),
          GlassMenuGroup(
            children: [
              for (final s in _speeds)
                GlassMenuItem(
                  icon: Icons.speed_rounded,
                  label: _speedLabel(s),
                  checked: s == current,
                  onTap: () {
                    _manager.player.setSpeed(s);
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showQueue() {
    final playlist = List<File>.of(_manager.playlist);
    if (playlist.isEmpty) return;
    Navigator.push(
      context,
      SmoothPageRoute(
        builder: (_) => FolderSongsPage(
          folderLabel: playlist.first.parent.path.split('/').last,
          files: playlist,
          scrollToCurrent: true,
          showMiniPlayer: false,
          onSongTap: (ctx, files, index) {
            Navigator.pop(ctx);
            _manager.playPath(files[index].path);
          },
        ),
      ),
    );
  }

  List<Widget> _topActions(AppLocalizations l10n) => [
    StreamBuilder<int>(
      stream: _manager.sleepTimerStream,
      initialData: _manager.sleepSecondsRemaining,
      builder: (_, snap) {
        final s = snap.data ?? 0;
        if (s == 0) return const SizedBox();
        return _SleepBadge(
          label: _formatSleep(s, l10n),
          onTap: _showSleepTimerSheet,
        );
      },
    ),
    const SizedBox(width: 8),
    GlassIconButton(
      blur: 0,
      icon: Icons.more_horiz_rounded,
      size: 42,
      tooltip: MaterialLocalizations.of(context).showMenuTooltip,
      onPressed: _showMenu,
    ),
  ];

  /// Record, title, timeline and transport controls.
  List<Widget> _body(
    ColorScheme cs,
    AppLocalizations l10n,
    String? path,
    double artSize,
  ) => [
    StreamBuilder<PlayerState>(
      stream: _manager.player.playerStateStream,
      initialData: _manager.player.playerState,
      builder: (_, snap) => VinylRecord(
        path: path,
        size: artSize,
        playing: isActuallyPlaying(snap.data),
      ),
    ),
    const SizedBox(height: 32),
    _buildTitle(cs, l10n, path),
    const SizedBox(height: 18),
    // Media transport controls and the timeline represent the direction of
    // time, so they stay left-to-right in Arabic (as in Apple's and Google's
    // RTL guidelines).
    SeekBar(
      activeColor: cs.onSurface.withValues(alpha: 0.85),
      inactiveColor: cs.onSurface.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: cs.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
    const SizedBox(height: 22),
    _buildMainControls(cs, l10n),
    const SizedBox(height: 24),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final path = _manager.currentPath.value;

    if (widget.embedded) return _buildPanel(cs, l10n, path);

    final screen = MediaQuery.sizeOf(context);
    final artSize = (screen.width - 56).clamp(180.0, screen.height * 0.42);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 68,
        leading: Center(
          child: GlassIconButton(
            blur: 0,
            icon: Icons.keyboard_arrow_down_rounded,
            size: 42,
            iconSize: 28,
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.pop(context),
          ),
        ),
        actions: [..._topActions(l10n), const SizedBox(width: 16)],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _PlayerBackdrop(cover: _coverBytes),
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: kToolbarHeight + 12),
                  ..._body(cs, l10n, path, artSize),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Rounded "now playing" card for the wide layout.
  Widget _buildPanel(ColorScheme cs, AppLocalizations l10n, String? path) {
    const radius = BorderRadius.all(Radius.circular(30));
    return LayoutBuilder(
      builder: (context, c) {
        final artSize = (c.maxWidth - 72).clamp(160.0, c.maxHeight * 0.48);
        return Container(
          foregroundDecoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Material(
              type: MaterialType.transparency,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _PlayerBackdrop(cover: _coverBytes),
                  SingleChildScrollView(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Row(
                            children: [const Spacer(), ..._topActions(l10n)],
                          ),
                        ),
                        ..._body(cs, l10n, path, artSize),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTitle(ColorScheme cs, AppLocalizations l10n, String? path) {
    final name = path != null ? formatName(path) : l10n.noTrack;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        layoutBuilder: (current, previous) => Stack(
          alignment: AlignmentDirectional.centerStart,
          children: [...previous, ?current],
        ),
        child: SizedBox(
          key: ValueKey(path),
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                _currentArtist.isEmpty ? l10n.unknownArtist : _currentArtist,
                style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainControls(ColorScheme cs, AppLocalizations l10n) {
    final player = _manager.player;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Row(
        textDirection: TextDirection.ltr,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GlassIconButton(
            blur: 0,
            icon: Icons.skip_previous_rounded,
            size: 62,
            iconSize: 34,
            tooltip: l10n.previous,
            onPressed: _manager.skipToPrevious,
          ),
          StreamBuilder<PlayerState>(
            stream: player.playerStateStream,
            initialData: player.playerState,
            builder: (_, snap) {
              final state = snap.data;
              final isPlaying = isActuallyPlaying(state);
              final busy =
                  state?.processingState == ProcessingState.loading ||
                  state?.processingState == ProcessingState.buffering;
              return _PlayPauseButton(
                isPlaying: isPlaying,
                busy: busy,
                tooltip: isPlaying ? l10n.pause : l10n.play,
                onPressed: isPlaying ? player.pause : _manager.resume,
              );
            },
          ),
          GlassIconButton(
            blur: 0,
            icon: Icons.skip_next_rounded,
            size: 62,
            iconSize: 34,
            tooltip: l10n.next,
            onPressed: player.seekToNext,
          ),
        ],
      ),
    );
  }

  String _formatSleep(int seconds, AppLocalizations l10n) {
    if (seconds == kSleepEndOfTrack) return l10n.endOfTrack;
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// Full-screen, heavily blurred artwork behind the player (like Apple Music),
/// falling back to the ambient glow when the track has no cover.
class _PlayerBackdrop extends StatefulWidget {
  final Uint8List? cover;

  const _PlayerBackdrop({required this.cover});

  @override
  State<_PlayerBackdrop> createState() => _PlayerBackdropState();
}

class _PlayerBackdropState extends State<_PlayerBackdrop> {
  static const _side = 48;

  /// The artwork blurred once into a tiny bitmap, then simply stretched to
  /// full screen. A live blur filter would be re-run on every frame while the
  /// record spins.
  ui.Image? _blurred;
  Uint8List? _preparedFor;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(_PlayerBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cover != widget.cover) _prepare();
  }

  @override
  void dispose() {
    _blurred?.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final bytes = widget.cover;
    _preparedFor = bytes;
    if (bytes == null) {
      _replace(null);
      return;
    }
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: _side);
      final src = (await codec.getNextFrame()).image;
      codec.dispose();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final rect = Offset.zero & Size.square(_side.toDouble());
      canvas.saveLayer(
        rect,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: 5,
            sigmaY: 5,
            tileMode: TileMode.mirror,
          ),
      );
      final w = src.width.toDouble(), h = src.height.toDouble();
      final side = math.min(w, h);
      canvas.drawImageRect(
        src,
        Rect.fromLTWH((w - side) / 2, (h - side) / 2, side, side),
        rect,
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
      src.dispose();
      final picture = recorder.endRecording();
      final image = await picture.toImage(_side, _side);
      picture.dispose();
      if (!mounted || _preparedFor != bytes) {
        image.dispose();
        return;
      }
      _replace(image);
    } catch (_) {
      if (mounted && _preparedFor == bytes) _replace(null);
    }
  }

  void _replace(ui.Image? image) {
    if (!mounted) return;
    final old = _blurred;
    setState(() => _blurred = image);
    // The previous image may still be fading out in the AnimatedSwitcher.
    if (old != null) Future.delayed(const Duration(seconds: 1), old.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final image = _blurred;

    final Widget layer = image == null
        ? const AmbientBackground(intensity: 1.6)
        : Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: cs.surface),
              RawImage(
                image: image,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      cs.surface.withValues(alpha: dark ? 0.30 : 0.25),
                      cs.surface.withValues(alpha: dark ? 0.55 : 0.50),
                      cs.surface.withValues(alpha: dark ? 0.80 : 0.78),
                    ],
                  ),
                ),
              ),
            ],
          );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      // Full-screen layers: the default layout centres children loosely.
      layoutBuilder: (current, previous) =>
          Stack(fit: StackFit.expand, children: [...previous, ?current]),
      child: KeyedSubtree(key: ValueKey(image), child: layer),
    );
  }
}

class _SleepBadge extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SleepBadge({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: GlassSurface(
        borderRadius: BorderRadius.circular(21),
        blur: 0,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(21),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bedtime_rounded, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final bool isPlaying;
  final bool busy;
  final String tooltip;
  final VoidCallback onPressed;

  const _PlayPauseButton({
    required this.isPlaying,
    required this.busy,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    const size = 84.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          GlassIconButton(
            blur: 0,
            size: size,
            tooltip: tooltip,
            // Coloured glass: the accent gradient, still slightly see-through.
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                for (final c in AppColors.accentGradient(
                  Theme.of(context).brightness,
                ))
                  c.withValues(alpha: 0.82),
              ],
            ),
            iconColor: Colors.white,
            iconSize: 44,
            onPressed: onPressed,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) => ScaleTransition(
                scale: animation,
                child: FadeTransition(opacity: animation, child: child),
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey<bool>(isPlaying),
              ),
            ),
          ),
          if (busy)
            const IgnorePointer(
              child: SizedBox(
                width: size - 6,
                height: size - 6,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white70,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
