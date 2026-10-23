import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// One launcher icon (and name) HUNTR can wear on the phone's home screen.
/// Its [id] matches an `.Icon…` alias in AndroidManifest.xml.
class AppIconChoice {
  const AppIconChoice({required this.id, this.label = 'HUNTR'});

  final String id;

  /// The name under it on the home screen.
  final String label;

  /// Its picture, as the launcher shows it (a copy of res/mipmap-xhdpi).
  String get asset => 'assets/app_icons/$id.png';

  /// Doesn't look like HUNTR (a plain app with its own name).
  bool get discreet => label != 'HUNTR';
}

/// The icons to choose from: HUNTR in each theme's colour, then Notes.
final appIconChoices = [
  for (final p in huntrPalettes) AppIconChoice(id: p.id),
  const AppIconChoice(id: 'notes', label: 'Notes'),
  const AppIconChoice(id: 'weather', label: 'Weather'),
  const AppIconChoice(id: 'clock', label: 'Clock'),
];

/// Switching the launcher icon (Android app only: a browser can't change
/// it, and iOS isn't set up yet). MainActivity.kt enables the chosen alias.
class AppIcons {
  static const _channel = MethodChannel('huntr/app_icon');

  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// The icon on the home screen now.
  static Future<String> current() async =>
      await _channel.invokeMethod<String>('current') ?? appIconChoices.first.id;

  /// Puts [id]'s icon (and name) on the home screen. The launcher may take
  /// a moment to show it.
  static Future<void> use(String id) =>
      _channel.invokeMethod<String>('set', {'icon': id});
}
