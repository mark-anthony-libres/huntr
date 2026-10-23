import 'package:flutter/material.dart';

/// One accent the app can wear (Settings > Theme): its main colour, the
/// deeper end of its gradient, and the glow behind highlighted cards.
class HuntrPalette {
  const HuntrPalette({
    required this.id,
    required this.name,
    required this.accent,
    required this.ember,
    required this.glow,
  });

  /// Saved on the device ('orange', 'blue', ...).
  final String id;
  final String name;
  final Color accent;
  final Color ember;
  final List<Color> glow;
}

/// The themes to choose from; the first is HUNTR's own.
const huntrPalettes = [
  HuntrPalette(
      id: 'orange',
      name: 'Sunset',
      accent: Color(0xFFFF7A1A),
      ember: Color(0xFFFF4F1A),
      glow: [Color(0xFF1E120B), Color(0xFF5C2408), Color(0xFFD9530F)]),
  HuntrPalette(
      id: 'blue',
      name: 'Ocean',
      accent: Color(0xFF3B9CFF),
      ember: Color(0xFF2563EB),
      glow: [Color(0xFF0B121E), Color(0xFF0B2A5C), Color(0xFF1F5FD9)]),
  HuntrPalette(
      id: 'purple',
      name: 'Violet',
      accent: Color(0xFFB06BFF),
      ember: Color(0xFF7C3AED),
      glow: [Color(0xFF150B1E), Color(0xFF3A0B5C), Color(0xFF8A2BD9)]),
  HuntrPalette(
      id: 'pink',
      name: 'Rose',
      accent: Color(0xFFFF5CA8),
      ember: Color(0xFFE11D74),
      glow: [Color(0xFF1E0B14), Color(0xFF5C0B33), Color(0xFFD91F6E)]),
  HuntrPalette(
      id: 'green',
      name: 'Mint',
      accent: Color(0xFF2EE59D),
      ember: Color(0xFF10B981),
      glow: [Color(0xFF0B1E15), Color(0xFF0B5C3A), Color(0xFF12B47A)]),
  HuntrPalette(
      id: 'red',
      name: 'Crimson',
      accent: Color(0xFFFF5252),
      ember: Color(0xFFDC2626),
      glow: [Color(0xFF1E0B0B), Color(0xFF5C0B0B), Color(0xFFD91F1F)]),
  HuntrPalette(
      id: 'gold',
      name: 'Gold',
      accent: Color(0xFFFFC83D),
      ember: Color(0xFFF59E0B),
      glow: [Color(0xFF1E180B), Color(0xFF5C430B), Color(0xFFD99A0F)]),
  HuntrPalette(
      id: 'peach',
      name: 'Peach',
      accent: Color(0xFFFFAB91),
      ember: Color(0xFFFF7A59),
      glow: [Color(0xFF1E130F), Color(0xFF5C2E1F), Color(0xFFD9704F)]),
  HuntrPalette(
      id: 'magenta',
      name: 'Magenta',
      accent: Color(0xFFE879F9),
      ember: Color(0xFFC026D3),
      glow: [Color(0xFF1A0B1E), Color(0xFF4F0B5C), Color(0xFFB01FD9)]),
  HuntrPalette(
      id: 'indigo',
      name: 'Indigo',
      accent: Color(0xFF8B93FF),
      ember: Color(0xFF4F46E5),
      glow: [Color(0xFF0E0B1E), Color(0xFF1F1A5C), Color(0xFF4F46D9)]),
  HuntrPalette(
      id: 'sky',
      name: 'Sky',
      accent: Color(0xFF7DD3FC),
      ember: Color(0xFF38BDF8),
      glow: [Color(0xFF0B161E), Color(0xFF0B3A5C), Color(0xFF1FA0D9)]),
  HuntrPalette(
      id: 'teal',
      name: 'Lagoon',
      accent: Color(0xFF2DD4BF),
      ember: Color(0xFF0D9488),
      glow: [Color(0xFF0B1E1C), Color(0xFF0B5C55), Color(0xFF0FB8A6)]),
  HuntrPalette(
      id: 'lime',
      name: 'Lime',
      accent: Color(0xFFA3E635),
      ember: Color(0xFF65A30D),
      glow: [Color(0xFF131E0B), Color(0xFF3A5C0B), Color(0xFF7AB40F)]),
  HuntrPalette(
      id: 'mono',
      name: 'Mono',
      accent: Color(0xFFE5E7EB),
      ember: Color(0xFF9CA3AF),
      glow: [Color(0xFF121214), Color(0xFF2E2F36), Color(0xFF6B7080)]),
];

/// Huntr colors: an accent (orange by default; see [huntrPalettes]) on a
/// deep night background. The accent follows the chosen theme
/// ([HuntrColors.use]); everything else stays.
class HuntrColors {
  static HuntrPalette _palette = huntrPalettes.first;

  /// The theme in use.
  static HuntrPalette get palette => _palette;

  /// Wears [palette] from now on (the app rebuilds to show it).
  static void use(HuntrPalette palette) => _palette = palette;

  /// The accent (named for HUNTR's own orange).
  static Color get orange => _palette.accent;
  static Color get ember => _palette.ember;
  static const coral = Color(0xFFFF6B5B);
  static const night = Color(0xFF0C0C0F);
  static const surface = Color(0xFF16171C);
  static const surfaceHigh = Color(0xFF22232A);
  static const border = Color(0xFF2A2B33);
  static const online = Color(0xFF3DDC84);

  /// Selected (active) chips and filters.
  static const active = Color(0xFF3B82F6);
  static const muted = Color(0xFF9A9FAD);

  static LinearGradient get accentGradient => LinearGradient(
        colors: [orange, ember],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  /// The warm glow behind highlighted cards (e.g. the Me profile card).
  static LinearGradient get glowGradient => LinearGradient(
        colors: _palette.glow,
        stops: const [0, 0.5, 1],
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
    badgeTheme: BadgeThemeData(
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
