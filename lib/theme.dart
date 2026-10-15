import 'package:flutter/material.dart';

/// Huntr colors: a warm amber-to-coral accent on a deep night background.
class HuntrColors {
  static const amber = Color(0xFFFFB547);
  static const coral = Color(0xFFFF6B5B);
  static const night = Color(0xFF0F1014);
  static const surface = Color(0xFF181A20);
  static const surfaceHigh = Color(0xFF22252D);
  static const online = Color(0xFF3DDC84);
  static const muted = Color(0xFF9A9FAD);

  static const accentGradient = LinearGradient(
    colors: [amber, coral],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

ThemeData buildHuntrTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: HuntrColors.amber,
    brightness: Brightness.dark,
  ).copyWith(
    primary: HuntrColors.amber,
    onPrimary: Colors.black,
    secondary: HuntrColors.coral,
    surface: HuntrColors.night,
    surfaceContainerLow: HuntrColors.surface,
    surfaceContainer: HuntrColors.surface,
    surfaceContainerHigh: HuntrColors.surfaceHigh,
    surfaceContainerHighest: HuntrColors.surfaceHigh,
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: Brightness.dark);
  return base.copyWith(
    scaffoldBackgroundColor: HuntrColors.night,
    appBarTheme: const AppBarTheme(
      backgroundColor: HuntrColors.night,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: HuntrColors.surface,
      indicatorColor: HuntrColors.amber.withValues(alpha: 0.18),
      labelTextStyle: WidgetStatePropertyAll(base.textTheme.labelMedium),
      height: 68,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: HuntrColors.surface,
      selectedColor: HuntrColors.amber.withValues(alpha: 0.22),
      side: const BorderSide(color: Color(0xFF2C303A)),
      shape: const StadiumBorder(),
      labelStyle: base.textTheme.labelLarge,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: HuntrColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: HuntrColors.surface,
      showDragHandle: true,
      surfaceTintColor: Colors.transparent,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
