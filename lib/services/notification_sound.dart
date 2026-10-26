import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The sound HUNTR's notifications make (Settings > Notifications > Sound),
/// saved on the account: each push asks Android for the matching channel
/// (MainActivity.kt; the backend's fcm_client.android_sound), and an
/// incoming message plays it while the app is open.
enum NotificationSound {
  /// The phone's own notification sound.
  phoneDefault('default', 'Phone default', 'sounds/message.wav'),
  chime('chime', 'Chime', 'sounds/chime.wav'),
  pop('pop', 'Pop', 'sounds/pop.wav'),
  ping('ping', 'Ping', 'sounds/ping.wav'),
  silent('silent', 'Silent', null),

  /// Any sound on the phone, picked in Android's settings for HUNTR's
  /// "Your sound" channel (Android app only).
  custom('custom', 'Your sound', 'sounds/message.wav');

  const NotificationSound(this.wire, this.label, this.asset);

  /// As the backend stores it.
  final String wire;
  final String label;

  /// Played in the app (and as the preview); null: nothing.
  final String? asset;

  static NotificationSound fromWire(String? wire) =>
      values.where((sound) => sound.wire == wire).firstOrNull ??
      NotificationSound.phoneDefault;

  /// The ones HUNTR offers; "Your sound" only where Android's settings can
  /// pick it (the Android app).
  static List<NotificationSound> get choices => [
        for (final sound in values)
          if (sound != custom || androidSettings) sound,
      ];

  /// The Android app: channels, and Android's settings for "Your sound".
  static bool get androidSettings =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static const _channel = MethodChannel('huntr/notification_sound');

  /// Creates HUNTR's notification channels, one per sound (Android app; at
  /// start, before any push needs one).
  static Future<void> ensureChannels() async {
    if (!androidSettings) return;
    try {
      await _channel.invokeMethod<void>('ensureChannels');
    } catch (error) {
      debugPrint('Notification channels not created: $error');
    }
  }

  /// Android's settings for this sound's channel ("Your sound": where its
  /// sound is picked).
  Future<void> openAndroidSettings() =>
      _channel.invokeMethod<void>('openSettings', {'sound': wire});

  static AudioPlayer? _preview;

  /// Plays it once (a preview in the picker); quietly skipped if it can't.
  Future<void> preview() async {
    final asset = this.asset;
    if (asset == null) return;
    try {
      final player = _preview ??= AudioPlayer();
      await player.stop();
      await player.play(AssetSource(asset));
    } catch (error) {
      debugPrint('Sound preview not played: $error');
    }
  }
}
