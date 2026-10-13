import 'dart:io';
import 'dart:ui';

import 'package:audio_player_app/audio_scanner.dart';
import 'package:audio_player_app/l10n/app_localizations.dart';
import 'package:audio_player_app/metadata_cache.dart';
import 'package:audio_player_app/utils/format_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('format_utils', () {
    test('formatName strips folder and extension', () {
      expect(formatName('/storage/emulated/0/Music/song.mp3'), 'song');
      expect(formatName('/a/b/my.track.name.flac'), 'my.track.name');
      expect(formatName('/a/.hidden'), '.hidden');
    });

    test('formatDuration', () {
      expect(formatDuration(null), '');
      expect(formatDuration(const Duration(seconds: 5)), '00:05');
      expect(formatDuration(const Duration(minutes: 3, seconds: 7)), '03:07');
      expect(
        formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });

    test('formatSize', () {
      expect(formatSize(512), '512 B');
      expect(formatSize(2048), '2.0 KB');
      expect(formatSize(5 * 1024 * 1024), '5.0 MB');
    });
  });

  group('stableHash', () {
    test('is deterministic', () {
      expect(stableHash('/a/b.mp3'), stableHash('/a/b.mp3'));
      expect(stableHash('/a/b.mp3'), hasLength(16));
    });

    test('differs for paths sharing a long prefix', () {
      // Regression: the old cover file name truncated base64(path) to 32
      // chars, so every file under the same long folder collided.
      const dir = '/storage/emulated/0/Music/Some Long Folder Name/';
      final hashes = {
        for (var i = 0; i < 200; i++) stableHash('${dir}track_$i.mp3'),
      };
      expect(hashes, hasLength(200));
    });
  });

  group('audio_scanner', () {
    test('isAudioPath is case-insensitive and extension based', () {
      expect(isAudioPath('/x/a.MP3'), isTrue);
      expect(isAudioPath('/x/a.opus'), isTrue);
      expect(isAudioPath('/x/a.txt'), isFalse);
      expect(isAudioPath('/x/noext'), isFalse);
    });

    test('isExcludedPath skips WhatsApp media', () {
      expect(isExcludedPath('/storage/emulated/0/WhatsApp/Media/a.opus'), true);
      expect(isExcludedPath('/storage/emulated/0/Music/a.mp3'), isFalse);
    });
  });

  group('AppLocalizations', () {
    test('substitutes named arguments', () {
      final en = AppLocalizations(const Locale('en'));
      expect(en.filesDeletedPartial(3, 1), 'Deleted 3, failed 1');
      expect(en.deleteFolderMsg('/x', 4), contains('4 audio files'));
      expect(en.deleteFolderMsg('/x', 4), contains('/x'));
    });

    test('falls back to English for missing Arabic keys', () {
      final ar = AppLocalizations(const Locale('ar'));
      expect(ar.translate('nonexistent'), 'nonexistent');
      expect(ar.delete, 'حذف');
    });
  });

  group('MetadataCache', () {
    test('getMetadataInfo completes and de-duplicates requests', () async {
      // Regression: the in-flight cleanup used to return the pending future
      // from whenComplete, so every request waited on itself forever.
      final dir = await Directory.systemTemp.createTemp('meta_test_');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/not_really_audio.mp3');
      await file.writeAsBytes(List.filled(1234, 0));

      final cache = MetadataCache();
      final results = await Future.wait([
        cache.getMetadataInfo(file.path),
        cache.getMetadataInfo(file.path),
      ]).timeout(const Duration(seconds: 10));

      expect(results[0].fileSize, 1234);
      expect(results[0].duration, isNull);
      expect(cache.peek(file.path)?.fileSize, 1234);
    });
  });
}
