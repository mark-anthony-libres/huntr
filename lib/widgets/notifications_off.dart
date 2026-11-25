import 'package:firebase_messaging/firebase_messaging.dart'
    show AuthorizationStatus;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../flows/media_permission.dart' show openAppSettingsAndWait;
import '../services/push_notifications.dart';
import '../theme.dart';

/// How to allow notifications for HUNTR where this is (once they're
/// blocked, only the person can): the Android app, or a browser on a phone
/// (Android, iPhone) or a computer.
List<String> notificationAllowSteps() {
  final android = defaultTargetPlatform == TargetPlatform.android;
  final ios = defaultTargetPlatform == TargetPlatform.iOS;
  if (!kIsWeb) {
    return const [
      'Tap Open settings below.',
      'Go to Notifications.',
      'Turn on notifications for HUNTR, then come back.',
    ];
  }
  if (android) {
    return const [
      'Tap the icon at the left of the address bar (next to huntr.online).',
      'Tap Permissions (or Site settings), then Notifications.',
      'Choose Allow, then come back and tap I\'ve allowed it.',
    ];
  }
  if (ios) {
    return const [
      'Open the iPhone Settings app, then Notifications.',
      'Find HUNTR (added to your Home Screen) and turn on Allow '
          'Notifications.',
      'Come back and tap I\'ve allowed it.',
    ];
  }
  return const [
    'Click the icon at the left of the address bar (next to huntr.online).',
    'Set Notifications to Allow (in Site settings if it isn\'t listed).',
    'Reload the page if it asks, then tap I\'ve allowed it.',
  ];
}

/// [steps], numbered.
class NumberedSteps extends StatelessWidget {
  const NumberedSteps({super.key, required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, step) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: HuntrColors.orange,
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(step, style: const TextStyle(height: 1.4))),
              ]),
            ),
        ],
      );
}

/// A reminder that notifications are off on this device: what they're for,
/// and turning them on - the device's own question when it hasn't been
/// answered (or was put off), else, when they're blocked, how to allow them
/// and checking again. Pops with true when they're on.
class NotificationsOffScreen extends StatefulWidget {
  const NotificationsOffScreen({super.key});

  @override
  State<NotificationsOffScreen> createState() => _NotificationsOffScreenState();
}

class _NotificationsOffScreenState extends State<NotificationsOffScreen> {
  PushNotifications get _push => PushNotifications.instance;
  bool _busy = false;

  /// Still off after trying (said under the button).
  String? _still;

  bool get _blocked => _push.permission.value == AuthorizationStatus.denied;

  Future<void> _turnOn() async {
    setState(() {
      _busy = true;
      _still = null;
    });
    bool on;
    if (_blocked) {
      // only the person can allow them: the phone's settings, or the browser's
      if (!kIsWeb) await openAppSettingsAndWait();
      on = await _push.recheck();
    } else {
      on = await _push.enable();
    }
    if (!mounted) return;
    if (on) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _still = _blocked
          ? (kIsWeb
              ? 'Still off. Allow notifications for huntr.online, then reload '
                  'the page.'
              : 'Still off. Turn on notifications for HUNTR in Settings.')
          : 'Notifications weren\'t turned on.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _blocked;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              key: const Key('notificationsOff'),
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: HuntrColors.orange.withValues(alpha: 0.14),
                      ),
                      child: Icon(Icons.notifications_off_outlined,
                          size: 42, color: HuntrColors.orange),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text('Notifications are off',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  const Text(
                      'Turn them on to know when someone taps you, messages '
                      'you, reacts to your message or replies to your story. '
                      'A notification says who, never what they wrote.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: HuntrColors.muted, height: 1.45)),
                  if (blocked) ...[
                    const SizedBox(height: 24),
                    const Text(
                        "They're blocked for HUNTR on this device, so HUNTR "
                        "can't ask. Turn them on yourself:",
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    NumberedSteps(steps: notificationAllowSteps()),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('notificationsTurnOn'),
                    onPressed: _busy ? null : _turnOn,
                    style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Text(!blocked
                            ? 'Turn on notifications'
                            : kIsWeb
                                ? "I've allowed it"
                                : 'Open settings'),
                  ),
                  if (_still != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(_still!,
                          key: const Key('notificationsStillOff'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: HuntrColors.coral)),
                    ),
                  const SizedBox(height: 6),
                  TextButton(
                    key: const Key('notificationsNotNow'),
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Not now'),
                  ),
                  const SizedBox(height: 4),
                  const Text('You can change this any time in Settings.',
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: HuntrColors.muted, fontSize: 12.5)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
