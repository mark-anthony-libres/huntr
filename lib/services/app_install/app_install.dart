import 'app_install_stub.dart'
    if (dart.library.js_interop) 'app_install_web.dart' as platform;

/// Installing HUNTR from the website as an app (a PWA: its own icon and
/// window, no browser bar). Only the web has anything to do here; in the
/// phone and desktop apps it's all "no".
class AppInstall {
  const AppInstall._();

  /// Opened as the installed app (nothing to offer).
  static bool get isInstalled => platform.isInstalled();

  /// The browser can install it with one tap (Chrome, Edge, Samsung, ...).
  static bool get canPrompt => platform.canPrompt();

  /// An iPhone or iPad: installing is Share > "Add to Home Screen" (no
  /// button can do it).
  static bool get isIos => platform.isIos();

  /// Shows the browser's install dialog; true when the user installed it.
  static Future<bool> prompt() => platform.prompt();

  /// [listener] runs when installing becomes possible or it got installed.
  static void onChange(void Function() listener) => platform.onChange(listener);

  /// The banner was dismissed recently ("Not now" counts for 14 days).
  static bool get dismissedRecently => platform.dismissedRecently();

  static void dismiss() => platform.dismiss();
}
