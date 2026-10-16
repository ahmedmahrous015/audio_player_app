import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'audio_manager.dart';
import 'l10n/app_localizations.dart';
import 'pages/songs_page.dart';
import 'theme/app_theme.dart';
import 'utils/app_messenger.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Launch UI immediately so the first frame renders in 0ms,
  // dismissing the OS splash screen without delay.
  runApp(const _LifecycleApp());

  // Initialize background audio asynchronously without blocking the UI.
  AudioManager.ensureBackgroundInitialized();
}

class _LifecycleApp extends StatefulWidget {
  const _LifecycleApp();

  @override
  State<_LifecycleApp> createState() => _LifecycleAppState();
}

class _LifecycleAppState extends State<_LifecycleApp>
    with WidgetsBindingObserver {
  StreamSubscription<String>? _errorSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _errorSub = AudioManager().playbackErrorStream.listen((_) {
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        showAppMessage(AppLocalizations.of(context).playbackError);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _errorSub?.cancel();
    AudioManager().dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      AudioManager().saveState();
    }
  }

  @override
  Widget build(BuildContext context) {
    return const MyApp();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ar')],
      // Arabic (right-to-left) whenever it is among the device's preferred
      // languages, even if it isn't the first one (e.g. a Mac set to
      // English + Arabic); otherwise English.
      localeListResolutionCallback: (locales, supportedLocales) {
        final preferred = locales ?? const <Locale>[];
        if (preferred.any((l) => l.languageCode == 'ar')) {
          return const Locale('ar');
        }
        return const Locale('en');
      },
      // Desktop / hardware-keyboard shortcuts. Text fields keep their own keys
      // (e.g. space while typing a search) because they handle them first.
      builder: (context, child) => CallbackShortcuts(
        bindings: _playbackShortcuts(),
        child: Focus(autofocus: true, child: child!),
      ),
      home: const SongsPage(),
    );
  }
}

Map<ShortcutActivator, VoidCallback> _playbackShortcuts() {
  final manager = AudioManager();
  void togglePlay() {
    if (manager.currentPath.value == null) return;
    isActuallyPlaying(manager.player.playerState)
        ? manager.player.pause()
        : manager.resume();
  }

  return {
    const SingleActivator(LogicalKeyboardKey.space): togglePlay,
    const SingleActivator(LogicalKeyboardKey.mediaPlayPause): togglePlay,
    const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
        manager.seekRelative(const Duration(seconds: 10)),
    const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
        manager.seekRelative(const Duration(seconds: -10)),
    const SingleActivator(LogicalKeyboardKey.arrowRight, meta: true):
        manager.player.seekToNext,
    const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true):
        manager.skipToPrevious,
    const SingleActivator(LogicalKeyboardKey.mediaTrackNext):
        manager.player.seekToNext,
    const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious):
        manager.skipToPrevious,
  };
}
