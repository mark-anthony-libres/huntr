import 'package:firebase_messaging/firebase_messaging.dart'
    show AuthorizationStatus;
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../flows/media_permission.dart' show openAppSettingsAndWait;

import '../../services/huntr_backend.dart';
import '../../services/push_notifications.dart';
import '../../services/services_scope.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import 'settings_group.dart';

/// Settings > Notifications: a switch for each kind (taps, messages, replies
/// to my story), saved on the backend for every device; and, while this
/// device doesn't show notifications yet, a way to allow them. Like the
/// privacy switches, a switch moves at once and moves back if the save
/// fails.
class NotificationSettingsGroup extends StatefulWidget {
  const NotificationSettingsGroup({super.key});

  @override
  State<NotificationSettingsGroup> createState() =>
      _NotificationSettingsGroupState();
}

class _NotificationSettingsGroupState extends State<NotificationSettingsGroup>
    with WidgetsBindingObserver {
  bool _saving = false;
  bool _enabling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // allowed since the last look (in the browser's or phone's settings)?
    unawaited(PushNotifications.instance.recheck());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // back from the settings where it was allowed: it turns on by itself
    if (state == AppLifecycleState.resumed) {
      unawaited(PushNotifications.instance.recheck());
    }
  }

  /// Blocked here: how to allow it (only the person can, in the browser's or
  /// phone's settings - an app can't ask again), then check again.
  Future<void> _howToAllow() async {
    final appOnPhone = !kIsWeb;
    final steps = _allowSteps();
    final again = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Allow notifications',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text(
                    "They're blocked for HUNTR here, so HUNTR can't ask again. "
                    'Turn them on yourself:',
                    style: TextStyle(color: HuntrColors.muted, height: 1.4)),
                const SizedBox(height: 14),
                for (final (i, step) in steps.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                              child: Text(step,
                                  style: const TextStyle(height: 1.4))),
                        ]),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('notificationsAllowed'),
                    onPressed: () => Navigator.of(context).pop(true),
                    child:
                        Text(appOnPhone ? 'Open settings' : "I've allowed it"),
                  ),
                ),
              ]),
        ),
      ),
    );
    if (again != true || !mounted) return;
    if (appOnPhone) await openAppSettingsAndWait();
    final on = await PushNotifications.instance.recheck();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(on
              ? 'Notifications are on for this device.'
              : 'Still blocked. Allow notifications for huntr.online, then '
                  'reload the page.')));
  }

  /// The steps for where this is: the Android app, or a browser on a
  /// phone (Android, iPhone) or a computer.
  static List<String> _allowSteps() {
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

  Future<void> _save({bool? taps, bool? messages, bool? storyReplies}) async {
    final app = AppScope.read(context);
    final profiles = ServicesScope.profilesOf(context);
    final token = app.sessionToken;
    final messenger = ScaffoldMessenger.of(context);
    final previous = app.notifications;
    app.updateNotifications(
        taps: taps, messages: messages, storyReplies: storyReplies);
    if (profiles == null || token == null) return; // no backend: local only
    setState(() => _saving = true);
    try {
      final saved = await profiles.updatePrivacy(token,
          notifyTaps: taps,
          notifyMessages: messages,
          notifyStoryReplies: storyReplies);
      app.updateNotifications(
          taps: saved.notifyTaps,
          messages: saved.notifyMessages,
          storyReplies: saved.notifyStoryReplies);
      final on = (taps ?? messages ?? storyReplies) ?? false;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            key: const Key('notificationsSaved'),
            content: Text(on
                ? 'Saved. Notifications on.'
                : 'Saved. Notifications off.')));
      // turning one on: this device should be allowed to show them
      if (on && PushNotifications.instance.undecided) {
        await PushNotifications.instance.enable();
      }
    } on SessionRejectedException {
      app.updateNotifications(
          taps: previous.taps,
          messages: previous.messages,
          storyReplies: previous.storyReplies);
      app.endSession();
    } catch (error) {
      app.updateNotifications(
          taps: previous.taps,
          messages: previous.messages,
          storyReplies: previous.storyReplies);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(error is BackendException
                ? error.message
                : 'Your notification setting could not be saved. Please try again.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _allow() async {
    setState(() => _enabling = true);
    final allowed = await PushNotifications.instance.enable();
    if (!mounted) return;
    setState(() => _enabling = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(allowed
            ? "Notifications are on for this device."
            : "Notifications aren't allowed for HUNTR here.")));
  }

  /// Where this device stands: on (registered), not asked, blocked, or a
  /// problem (with what went wrong) - each with what can be done.
  Widget _deviceRow(PushNotifications push) {
    final status = push.permission.value;
    final problem = push.problem.value;
    final on =
        status == AuthorizationStatus.authorized && push.registered.value;
    final (icon, title, subtitle, action) = problem != null
        ? (
            Icons.error_outline_rounded,
            "Couldn't turn on notifications here",
            problem,
            'Try again'
          )
        : on
            ? (
                Icons.notifications_active_outlined,
                'On for this device',
                'You get notifications here',
                null
              )
            : push.blocked
                ? (
                    Icons.notifications_off_outlined,
                    'Blocked on this device',
                    'Allow them in your browser or phone settings',
                    'How to allow'
                  )
                : (
                    Icons.notifications_off_outlined,
                    'Not on for this device',
                    'Allow HUNTR to show notifications here',
                    'Turn on'
                  );
    return SettingsRow(
      key: const Key('notificationsDevice'),
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: on
          ? const Icon(Icons.check_circle_rounded, color: Colors.white)
          : action == null
              ? null
              : FilledButton(
                  key: const Key('notificationsAllow'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 16)),
                  onPressed: _enabling
                      ? null
                      : push.blocked && problem == null
                          ? _howToAllow
                          : _allow,
                  child: Text(action),
                ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chosen = AppScope.of(context).notifications;
    final push = PushNotifications.instance;
    return ListenableBuilder(
      listenable:
          Listenable.merge([push.permission, push.registered, push.problem]),
      builder: (context, _) {
        // this device can't show them (blocked, not on yet): the kinds show
        // off and can't be changed here (they're kept on the account)
        final here = !PushNotifications.supported ||
            push.permission.value == AuthorizationStatus.authorized;
        final locked = _saving || !here;
        return SettingsGroup(children: [
          // this device: on, not yet, blocked, or why it couldn't start
          if (PushNotifications.supported) _deviceRow(push),
          SettingsRow(
            icon: Icons.waving_hand_outlined,
            title: 'Taps',
            subtitle: 'When someone taps you',
            trailing: Switch(
              key: const Key('notifyTaps'),
              value: here && chosen.taps,
              onChanged: locked ? null : (value) => _save(taps: value),
            ),
          ),
          SettingsRow(
            icon: Icons.chat_bubble_outline,
            title: 'Messages',
            subtitle: 'New messages (only who sent them, never what they say)',
            trailing: Switch(
              key: const Key('notifyMessages'),
              value: here && chosen.messages,
              onChanged: locked ? null : (value) => _save(messages: value),
            ),
          ),
          SettingsRow(
            icon: Icons.auto_stories_outlined,
            title: 'Replies to your story',
            subtitle: 'When someone replies to your story',
            trailing: Switch(
              key: const Key('notifyStoryReplies'),
              value: here && chosen.storyReplies,
              onChanged: locked ? null : (value) => _save(storyReplies: value),
            ),
          ),
        ]);
      },
    );
  }
}
