// The classic registration token (getToken / onTokenRefresh): the backend
// sends to it with FCM's HTTP v1 `token` target. The newer register() gives
// an installation id that needs a different send target - not used yet.
// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config/firebase_config.dart';
import '../config/google_oauth_config.dart';
import 'huntr_backend.dart' as backend;

/// Where a tapped notification leads: the Taps inbox, or a chat.
sealed class PushTarget {
  const PushTarget();

  /// From a notification's data (`type`, `conversation_id`), or the
  /// website's link (`?open=taps` / `?open=chat&conversation=…`).
  static PushTarget? from(Map<String, dynamic> data) {
    final open = data['open'] ?? data['type'];
    final conversation =
        int.tryParse('${data['conversation'] ?? data['conversation_id']}');
    return switch (open) {
      'tap' || 'taps' => const OpenTaps(),
      'chat' ||
      'message' ||
      'story_reply' when conversation != null =>
        OpenChat(conversation),
      _ => null,
    };
  }
}

class OpenTaps extends PushTarget {
  const OpenTaps();
}

class OpenChat extends PushTarget {
  const OpenChat(this.conversationId);
  final int conversationId;
}

/// Push notifications (Firebase Cloud Messaging) on this device: asking to
/// show them, registering the device with the backend after sign-in (and
/// forgetting it on sign-out), and where a tapped one leads. The website and
/// the Android app only (not the desktop app). What's sent, and each kind's
/// switch, is the backend's (push_service).
class PushNotifications {
  PushNotifications._();

  static final instance = PushNotifications._();

  static bool get supported =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android;

  static String get _platform => kIsWeb ? 'web' : 'android';

  bool _ready = false;
  String? _pushToken;
  String? _sessionToken;
  StreamSubscription<String>? _refreshes;
  StreamSubscription<RemoteMessage>? _opens;

  /// Whether this device lets HUNTR show notifications (null: not known,
  /// or not supported here).
  final permission = ValueNotifier<AuthorizationStatus?>(null);

  /// This device is registered with the backend (it gets notifications).
  final registered = ValueNotifier<bool>(false);

  /// Why notifications couldn't be set up here (null: no problem), for
  /// Settings to show - with a way to try again ([enable]).
  final problem = ValueNotifier<String?>(null);

  void _failed(String what, Object error) {
    debugPrint('$what: $error');
    final text = error is backend.BackendException ? error.message : '$error';
    problem.value = text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }

  Future<void> _init() async {
    if (_ready) return;
    await Firebase.initializeApp(
        options: kIsWeb
            ? const FirebaseOptions(
                apiKey: FirebaseWebConfig.apiKey,
                authDomain: FirebaseWebConfig.authDomain,
                projectId: FirebaseWebConfig.projectId,
                storageBucket: FirebaseWebConfig.storageBucket,
                messagingSenderId: FirebaseWebConfig.messagingSenderId,
                appId: FirebaseWebConfig.appId)
            // Android: android/app/google-services.json
            : null);
    _ready = true;
    permission.value =
        (await FirebaseMessaging.instance.getNotificationSettings())
            .authorizationStatus;
  }

  /// Signed in: if notifications are already allowed, this device is
  /// registered (again; tokens change). [onOpen]: a notification was
  /// tapped (also the one that started the app).
  Future<void> start(String sessionToken,
      {required void Function(PushTarget target) onOpen}) async {
    if (!supported) return;
    _sessionToken = sessionToken;
    try {
      await _init();
      // first: this device gets notifications (when allowed)
      if (permission.value == AuthorizationStatus.authorized) {
        await _register();
      }
    } catch (error) {
      _failed('Push notifications not started', error);
      return;
    }
    // then: where a tapped one leads (on its own: it never stops the above)
    try {
      _opens ??= FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final target = PushTarget.from(message.data);
        if (target != null) onOpen(target);
      });
      final first = await FirebaseMessaging.instance.getInitialMessage();
      final target = first == null ? null : PushTarget.from(first.data);
      if (target != null) onOpen(target);
    } catch (error) {
      debugPrint('Tapped notifications not followed: $error');
    }
  }

  /// Reads this device's permission again (after the person allowed it in
  /// the browser's or phone's settings) and, when it's allowed now,
  /// registers the device. True when notifications are on here.
  Future<bool> recheck() async {
    if (!supported || _sessionToken == null) return false;
    try {
      await _init();
      permission.value =
          (await FirebaseMessaging.instance.getNotificationSettings())
              .authorizationStatus;
      if (permission.value != AuthorizationStatus.authorized) return false;
      if (!registered.value) {
        problem.value = null;
        await _register();
      }
      return registered.value;
    } catch (error) {
      _failed('Push notifications not rechecked', error);
      return false;
    }
  }

  /// Not asked yet on this device (the app offers to turn them on).
  bool get undecided =>
      supported && permission.value == AuthorizationStatus.notDetermined;

  /// Blocked in the phone's or browser's settings (only they can undo it).
  bool get blocked => permission.value == AuthorizationStatus.denied;

  /// Asks to show notifications (the system's prompt; on the website it
  /// must follow a tap), then registers this device. True when allowed.
  Future<bool> enable() async {
    if (!supported) return false;
    problem.value = null;
    try {
      await _init();
      final settings = await FirebaseMessaging.instance.requestPermission();
      permission.value = settings.authorizationStatus;
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        return false;
      }
      await _register();
      return true;
    } catch (error) {
      _failed('Push notifications not enabled', error);
      return false;
    }
  }

  Future<void> _register() async {
    final session = _sessionToken;
    if (session == null) return;
    final pushToken = await FirebaseMessaging.instance
        .getToken(vapidKey: kIsWeb ? FirebaseWebConfig.vapidKey : null);
    if (pushToken == null) return;
    _pushToken = pushToken;
    await backend.registerPushDevice(
        backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
        token: session,
        pushToken: pushToken,
        platform: _platform);
    registered.value = true;
    problem.value = null;
    _refreshes ??= FirebaseMessaging.instance.onTokenRefresh.listen((fresh) {
      _pushToken = fresh;
      final session = _sessionToken;
      if (session == null) return;
      unawaited(GoogleOAuthConfig.loadBackendUrl()
          .then((url) => backend.registerPushDevice(
              backendUrl: url,
              token: session,
              pushToken: fresh,
              platform: _platform))
          .catchError((Object error) =>
              debugPrint('Push token not re-registered: $error')));
    });
  }

  /// Signing out ([sessionToken]: the one ending): this device stops
  /// getting that account's notifications.
  Future<void> stop(String? sessionToken) async {
    _sessionToken = null;
    registered.value = false;
    final pushToken = _pushToken;
    _pushToken = null;
    if (pushToken == null || sessionToken == null) return;
    try {
      await backend.forgetPushDevice(
          backendUrl: await GoogleOAuthConfig.loadBackendUrl(),
          token: sessionToken,
          pushToken: pushToken);
    } catch (error) {
      debugPrint('Push device not forgotten: $error');
    }
  }
}
