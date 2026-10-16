import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide view of the library's folders, so any screen (e.g. the "move to
/// folder" sheet) can list them, plus folders the user created that don't
/// contain any audio yet.
class Library {
  static final Library _instance = Library._internal();
  factory Library() => _instance;
  Library._internal();

  static const _kCreatedFolders = 'created_folders';

  /// Folders that currently hold audio files (kept up to date by the songs
  /// page after each scan / change).
  final ValueNotifier<List<String>> scannedFolders = ValueNotifier(const []);

  /// Folders created from the app; shown even while empty.
  final ValueNotifier<Set<String>> createdFolders = ValueNotifier(const {});

  /// Every known folder: scanned ones first, then empty created ones.
  List<String> get allFolders => [
    ...scannedFolders.value,
    for (final f in createdFolders.value)
      if (!scannedFolders.value.contains(f)) f,
  ];

  /// Where new folders are created.
  static String? get defaultRoot {
    if (Platform.isAndroid) return '/storage/emulated/0/Music';
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      return home == null ? null : '$home/Music';
    }
    return null;
  }

  Future<void> loadCreatedFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_kCreatedFolders) ?? const [];
      // Drop folders that were removed outside the app.
      createdFolders.value = {
        for (final p in saved)
          if (Directory(p).existsSync()) p,
      };
    } catch (_) {}
  }

  Future<void> _saveCreatedFolders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _kCreatedFolders,
        createdFolders.value.toList(),
      );
    } catch (_) {}
  }

  /// Creates `<defaultRoot>/<name>`. Returns its path, or null on failure.
  Future<String?> createFolder(String name) async {
    final root = defaultRoot;
    final clean = name.trim();
    if (root == null || !isValidFolderName(clean)) return null;
    final path = '$root/$clean';
    try {
      await Directory(path).create(recursive: true);
    } catch (_) {
      return null;
    }
    createdFolders.value = {...createdFolders.value, path};
    await _saveCreatedFolders();
    return path;
  }

  /// Forgets (and removes, if empty) a created folder.
  Future<void> removeCreatedFolder(String path) async {
    try {
      final dir = Directory(path);
      if (dir.existsSync() && dir.listSync().isEmpty) await dir.delete();
    } catch (_) {}
    createdFolders.value = {...createdFolders.value}..remove(path);
    await _saveCreatedFolders();
  }

  static bool isValidFolderName(String name) =>
      name.isNotEmpty &&
      name != '.' &&
      name != '..' &&
      !name.contains('/') &&
      !name.contains('\\');

  static bool folderExists(String name) {
    final root = defaultRoot;
    return root != null && Directory('$root/${name.trim()}').existsSync();
  }
}
