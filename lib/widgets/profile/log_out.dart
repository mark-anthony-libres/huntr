import 'package:flutter/material.dart';

import '../../screens/entry_screen.dart' show signOutOfGoogle;
import '../../services/services_scope.dart';
import '../../state/app_state.dart';

/// Asks, then logs out: the session ends on the backend (when it can be
/// reached) and is forgotten on this device, this device's copies of my
/// photos and messages are cleared, and Google is signed out. The account
/// and everything in it stay on the server.
Future<void> confirmAndLogOut(BuildContext context) async {
  final sessions = ServicesScope.sessionsOf(context);
  final app = AppScope.read(context);
  final navigator = Navigator.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('logOutDialog'),
      title: const Text('Log out?'),
      content: const Text(
          'You can sign in again any time. Your account, chats and photos '
          'stay as they are.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
          key: const Key('logOutConfirm'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Log out'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  final token = app.sessionToken;
  if (token != null) await sessions?.logOut(token);
  await signOutOfGoogle();
  navigator.popUntil((route) => route.isFirst); // this may be Settings
  app.endSession(); // back to sign-in; clears my data on this device
}
