import 'dart:io';
import 'package:flutter/services.dart';

enum RingtoneResult { success, permissionRequired, failed }

class DeviceUtils {
  static const _channel = MethodChannel('com.example.audio_player_app/device');

  static Future<RingtoneResult> setRingtone(String filePath) async {
    try {
      final result = await _channel.invokeMethod<bool>('setRingtone', {
        'path': filePath,
      });
      return result == true ? RingtoneResult.success : RingtoneResult.failed;
    } on PlatformException catch (e) {
      return e.code == 'PERMISSION_DENIED'
          ? RingtoneResult.permissionRequired
          : RingtoneResult.failed;
    } catch (_) {
      return RingtoneResult.failed;
    }
  }

  /// Deletes [paths] from the device. Returns the ones that are gone
  /// afterwards, and whether the user declined the system confirmation.
  ///
  /// On Android 11+ files not created by this app can't be removed with
  /// [File.delete]; the native side falls back to a single system
  /// confirmation dialog (MediaStore delete request) for all of them.
  static Future<({Set<String> deleted, bool cancelled})> deleteFiles(
    List<String> paths,
  ) async {
    if (paths.isEmpty) return (deleted: <String>{}, cancelled: false);
    // Android: MediaStore delete (with the system consent dialog).
    // macOS: moved to the Trash.
    if (Platform.isAndroid || Platform.isMacOS) {
      try {
        final deleted = await _channel.invokeListMethod<String>('deleteFiles', {
          'paths': paths,
        });
        if (deleted != null) {
          return (deleted: deleted.toSet(), cancelled: false);
        }
      } on PlatformException catch (e) {
        if (e.code == 'CANCELLED') {
          return (deleted: <String>{}, cancelled: true);
        }
        // Otherwise fall through to plain file deletion.
      } catch (_) {}
    }
    final deleted = <String>{};
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
        deleted.add(path);
      } catch (_) {}
    }
    return (deleted: deleted, cancelled: false);
  }

  /// Moves [paths] into [targetDir]. Returns `{oldPath: newPath}` for the
  /// files that moved, and whether the user declined the system confirmation
  /// (Android 11+ asks once before moving files the app doesn't own).
  static Future<({Map<String, String> moved, bool cancelled})> moveFiles(
    List<String> paths,
    String targetDir,
  ) async {
    if (paths.isEmpty) return (moved: <String, String>{}, cancelled: false);
    if (Platform.isAndroid) {
      try {
        final moved = await _channel.invokeMapMethod<String, String>(
          'moveFiles',
          {'paths': paths, 'targetDir': targetDir},
        );
        return (moved: moved ?? <String, String>{}, cancelled: false);
      } on PlatformException catch (e) {
        if (e.code == 'CANCELLED') {
          return (moved: <String, String>{}, cancelled: true);
        }
        return (moved: <String, String>{}, cancelled: false);
      } catch (_) {
        return (moved: <String, String>{}, cancelled: false);
      }
    }
    // macOS / others: a plain rename inside the accessible folders.
    final moved = <String, String>{};
    await Directory(targetDir).create(recursive: true);
    for (final path in paths) {
      try {
        final src = File(path);
        if (src.parent.path == targetDir || !await src.exists()) continue;
        final dst = _uniqueTarget(targetDir, path.split('/').last);
        await src.rename(dst);
        moved[path] = dst;
      } catch (_) {}
    }
    return (moved: moved, cancelled: false);
  }

  static String _uniqueTarget(String dir, String name) {
    var candidate = '$dir/$name';
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var i = 1;
    while (File(candidate).existsSync()) {
      candidate = '$dir/$base ($i)$ext';
      i++;
    }
    return candidate;
  }
}
