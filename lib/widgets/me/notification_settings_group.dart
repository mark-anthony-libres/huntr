import 'package:firebase_messaging/firebase_messaging.dart'
    show AuthorizationStatus;
import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../services/push_notifications.dart';
import '../../services/services_scope.dart';
import '../../state/app_state.dart';
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

class _NotificationSettingsGroupState extends State<NotificationSettingsGroup> {
  bool _saving = false;
  bool _enabling = false;

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

  @override
  Widget build(BuildContext context) {
    final chosen = AppScope.of(context).notifications;
    final push = PushNotifications.instance;
    return ValueListenableBuilder<AuthorizationStatus?>(
      valueListenable: push.permission,
      builder: (context, status, _) => SettingsGroup(children: [
        // this device: not asked yet, or blocked in its settings
        if (PushNotifications.supported &&
            status != null &&
            status != AuthorizationStatus.authorized)
          SettingsRow(
            key: const Key('notificationsDevice'),
            icon: Icons.notifications_off_outlined,
            title: push.blocked
                ? 'Blocked on this device'
                : 'Not on for this device',
            subtitle: push.blocked
                ? 'Allow notifications for HUNTR in your browser or phone '
                    'settings'
                : 'Allow HUNTR to show notifications here',
            trailing: push.blocked
                ? null
                : FilledButton(
                    key: const Key('notificationsAllow'),
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 38),
                        padding: const EdgeInsets.symmetric(horizontal: 16)),
                    onPressed: _enabling ? null : _allow,
                    child: const Text('Turn on'),
                  ),
          ),
        SettingsRow(
          icon: Icons.waving_hand_outlined,
          title: 'Taps',
          subtitle: 'When someone taps you',
          trailing: Switch(
            key: const Key('notifyTaps'),
            value: chosen.taps,
            onChanged: _saving ? null : (value) => _save(taps: value),
          ),
        ),
        SettingsRow(
          icon: Icons.chat_bubble_outline,
          title: 'Messages',
          subtitle: 'New messages (only who sent them, never what they say)',
          trailing: Switch(
            key: const Key('notifyMessages'),
            value: chosen.messages,
            onChanged: _saving ? null : (value) => _save(messages: value),
          ),
        ),
        SettingsRow(
          icon: Icons.auto_stories_outlined,
          title: 'Replies to your story',
          subtitle: 'When someone replies to your story',
          trailing: Switch(
            key: const Key('notifyStoryReplies'),
            value: chosen.storyReplies,
            onChanged: _saving ? null : (value) => _save(storyReplies: value),
          ),
        ),
      ]),
    );
  }
}
