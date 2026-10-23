import 'package:flutter/material.dart';

/// Huntr colors: a warm orange-to-ember accent on a deep night background.
class HuntrColors {
  static const orange = Color(0xFFFF7A1A);
  static const ember = Color(0xFFFF4F1A);
  static const coral = Color(0xFFFF6B5B);
  static const night = Color(0xFF0C0C0F);
  static const surface = Color(0xFF16171C);
  static const surfaceHigh = Color(0xFF22232A);
  static const border = Color(0xFF2A2B33);
  static const online = Color(0xFF3DDC84);

  /// Selected (active) chips and filters.
  static const active = Color(0xFF3B82F6);
  static const muted = Color(0xFF9A9FAD);

  static const accentGradient = LinearGradient(
    colors: [orange, ember],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// The warm glow behind highlighted cards (e.g. the Me profile card).
  static const glowGradient = LinearGradient(
    colors: [Color(0xFF1E120B), Color(0xFF5C2408), Color(0xFFD9530F)],
    stops: [0, 0.5, 1],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// The app's font, everywhere. Text styles that replace the theme's (e.g. a
/// button's own textStyle) set it explicitly.
const huntrFontFamily = 'PlusJakartaSans';

ThemeData buildHuntrTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: HuntrColors.orange,
    brightness: Brightness.dark,
  ).copyWith(
    primary: HuntrColors.orange,
    onPrimary: Colors.black,
    secondary: HuntrColors.ember,
    surface: HuntrColors.night,
    surfaceContainerLow: HuntrColors.surface,
    surfaceContainer: HuntrColors.surface,
    surfaceContainerHigh: HuntrColors.surfaceHigh,
    surfaceContainerHighest: HuntrColors.surfaceHigh,
  );

  final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: Brightness.dark,
      fontFamily: huntrFontFamily);
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
      indicatorColor: HuntrColors.orange.withValues(alpha: 0.18),
      labelTextStyle: WidgetStatePropertyAll(base.textTheme.labelMedium),
      height: 68,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: HuntrColors.surface,
      selectedColor: HuntrColors.active.withValues(alpha: 0.22),
      // a blue outline when selected
      side: WidgetStateBorderSide.resolveWith((states) => BorderSide(
          color: states.contains(WidgetState.selected)
              ? HuntrColors.active
              : HuntrColors.border)),
      shape: const StadiumBorder(),
      labelStyle: base.textTheme.labelLarge,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? Colors.black
              : HuntrColors.muted),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? HuntrColors.orange
              : HuntrColors.surfaceHigh),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? HuntrColors.orange
              : HuntrColors.border),
    ),
    badgeTheme: const BadgeThemeData(
      backgroundColor: HuntrColors.ember,
      textColor: Colors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: HuntrColors.surface,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
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
        textStyle: const TextStyle(
            fontFamily: huntrFontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 16),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
