import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioMetadataInfo {
  final Uint8List? coverArt;
  final Duration? duration;
  final String artist;
  final int? fileSize;

  const AudioMetadataInfo({
    this.coverArt,
    this.duration,
    this.artist = '',
    this.fileSize,
  });
}

/// Lightweight per-file facts kept for every file ever read (cover bytes are
/// held separately in a bounded LRU because they are large).
class _MetaFacts {
  final Duration? duration;
  final String artist;
  final int? fileSize;
  final bool hasCover;

  const _MetaFacts(this.duration, this.artist, this.fileSize, this.hasCover);
}

typedef _RawMeta = ({
  int? sizeBytes,
  int? durationMs,
  String artist,
  Uint8List? cover,
});

/// Runs in a background isolate: parsing tags (and especially embedded
/// artwork) is synchronous file I/O that would otherwise jank the UI thread.
_RawMeta _readRawMetadata(String path) {
  final file = File(path);
  int? size;
  try {
    size = file.lengthSync();
  } catch (_) {}
  try {
    final m = readMetadata(file, getImage: true);
    return (
      sizeBytes: size,
      durationMs: m.duration?.inMilliseconds,
      artist: m.artist?.trim() ?? '',
      cover: m.pictures.isNotEmpty ? m.pictures.first.bytes : null,
    );
  } catch (_) {
    return (sizeBytes: size, durationMs: null, artist: '', cover: null);
  }
}

/// Spawns the background read. Kept as a plain (non-async) top-level function
/// so the closure only captures [path]: a closure created inside an async
/// method also captures that method's state (including Futures), which can't
/// be sent to another isolate.
Future<_RawMeta> _readInBackground(String path) =>
    Isolate.run(() => _readRawMetadata(path));

class MetadataCache {
  static final MetadataCache _instance = MetadataCache._internal();
  factory MetadataCache() => _instance;
  MetadataCache._internal();

  static const String _prefsKeyCachedPaths = 'cached_audio_paths';

  /// Max decoded-from-tag cover byte arrays kept in memory.
  static const int _maxCovers = 150;

  /// Max metadata reads running at once.
  static const int _maxConcurrentReads = 3;

  final _facts = <String, _MetaFacts>{};
  // Map literals are insertion-ordered, which gives us LRU ordering for free.
  final _covers = <String, Uint8List>{};
  final _inflight = <String, Future<AudioMetadataInfo>>{};
  final _uriCache = <String, Uri?>{};
  final _modTimeCache = <String, DateTime>{};
  final _waiters = <Completer<void>>[];
  int _running = 0;
  Future<String>? _artDirFuture;

