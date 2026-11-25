import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/meta_config.dart';

/// Where a story goes.
enum StoryApp { instagram, facebook }

/// Opens Instagram's or Facebook's story editor with a picture as the story
/// (the phone app's own code: MainActivity.kt, AppDelegate.swift). Only the
/// Android and iPhone apps can; a browser can't open another app's editor.
class StoryShare {
  StoryShare._();

  static const _channel = MethodChannel('huntr/story_share');

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// [first]'s story editor, else the other's; true when one opened (false:
  /// neither app is there, or this isn't a phone app).
  static Future<bool> open(Uint8List png, {required StoryApp first}) async {
    if (!supported) return false;
    final order = first == StoryApp.instagram
        ? const [StoryApp.instagram, StoryApp.facebook]
        : const [StoryApp.facebook, StoryApp.instagram];
    for (final app in order) {
      try {
        final opened = await _channel.invokeMethod<bool>('share', {
          'target': app.name,
          'png': png,
          'appId': metaAppId,
        });
        if (opened == true) return true;
      } on MissingPluginException {
        return false;
      } on PlatformException {
        // try the other one
      }
    }
    return false;
  }
}
