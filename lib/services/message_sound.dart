import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'notification_sound.dart';

/// The short sound for an incoming message, while the app is open: the
/// one chosen for notifications ([sound]; none when Silent). If the device
/// or browser won't play it (e.g. a browser before any tap), it's skipped
/// quietly; it never affects the message itself.
class MessageSound {
  MessageSound({this.sound});

  final NotificationSound Function()? sound;
  AudioPlayer? _player;

  Future<void> play() async {
    final asset = (sound?.call() ?? NotificationSound.phoneDefault).asset;
    if (asset == null) return;
    try {
      final player = _player ??= AudioPlayer();
      await player.stop();
      await player.play(AssetSource(asset));
    } catch (error) {
      debugPrint('Message sound not played: $error');
    }
  }
}
