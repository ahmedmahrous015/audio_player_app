import 'dart:io';
import 'package:path_provider/path_provider.dart';

const audioExtensions = {
  '.mp3',
  '.m4a',
  '.wav',
  '.flac',
  '.aac',
  '.ogg',
  '.opus',
  '.wma',
  '.amr',
  '.ape',
  '.mka',
  '.mid',
  '.midi',
  '.caf',
  '.ac3',
  '.mp2',
  '.3gp',
  '.webm',
  '.pcm',
};

const _maxFiles = 2000;

const _ignoredDirNames = {
  'android',
  'data',
  'obb',
  '.git',
  '.thumbnails',
  '.cache',
  'cache',
  'node_modules',
  'pictures',
};

/// WhatsApp voice notes and media are intentionally left out of the library.
bool isExcludedPath(String path) => path.toLowerCase().contains('whatsapp');

bool isAudioPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot == -1) return false;
  return audioExtensions.contains(path.substring(dot).toLowerCase());
}

bool _shouldSkipDir(String path) {
  final lower = path.toLowerCase();
  if (isExcludedPath(lower)) return true;
  final name = lower.split('/').last;
  if (name.startsWith('.')) return true;
  if (_ignoredDirNames.contains(name)) return true;
  if (lower.contains('/android/data') || lower.contains('/android/obb')) {
    return true;
  }
  return false;
}

/// Scans device storage for audio files (at most [_maxFiles]).
Future<List<File>> findAudioFiles() async {
  final foundPaths = <String>{};
  final found = <File>[];

  void addFileIfAudio(File f) {
    final path = f.path;
    if (isExcludedPath(path) || !isAudioPath(path)) return;
    if (foundPaths.add(path)) found.add(f);
  }

  Future<void> scanDir(Directory dir, {int depth = 0, int maxDepth = 6}) async {
    if (depth > maxDepth || found.length >= _maxFiles) return;
    if (_shouldSkipDir(dir.path)) return;

    try {
      if (!await dir.exists()) return;
      final entities = await dir
          .list(recursive: false, followLinks: false)
          .toList();
      final subDirs = <Directory>[];

      for (final e in entities) {
        if (e is File) {
          addFileIfAudio(e);
          if (found.length >= _maxFiles) break;
        } else if (e is Directory && !_shouldSkipDir(e.path)) {
          subDirs.add(e);
        }
      }

      if (subDirs.isNotEmpty && found.length < _maxFiles) {
        await Future.wait(
          subDirs.map(
            (sub) => scanDir(sub, depth: depth + 1, maxDepth: maxDepth),
          ),
        );
      }
    } catch (_) {}
  }

  if (Platform.isAndroid) {
    const root = '/storage/emulated/0';
    // 1. Scan prioritized media directories first in parallel
    final priorityDirs = [
      'Music',
      'Download',
      'Podcasts',
      'Audiobooks',
      'Recordings',
      'Ringtones',
      'Notifications',
      'Alarms',
      'Documents',
      'DCIM',
      'Telegram/Telegram Audio',
    ].map((d) => Directory('$root/$d')).toList();

    await Future.wait(priorityDirs.map((d) => scanDir(d, maxDepth: 4)));

    // 2. Scan remaining top-level storage directories
    try {
      final rootDir = Directory(root);
      if (await rootDir.exists()) {
        final scanned = priorityDirs.map((d) => d.path.toLowerCase()).toSet();
        final remainingDirs = <Directory>[];
        await for (final e in rootDir.list(followLinks: false)) {
          if (e is File) {
            addFileIfAudio(e);
          } else if (e is Directory &&
              !_shouldSkipDir(e.path) &&
              !scanned.contains(e.path.toLowerCase())) {
            remainingDirs.add(e);
          }
        }
        await Future.wait(
          remainingDirs.map((d) => scanDir(d, depth: 1, maxDepth: 5)),
        );
      }
    } catch (_) {}

    if (found.isEmpty) {
      await scanDir(Directory('/sdcard'), maxDepth: 4);
    }
  } else if (Platform.isMacOS) {
    // Sandboxed: HOME is the app container, whose Music and Downloads entries
    // link to the user's real folders (read-only entitlements).
    final home = Platform.environment['HOME'];
    final dirs = [
      if (home != null) Directory('$home/Music'),
      if (home != null) Directory('$home/Downloads'),
      Directory((await getApplicationDocumentsDirectory()).path),
    ];
    await Future.wait(dirs.map((d) => scanDir(d, maxDepth: 6)));
  } else {
    final appDir = await getApplicationDocumentsDirectory();
    await scanDir(Directory(appDir.path), maxDepth: 4);
  }

  return found;
}
