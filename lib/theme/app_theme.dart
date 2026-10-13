import 'package:flutter/material.dart';

/// "Liquid glass" palette: the icon's pink as the accent, with iOS violet and
/// blue for the aurora glow the translucent surfaces refract.
class AppColors {
  static const pink = Color(0xFFFF2D55);
  static const pinkDark = Color(0xFFFF375F);
  static const violet = Color(0xFFAF52DE);
  static const violetDark = Color(0xFFBF5AF2);
  static const blue = Color(0xFF007AFF);
  static const blueDark = Color(0xFF0A84FF);

  /// Accent gradient for highlighted glass (play button, artwork fallback).
  static List<Color> accentGradient(Brightness b) => b == Brightness.dark
      ? const [pinkDark, violetDark]
      : const [pink, violet];
}

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;

  final cs =
      ColorScheme.fromSeed(
        seedColor: AppColors.pink,
        brightness: brightness,
      ).copyWith(
        primary: dark ? AppColors.pinkDark : AppColors.pink,
        onPrimary: Colors.white,
        // iOS system red for destructive actions.
        error: dark ? const Color(0xFFFF453A) : const Color(0xFFFF3B30),
        onError: Colors.white,
        secondary: dark ? AppColors.blueDark : AppColors.blue,
        onSecondary: Colors.white,
        tertiary: dark ? AppColors.violetDark : AppColors.violet,
        onTertiary: Colors.white,
        // Neutral iOS system greys instead of pink-tinted Material surfaces.
        surface: dark ? Colors.black : const Color(0xFFF2F2F7),
        onSurface: dark ? Colors.white : const Color(0xFF1C1C1E),
        onSurfaceVariant: dark
            ? const Color(0xFF98989F)
            : const Color(0xFF6C6C70),
        surfaceContainerLowest: dark ? const Color(0xFF0A0A0A) : Colors.white,
        surfaceContainerLow: dark ? const Color(0xFF1C1C1E) : Colors.white,
        surfaceContainer: dark
            ? const Color(0xFF1C1C1E)
            : const Color(0xFFF2F2F7),
        surfaceContainerHigh: dark
            ? const Color(0xFF2C2C2E)
            : const Color(0xFFE5E5EA),
        surfaceContainerHighest: dark
            ? const Color(0xFF3A3A3C)
            : const Color(0xFFD1D1D6),
      );

  // Slightly see-through overlays so sheets and menus read as glass.
  final overlay = cs.surfaceContainerLow.withValues(alpha: dark ? 0.90 : 0.93);

  const sheetShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: 'Janna',
    colorScheme: cs,
    scaffoldBackgroundColor: cs.surface,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: cs.onSurface,
      titleTextStyle: TextStyle(
        fontFamily: 'Janna',
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: cs.onSurface,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      shape: sheetShape,
      backgroundColor: overlay,
      modalBackgroundColor: overlay,
      modalBarrierColor: Colors.black.withValues(alpha: dark ? 0.45 : 0.25),
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: cs.onSurfaceVariant.withValues(alpha: 0.4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: overlay,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: overlay,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(overlay),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: cs.onSurface.withValues(alpha: 0.08),
      thickness: 0.5,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: dark
          ? const Color(0xFF2C2C2E).withValues(alpha: 0.94)
          : Colors.white.withValues(alpha: 0.96),
      contentTextStyle: TextStyle(
        fontFamily: 'Janna',
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
        color: cs.onSurface,
      ),
      // Sit above the floating mini player.
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 104),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: Colors.white.withValues(alpha: dark ? 0.14 : 0.8),
        ),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: cs.primary),
    textSelectionTheme: TextSelectionThemeData(cursorColor: cs.primary),
  );
}
