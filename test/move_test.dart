import 'dart:io';

import 'package:audio_player_app/device_utils.dart';
import 'package:audio_player_app/library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('folder names: rejects empty and path separators', () {
    expect(Library.isValidFolderName('My songs'), isTrue);
    expect(Library.isValidFolderName(''), isFalse);
    expect(Library.isValidFolderName('a/b'), isFalse);
    expect(Library.isValidFolderName('..'), isFalse);
  });

  test('moveFiles moves into the folder and never overwrites', () async {
    final root = await Directory.systemTemp.createTemp('move_test_');
    addTearDown(() => root.delete(recursive: true));
    final from = await Directory('${root.path}/from').create();
    final to = await Directory('${root.path}/to').create();
    final a = await File('${from.path}/song.mp3').writeAsString('a');
    // A file with the same name already exists in the destination.
    await File('${to.path}/song.mp3').writeAsString('existing');

    final result = await DeviceUtils.moveFiles([a.path], to.path);

    expect(result.cancelled, isFalse);
    expect(result.moved.keys, [a.path]);
    expect(result.moved[a.path], '${to.path}/song (1).mp3');
    expect(await a.exists(), isFalse);
    expect(await File('${to.path}/song.mp3').readAsString(), 'existing');
    expect(await File('${to.path}/song (1).mp3').readAsString(), 'a');
  });
}
