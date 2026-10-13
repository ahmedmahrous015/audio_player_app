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
}
