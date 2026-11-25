import 'package:firebase_messaging/firebase_messaging.dart'
    show AuthorizationStatus;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../flows/media_permission.dart' show openAppSettingsAndWait;
import '../services/app_install/app_install.dart';
import '../services/push_notifications.dart';
import '../theme.dart';
import 'install_banner.dart' show AddToHomeScreenSteps;

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
/// The website in an iPhone's (or iPad's) browser, not added to its Home
/// Screen: there it can't have notifications at all.
bool get needsHomeScreenForNotifications =>
    kIsWeb && AppInstall.isIos && !AppInstall.isInstalled;

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

/// Shows [NotificationsOffSheet] over what's on screen (not covering it);
/// true when notifications got turned on.
Future<bool> showNotificationsOff(BuildContext context) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => const NotificationsOffSheet(),
    ) ==
    true;

/// A reminder that notifications are off on this device, as a sheet: what
/// they're for, and turning them on - the device's own question when it
/// hasn't been answered (or was put off), else, when they're blocked, how to
/// allow them and checking again (on an iPhone's Safari: adding HUNTR to the
/// Home Screen). Pops with true when they're on.
class NotificationsOffSheet extends StatefulWidget {
  const NotificationsOffSheet({super.key});

  @override
  State<NotificationsOffSheet> createState() => _NotificationsOffSheetState();
}

class _NotificationsOffSheetState extends State<NotificationsOffSheet> {
  PushNotifications get _push => PushNotifications.instance;
  bool _busy = false;

  /// Still off after trying (said under the button).
  String? _still;

  bool get _blocked => _push.permission.value == AuthorizationStatus.denied;

  /// The website in an iPhone's Safari: notifications come only to HUNTR
  /// added to the Home Screen (and opened from there).
  bool get _needsHomeScreen => needsHomeScreenForNotifications;

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
    final homeScreen = _needsHomeScreen;
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('notificationsOff'),
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: HuntrColors.orange.withValues(alpha: 0.14),
                ),
                child: Icon(Icons.notifications_off_outlined,
                    size: 32, color: HuntrColors.orange),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Notifications are off',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            const Text(
                'Turn them on to know when someone taps you, messages '
                'you, reacts to your message or replies to your story. '
                'A notification says who, never what they wrote.',
                textAlign: TextAlign.center,
                style: TextStyle(color: HuntrColors.muted, height: 1.45)),
            if (homeScreen) ...[
              const SizedBox(height: 24),
              const Text(
                  'On an iPhone, HUNTR can send notifications only once '
                  "it's on your Home Screen:",
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              const AddToHomeScreenSteps(
                  after: 'Then open HUNTR from your Home Screen and turn '
                      'on notifications there.'),
            ] else if (blocked) ...[
              const SizedBox(height: 24),
              const Text(
                  "They're blocked for HUNTR on this device, so HUNTR "
                  "can't ask. Turn them on yourself:",
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              NumberedSteps(steps: notificationAllowSteps()),
            ],
            const SizedBox(height: 24),
            if (!homeScreen)
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
              onPressed: _busy ? null : () => Navigator.of(context).pop(false),
              child: Text(homeScreen ? 'Got it' : 'Not now'),
            ),
            const SizedBox(height: 4),
            const Text('You can change this any time in Settings.',
                textAlign: TextAlign.center,
                style: TextStyle(color: HuntrColors.muted, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}
