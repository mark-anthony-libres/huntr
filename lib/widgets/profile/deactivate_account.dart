import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../services/services_scope.dart';
import '../../state/app_state.dart';

const _danger = Color(0xFFFF6B5B);

/// Asks for confirmation, then permanently deletes the account on the
/// backend and signs out. Nothing is deleted unless the user confirms.
Future<void> confirmAndDeactivateAccount(BuildContext context) async {
  final profiles = ServicesScope.profilesOf(context);
  final sessions = ServicesScope.sessionsOf(context);
  final app = AppScope.read(context);
  final token = app.sessionToken;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  if (profiles == null || token == null) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Deactivating your account needs the Huntr server.')));
    return;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => const _ConfirmDeactivation(),
  );
  if (confirmed != true) return;

  try {
    await profiles.deleteAccount(token);
  } on SessionRejectedException {
    // The session is already gone; nothing more can be deleted from here.
  } catch (error) {
    messenger.showSnackBar(SnackBar(
      content: Text(error is BackendException
          ? error.message
          : 'Your account could not be deactivated. Please try again.'),
    ));
    return;
  }
  await sessions?.forget();
  // back to the first screen (this may be Settings), then sign out and say so
  navigator.popUntil((route) => route.isFirst);
  app.endSession();
  // once the closing page has gone (a message shown during its exit would
  // appear on both screens)
  await Future<void>.delayed(const Duration(milliseconds: 450));
  messenger.showSnackBar(
      const SnackBar(content: Text('Your account and data were deleted.')));
}

class _ConfirmDeactivation extends StatelessWidget {
  const _ConfirmDeactivation();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Deactivate your account?'),
      content: const Text(
        'This permanently deletes your account, profile, photos, location '
        'and settings. It can\'t be undone.\n\n'
        'You can sign in again later, but you\'ll start with a new account.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('deactivateAccountConfirm'),
          style: TextButton.styleFrom(foregroundColor: _danger),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete permanently'),
        ),
      ],
    );
  }
}
