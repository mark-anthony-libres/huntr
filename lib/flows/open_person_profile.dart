import 'package:flutter/material.dart';

import '../models/models.dart';
import '../screens/profile_screen.dart';
import '../services/services_scope.dart';
import '../state/app_state.dart';

/// Opens someone's profile at once with what's known of them, then with all
/// of it (photos, stats, ...) once loaded. [onMessage], given the profile
/// page's context, replaces opening a new chat (e.g. going back to the one it
/// came from). Completes when the profile is closed.
Future<void> openPersonProfile(BuildContext context, Profile p,
    {void Function(BuildContext page)? onMessage}) {
  final person = ValueNotifier<Profile>(p);
  final closed = Navigator.of(context)
      .push(MaterialPageRoute(
          builder: (_) => ValueListenableBuilder<Profile>(
              valueListenable: person,
              builder: (page, profile, _) => ProfileScreen.person(
                  person: profile,
                  onMessage:
                      onMessage == null ? null : () => onMessage(page)))))
      .whenComplete(person.dispose);
  final explore = ServicesScope.exploreOf(context);
  final token = AppScope.read(context).sessionToken;
  final userId = p.backendId;
  if (explore != null && token != null && userId != null) {
    explore.fetchPerson(token, userId).then((full) {
      try {
        person.value = full;
      } on FlutterError {
        // closed meanwhile (the notifier is disposed)
      }
    }, onError: (Object error) {
      debugPrint('Profile $userId could not be loaded: $error');
    });
  }
  return closed;
}
