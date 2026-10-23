import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// The short sound for an incoming message, while the app is open. If the
/// device or browser won't play it (e.g. a browser before any tap), it's
/// skipped quietly; it never affects the message itself.
class MessageSound {
  AudioPlayer? _player;

  Future<void> play() async {
    try {
      final player = _player ??= AudioPlayer();
      await player.stop();
      await player.play(AssetSource('sounds/message.wav'));
    } catch (error) {
      debugPrint('Message sound not played: $error');
    }
  }
}
