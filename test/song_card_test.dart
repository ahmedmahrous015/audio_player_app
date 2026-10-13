import 'package:audio_player_app/l10n/app_localizations.dart';
import 'package:audio_player_app/widgets/song_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: const [AppLocalizations.delegate],
  home: Scaffold(body: child),
);

void main() {
  testWidgets('selection mode shows a check instead of the ⋯ button', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        SongCard(
          name: 'Song',
          filePath: '/nonexistent/song.mp3',
          onTap: () {},
          selectionMode: true,
          selected: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
  });

  testWidgets('long-press calls onLongPress (starts selection)', (
    tester,
  ) async {
    var longPressed = false;
    await tester.pumpWidget(
      _host(
        SongCard(
          name: 'Song',
          filePath: '/nonexistent/song.mp3',
          onTap: () {},
          onLongPress: () => longPressed = true,
        ),
      ),
    );
    await tester.pump(); // let the (async) localizations load
    await tester.longPress(find.text('Song'));
    expect(longPressed, isTrue);
    expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
  });
}
