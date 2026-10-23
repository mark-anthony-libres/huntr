import 'package:video_player/video_player.dart';

import '../huntr_backend.dart' show Story;
import 'story_video_cache_io.dart'
    if (dart.library.js_interop) 'story_video_cache_web.dart' as platform;

/// Story videos kept on this device, keyed by story id (never by the link,
/// which changes every time stories are listed): one played once is played
/// again from the device, and the next one is fetched ahead while the
/// current one plays. On a phone they're files in the app's private cache
/// (not the gallery, nothing a user can open or share), removed after a day
/// like the stories themselves. In a browser they stream as usual.
class StoryVideoCache {
  const StoryVideoCache._();

  /// A player for [story]: from the device when it's there, else downloaded
  /// first (or streamed when that fails).
  static Future<VideoPlayerController> player(Story story) =>
      platform.player(story);

  /// Downloads [story] ahead of time (does nothing if it's there already).
  static Future<void> prefetch(Story story) => platform.prefetch(story);
}