  /// Fast retrieval of cached paths from disk
  Future<List<String>?> getCachedPaths() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_prefsKeyCachedPaths);
    } catch (_) {
      return null;
    }
  }

  /// Save scanned audio file paths to disk
  Future<void> saveCachedPaths(List<String> paths) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKeyCachedPaths, paths);
    } catch (_) {}
  }

  Uint8List? _takeCover(String path) {
    final bytes = _covers.remove(path);
    if (bytes != null) _covers[path] = bytes; // mark as most recently used
    return bytes;
  }

  void _putCover(String path, Uint8List bytes) {
    _covers.remove(path);
    _covers[path] = bytes;
    while (_covers.length > _maxCovers) {
      _covers.remove(_covers.keys.first);
    }
  }

  /// Synchronous lookup; returns null when the file has not been read yet or
  /// its artwork was evicted and needs re-reading.
  AudioMetadataInfo? peek(String path) {
    final f = _facts[path];
    if (f == null) return null;
    final cover = f.hasCover ? _takeCover(path) : null;
    if (f.hasCover && cover == null) return null;
    return AudioMetadataInfo(
      coverArt: cover,
      duration: f.duration,
      artist: f.artist,
      fileSize: f.fileSize,
    );
  }

  /// Unified metadata fetch in a single file-read pass.
  Future<AudioMetadataInfo> getMetadataInfo(String path) {
    final cached = peek(path);
    if (cached != null) return Future.value(cached);
    // Block body on purpose: `=> _inflight.remove(path)` would return this
    // very future, and whenComplete waits for a returned future -> deadlock.
    return _inflight[path] ??= _load(path).whenComplete(() {
      _inflight.remove(path);
    });
  }

  Future<AudioMetadataInfo> _load(String path) async {
    await _acquire();
    try {
      _RawMeta raw;
      try {
        raw = await _readInBackground(path);
      } catch (e) {
        debugPrint('MetadataCache: failed to read $path: $e');
        raw = (sizeBytes: null, durationMs: null, artist: '', cover: null);
      }
      final cover = raw.cover;
      final facts = _MetaFacts(
        raw.durationMs != null ? Duration(milliseconds: raw.durationMs!) : null,
        raw.artist,
        raw.sizeBytes,
        cover != null,
      );
      _facts[path] = facts;
      if (cover != null) _putCover(path, cover);
      return AudioMetadataInfo(
        coverArt: cover,
        duration: facts.duration,
        artist: facts.artist,
        fileSize: facts.fileSize,
      );
    } finally {
      _release();
    }
  }

  Future<void> _acquire() async {
    if (_running < _maxConcurrentReads) {
      _running++;
      return;
    }
    final c = Completer<void>();
    _waiters.add(c);
    await c.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      // LIFO: the most recent request is most likely for a row that is
      // currently on screen, so serve it before rows scrolled past.
      _waiters.removeLast().complete();
    } else {
      _running--;
    }
  }

  Future<Duration?> getCachedDuration(String path) async =>
      (await getMetadataInfo(path)).duration;

  Future<Uint8List?> getCoverArt(String path) async =>
      (await getMetadataInfo(path)).coverArt;

  Future<String> getArtist(String path) async =>
      (await getMetadataInfo(path)).artist;

  String? getCachedArtist(String path) => _facts[path]?.artist;

  Future<int?> getFileSize(String path) async {
    final known = _facts[path]?.fileSize;
    if (known != null) return known;
    try {
      return await File(path).length();
    } catch (_) {
      return null;
    }
  }

  Future<String> _artDir() {
    return _artDirFuture ??= () async {
      // A fixed directory (instead of a fresh createTemp per launch) so old
      // artwork files are reused rather than piling up in the temp folder.
      final dir = Directory('${Directory.systemTemp.path}/album_art');
      await dir.create(recursive: true);
      return dir.path;
    }();
  }

  /// Writes the track's artwork to a file so it can be shown in the media
  /// notification / lock screen.
  Future<Uri?> getCoverUri(String path) async {
    if (_uriCache.containsKey(path)) return _uriCache[path];

    final bytes = await getCoverArt(path);
    if (bytes == null) {
      _uriCache[path] = null;
      return null;
    }

    try {
      final dir = await _artDir();
      final f = File('$dir/${stableHash(path)}.${_detectFormat(bytes)}');
      if (!await f.exists()) {
        await f.writeAsBytes(bytes, flush: true);
      }
      final uri = Uri.file(f.path);
      _uriCache[path] = uri;
      return uri;
    } catch (_) {
      return null;
    }
  }

  Uri? getCachedCoverUri(String path) => _uriCache[path];

  String _detectFormat(Uint8List bytes) {
    if (bytes.length > 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    return 'jpg';
  }

  DateTime getFileModTime(File file) {
    return _modTimeCache.putIfAbsent(file.path, () {
      try {
        return file.lastModifiedSync();
      } catch (_) {
        return DateTime.fromMillisecondsSinceEpoch(0);
      }
    });
  }

  /// Drops everything known about [paths] (e.g. after they were deleted).
  void evict(Iterable<String> paths) {
    for (final p in paths) {
      _facts.remove(p);
      _covers.remove(p);
      _uriCache.remove(p);
      _modTimeCache.remove(p);
    }
  }

  void clear() {
    _facts.clear();
    _covers.clear();
    _uriCache.clear();
    _modTimeCache.clear();
  }
}

/// Deterministic 64-bit (two 32-bit FNV-1a lanes) hex hash of [s]. Unlike
/// [String.hashCode] it is stable across app launches.
String stableHash(String s) {
  var h1 = 0x811c9dc5;
  var h2 = 0x050c5d1f;
  for (final c in s.codeUnits) {
    h1 = ((h1 ^ c) * 0x01000193) & 0xFFFFFFFF;
    h2 = ((h2 ^ c) * 0x01000193) & 0xFFFFFFFF;
    h2 = (h2 ^ (h2 >> 15)) & 0xFFFFFFFF;
  }
  return h1.toRadixString(16).padLeft(8, '0') +
      h2.toRadixString(16).padLeft(8, '0');
}
