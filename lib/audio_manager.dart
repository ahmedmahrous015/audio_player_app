import 'dart:async';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'metadata_cache.dart';
import 'utils/format_utils.dart';

/// Whether the UI should show "pause": just_audio keeps `playing == true`
/// after the queue completes, which would otherwise leave a dead pause button.
bool isActuallyPlaying(PlayerState? state) =>
    state != null &&
    state.playing &&
    state.processingState != ProcessingState.completed;

/// Value emitted on [AudioManager.sleepTimerStream] while an
/// "end of track" sleep timer is armed.
const int kSleepEndOfTrack = -1;

class AudioManager {
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() => _instance;

  AudioManager._internal() {
    _initSubscriptions();
    unawaited(_restorePlaybackSettings());
  }

  static Future<void>? _bgInitFuture;

  /// Ensures JustAudioBackground is initialized before any playback or audio source setup.
  static Future<void> ensureBackgroundInitialized() {
    return _bgInitFuture ??= () async {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.example.audio.channel',
        androidNotificationChannelName: 'Audio Playback',
        androidNotificationOngoing: true,
      );
      // Declare ourselves a music player: just_audio then requests audio
      // focus on play, pausing when headphones are unplugged ("becoming
      // noisy") and during calls, and resuming after short interruptions.
      try {
        final session = await AudioSession.instance;
        await session.configure(const AudioSessionConfiguration.music());
      } catch (_) {}
    }();
  }

  static const _kLastTrack = 'last_track_path';
  static const _kLastPosition = 'last_position_ms';
  static const _kSpeed = 'playback_speed';
  static const _kLoopMode = 'loop_mode';
  static const _kShuffle = 'shuffle_enabled';

  final AudioPlayer player = AudioPlayer();
  List<File> playlist = [];

  /// Path of the track currently loaded in the player, or null when nothing
  /// is loaded. Safer than indexing [playlist] with [AudioPlayer.currentIndex],
  /// which can briefly disagree while the source is being rebuilt.
  final ValueNotifier<String?> currentPath = ValueNotifier<String?>(null);

  Timer? _sleepTimer;
  bool _sleepAtEndOfTrack = false;
  final StreamController<int> _sleepTickController =
      StreamController<int>.broadcast();
  int _sleepSecondsRemaining = 0;
  Timer? _saveTimer;
  SharedPreferences? _prefs;

  /// Incremented on every [setPlaylist] call so a slow, older request (like
  /// restoring the last session) can't replace a newer one.
  int _loadToken = 0;

  final StreamController<Set<String>> _deletedController =
      StreamController<Set<String>>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  /// Emits the set of paths removed from disk anywhere in the app, so every
  /// screen listing files can drop them.
  Stream<Set<String>> get deletedFilesStream => _deletedController.stream;

  /// Emits the path of a track that failed to load or play.
  Stream<String> get playbackErrorStream => _errorController.stream;

  /// Emits remaining seconds, 0 when cancelled, or [kSleepEndOfTrack].
  Stream<int> get sleepTimerStream => _sleepTickController.stream;
  bool get isSleepTimerActive => _sleepTimer != null || _sleepAtEndOfTrack;
  int get sleepSecondsRemaining =>
      _sleepAtEndOfTrack ? kSleepEndOfTrack : _sleepSecondsRemaining;

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  void _initSubscriptions() {
    player.playingStream.listen((playing) {
      if (playing) {
        _startPositionSaver();
      } else {
        _stopPositionSaver();
        _saveState();
      }
    });

    player.sequenceStateStream.listen((state) {
      final tag = state?.currentSource?.tag;
      final path = tag is MediaItem ? tag.id : null;
      _setCurrentPath(path);
    });

    player.positionDiscontinuityStream.listen((d) {
      if (d.reason == PositionDiscontinuityReason.autoAdvance) {
        _onTrackFinished();
      }
    });

    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) _onTrackFinished();
    });

    // Without an error listener a broken file surfaces as an unhandled
    // async exception; report it to the UI instead.
    player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace _) {
        final path = currentPath.value;
        if (path != null) _errorController.add(path);
      },
    );
  }

  void _setCurrentPath(String? path) {
    if (path != null && !playlist.any((f) => f.path == path)) path = null;
    if (currentPath.value != path) {
      currentPath.value = path;
      _saveState();
    }
  }

  Future<void> _savePref(Future<bool> Function(SharedPreferences) write) async {
    try {
      await write(await _getPrefs());
    } catch (_) {}
  }

  Future<void> _restorePlaybackSettings() async {
    try {
      final prefs = await _getPrefs();
      final speed = prefs.getDouble(_kSpeed);
      final loop = prefs.getInt(_kLoopMode);
      final shuffle = prefs.getBool(_kShuffle);
      if (speed != null && speed > 0) await player.setSpeed(speed);
      if (loop != null && loop >= 0 && loop < LoopMode.values.length) {
        await player.setLoopMode(LoopMode.values[loop]);
      }
      if (shuffle == true) await player.setShuffleModeEnabled(true);
    } catch (_) {
    } finally {
      // Subscribe only after restoring, otherwise the streams' initial default
      // values would overwrite the saved settings.
      player.speedStream.listen(
        (s) => _savePref((p) => p.setDouble(_kSpeed, s)),
      );
      player.loopModeStream.listen(
        (m) => _savePref((p) => p.setInt(_kLoopMode, m.index)),
      );
      player.shuffleModeEnabledStream.listen(
        (on) => _savePref((p) => p.setBool(_kShuffle, on)),
      );
    }
  }

  void _startPositionSaver() {
    _stopPositionSaver();
    _saveTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _saveState(),
    );
  }

  void _stopPositionSaver() {
    _saveTimer?.cancel();
    _saveTimer = null;
  }

  Future<void> _saveState() async {
    final path = currentPath.value;
    if (path == null) return;
    try {
      final prefs = await _getPrefs();
      await prefs.setString(_kLastTrack, path);
      await prefs.setInt(_kLastPosition, player.position.inMilliseconds);
    } catch (_) {}
  }

  Future<void> saveState() => _saveState();

  Future<({String path, int positionMs})?> loadSavedState() async {
    try {
      final prefs = await _getPrefs();
      final path = prefs.getString(_kLastTrack);
      final pos = prefs.getInt(_kLastPosition);
      if (path == null || pos == null) return null;
      return (path: path, positionMs: pos);
    } catch (_) {
      return null;
    }
  }

  /// Loads (paused) the track that was playing when the app was last closed.
  Future<void> restoreLastSession(List<File> files) async {
    if (_loadToken != 0) return;
    final saved = await loadSavedState();
    if (saved == null || _loadToken != 0) return;
    final idx = files.indexWhere((f) => f.path == saved.path);
    if (idx < 0) return;
    try {
      await setPlaylist(
        files,
        idx,
        initialPosition: Duration(milliseconds: saved.positionMs),
      );
    } catch (_) {}
  }

  MediaItem _mediaItemFor(File file) {
    final path = file.path;
    final artist = MetadataCache().getCachedArtist(path);
    return MediaItem(
      id: path,
      title: formatName(path),
      album: file.parent.path.split('/').last,
      artist: (artist != null && artist.isNotEmpty) ? artist : null,
      artUri: MetadataCache().getCachedCoverUri(path),
    );
  }

  AudioSource _sourceFor(File file) =>
      AudioSource.uri(Uri.file(file.path), tag: _mediaItemFor(file));

  /// Loads the folder containing `files[index]` as the play queue (sorted by
  /// name) and starts from that file. Returns false if nothing was loaded
  /// (invalid input or superseded by a newer call).
  Future<bool> setPlaylist(
    List<File> files,
    int index, {
    Duration? initialPosition,
  }) async {
    if (files.isEmpty || index < 0 || index >= files.length) return false;
    final token = ++_loadToken;

    // Ensure background audio service is initialized before creating MediaItem sources
    await ensureBackgroundInitialized();

    final targetFile = files[index];
    final folderPath = targetFile.parent.path;

    // Filter files to only those in the same folder
    final folderFiles = files
        .where((f) => f.parent.path == folderPath)
        .toList();

    // Sort folder files alphabetically/by path to keep a consistent order within folders
    folderFiles.sort(
      (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
    );

    // Find the new index of targetFile in the filtered list
    final newIndex = folderFiles.indexWhere((f) => f.path == targetFile.path);
    final finalIndex = newIndex >= 0 ? newIndex : 0;

    // Give the notification artwork/artist for the starting track a short
    // head start; don't hold up playback if the file is slow to parse.
    try {
      await MetadataCache()
          .getCoverUri(targetFile.path)
          .timeout(const Duration(milliseconds: 400));
    } catch (_) {}

    if (token != _loadToken) return false;
    playlist = folderFiles;

    await player.setAudioSource(
      ConcatenatingAudioSource(children: folderFiles.map(_sourceFor).toList()),
      initialIndex: finalIndex,
      initialPosition: initialPosition,
    );

    unawaited(_prefetchAdjacent(finalIndex));
    return true;
  }

  /// Loads and plays; returns false (and reports the error) on failure.
  Future<bool> playFiles(List<File> files, int index) async {
    try {
      if (!await setPlaylist(files, index)) return false;
      unawaited(player.play());
      return true;
    } on PlayerInterruptedException {
      // A newer request replaced this one; not an error.
      return false;
    } catch (_) {
      if (index >= 0 && index < files.length) {
        _errorController.add(files[index].path);
      }
      return false;
    }
  }

  /// Play button handler: after the queue has finished, `play()` alone does
  /// nothing, so restart the current track first.
  Future<void> resume() async {
    if (player.processingState == ProcessingState.completed) {
      await player.seek(Duration.zero);
    }
    await player.play();
  }

  /// Jumps to [path] inside the current queue.
  Future<void> playPath(String path) async {
    final idx = playlist.indexWhere((f) => f.path == path);
    if (idx < 0) return;
    if (idx != player.currentIndex) {
      await player.seek(Duration.zero, index: idx);
    }
    unawaited(player.play());
  }

  /// "Previous" that restarts the current track if it has played for a few
  /// seconds, matching common music player behaviour.
  Future<void> skipToPrevious() async {
    if (player.position > const Duration(seconds: 3) || !player.hasPrevious) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  Future<void> seekRelative(Duration offset) async {
    final dur = player.duration;
    var target = player.position + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (dur != null && target > dur) target = dur;
    await player.seek(target);
  }

  Future<void> cycleLoopMode() {
    const order = [LoopMode.off, LoopMode.all, LoopMode.one];
    final next = order[(order.indexOf(player.loopMode) + 1) % order.length];
    return player.setLoopMode(next);
  }

  Future<void> toggleShuffle() async {
    final enable = !player.shuffleModeEnabled;
    if (enable) await player.shuffle();
    await player.setShuffleModeEnabled(enable);
  }

  Future<void> _prefetchAdjacent(int currentIndex) async {
    for (final i in [currentIndex, currentIndex + 1, currentIndex - 1]) {
      if (i >= 0 && i < playlist.length) {
        unawaited(MetadataCache().getCoverUri(playlist[i].path));
      }
    }
  }

  void startSleepTimer(Duration duration) {
    cancelSleepTimer();
    _sleepSecondsRemaining = duration.inSeconds;
    _emitSleep(_sleepSecondsRemaining);

    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _sleepSecondsRemaining--;
      _emitSleep(_sleepSecondsRemaining);
      // Fade out over the last 10 seconds instead of cutting off abruptly.
      if (_sleepSecondsRemaining <= 10 && _sleepSecondsRemaining > 0) {
        player.setVolume(_sleepSecondsRemaining / 10);
      }
      if (_sleepSecondsRemaining <= 0) {
        cancelSleepTimer();
        player.pause();
      }
    });
  }

  /// Pauses playback when the current track finishes.
  void startSleepAtEndOfTrack() {
    cancelSleepTimer();
    _sleepAtEndOfTrack = true;
    _emitSleep(kSleepEndOfTrack);
  }

  void _onTrackFinished() {
    if (!_sleepAtEndOfTrack) return;
    cancelSleepTimer();
    player.pause();
    // Auto-advance already moved to the next track; rewind it so it is ready.
    if (player.processingState != ProcessingState.completed) {
      player.seek(Duration.zero);
    }
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepAtEndOfTrack = false;
    _sleepSecondsRemaining = 0;
    if (player.volume != 1.0) player.setVolume(1.0);
    _emitSleep(0);
  }

  void _emitSleep(int value) {
    if (!_sleepTickController.isClosed) _sleepTickController.add(value);
  }

  /// Call after files were removed from disk: updates the queue and notifies
  /// every listening screen.
  void onFilesDeleted(Set<String> paths) {
    if (paths.isEmpty) return;
    MetadataCache().evict(paths);
    removeFromPlaylistBatch(paths);
    if (!_deletedController.isClosed) _deletedController.add(paths);
  }

  void removeFromPlaylist(String path) => removeFromPlaylistBatch({path});

  void removeFromPlaylistBatch(Iterable<String> paths) {
    final pathSet = paths.toSet();
    if (!playlist.any((f) => pathSet.contains(f.path))) return;

    final oldIndex = player.currentIndex;
    int decrement = 0;
    if (oldIndex != null) {
      for (var i = 0; i < oldIndex && i < playlist.length; i++) {
        if (pathSet.contains(playlist[i].path)) decrement++;
      }
    }

    final wasCurrent = pathSet.contains(currentPath.value);

    playlist.removeWhere((f) => pathSet.contains(f.path));

    if (playlist.isEmpty) {
      _setCurrentPath(null);
      unawaited(player.stop());
      return;
    }

    if (wasCurrent) {
      final idx = ((oldIndex ?? 0) - decrement).clamp(0, playlist.length - 1);
      unawaited(_rebuildSources(idx, Duration.zero));
    } else {
      unawaited(
        _rebuildSources(
          oldIndex != null ? oldIndex - decrement : null,
          player.position,
        ),
      );
    }
  }

  Future<void> _rebuildSources(int? index, Duration position) async {
    try {
      await player.setAudioSource(
        ConcatenatingAudioSource(children: playlist.map(_sourceFor).toList()),
        initialIndex: index,
        initialPosition: position,
      );
    } catch (_) {}
  }

  void dispose() {
    _stopPositionSaver();
    _saveState();
    cancelSleepTimer();
    _sleepTickController.close();
    _deletedController.close();
    _errorController.close();
    player.dispose();
  }
}
