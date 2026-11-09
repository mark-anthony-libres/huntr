import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../services/services_scope.dart';
import '../../state/app_state.dart';
import 'settings_group.dart';

/// "I have a place": shows "Has a place" on my profile and Explore card,
/// and lets people find me with Explore's "Has a place" filter. Saved on the
/// backend; the switch moves back if the save fails.
class HasPlaceSetting extends StatefulWidget {
  const HasPlaceSetting({super.key});

  @override
  State<HasPlaceSetting> createState() => _HasPlaceSettingState();
}

class _HasPlaceSettingState extends State<HasPlaceSetting> {
  bool _saving = false;

  Future<void> _save(bool hasPlace) async {
    final app = AppScope.read(context);
    final profiles = ServicesScope.profilesOf(context);
    final messenger = ScaffoldMessenger.of(context);
    final token = app.sessionToken;
    final previous = app.myHasPlace;
    app.setHasPlace(hasPlace);
    if (profiles == null || token == null) return; // no backend: local only
    setState(() => _saving = true);
    try {
      app.setHasPlace(await profiles.updatePlace(token, hasPlace));
    } catch (error) {
      app.setHasPlace(previous);
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
        icon: Icons.home_rounded,
        title: app.myHasPlace ? 'I have a place' : "I don't have a place",
        subtitle: app.myHasPlace
            ? 'Your profile shows that you have a place'
            : 'Turn on if you have a place',
        trailing: Switch(
          key: const Key('hasPlaceSwitch'),
          value: app.myHasPlace,
          onChanged: _saving ? null : _save,
        ),
      ),
    ]);
  }
}
