import 'dart:ui' show Color;

import '../../theme.dart';
import 'splash_theme_stub.dart'
    if (dart.library.js_interop) 'splash_theme_web.dart' as platform;

/// Tells the web page that shows before the app starts (web/index.html)
/// which theme to wear next time: its colours, kept in the browser's
/// plain storage (the app's own choice is in secure storage, which the
/// page can't read). Nothing on the other platforms.
void rememberSplashTheme(HuntrPalette palette) {
  String hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
  platform.save(
    accent: hex(palette.accent),
    ember: hex(palette.ember),
    // the glow behind the logo: the night, a little towards the accent
    glow: hex(Color.lerp(HuntrColors.night, palette.accent, 0.14)!),
  );
}
