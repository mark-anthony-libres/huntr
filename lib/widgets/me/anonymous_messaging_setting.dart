import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../state/app_state.dart';
import '../../state/messaging_state.dart';
import 'settings_group.dart';

/// "Anonymous messaging": whether my first message to someone is anonymous.
/// Off, Message starts a direct chat that shows who I am, and I can't write
/// anonymously (nothing is deleted; people writing to me anonymously aren't
/// affected). Saved on the backend,
/// which enforces it; the switch moves back if the save fails.
class AnonymousMessagingSetting extends StatefulWidget {
  const AnonymousMessagingSetting({super.key});

  @override
  State<AnonymousMessagingSetting> createState() =>
      _AnonymousMessagingSettingState();
}

class _AnonymousMessagingSettingState extends State<AnonymousMessagingSetting> {
  bool _saving = false;

  Future<void> _save(bool enabled) async {
    final app = AppScope.read(context);
    final messaging = MessagingScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    final previous = app.anonymousMessaging;
    app.setAnonymousMessaging(enabled);
    if (messaging == null) return; // no backend: local only
    setState(() => _saving = true);
    try {
      final saved = await messaging.setAnonymousMessaging(enabled);
      if (saved != null) app.setAnonymousMessaging(saved);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(saved == true
                ? 'Saved! Your first messages are anonymous now 🎭'
                : 'Saved! Your first messages will show who you are.')));
      // the chat list shows where I can still write
      await messaging.refresh();
    } catch (error) {
      app.setAnonymousMessaging(previous);
      messenger.showSnackBar(SnackBar(
          content: Text(error is BackendException
              ? error.message
              : 'Your setting could not be saved. Please try again.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return SettingsGroup(children: [
      SettingsRow(
        icon: Icons.theater_comedy_outlined,
        title: 'Anonymous messaging',
        subtitle: 'Your first message to someone hides who you are. Off: it '
            'shows your profile (your chats are kept)',
        trailing: Switch(
          key: const Key('anonymousMessagingSwitch'),
          value: app.anonymousMessaging,
          onChanged: _saving ? null : _save,
        ),
      ),
    ]);
  }
}
