import 'package:flutter/material.dart';

import '../../screens/nsfw_guidelines_screen.dart';
import '../../services/huntr_backend.dart';
import '../../services/services_scope.dart';
import '../../state/app_state.dart';
import 'settings_group.dart';

/// "Don't show NSFW content": a switch, on by default, and What is
/// NSFW? under it. Saved on the backend; the choice moves at once and back
/// if the save fails.
class NsfwSetting extends StatefulWidget {
  const NsfwSetting({super.key});

  @override
  State<NsfwSetting> createState() => _NsfwSettingState();
}

class _NsfwSettingState extends State<NsfwSetting> {
  bool _saving = false;

  Future<void> _save(bool hide) async {
    final app = AppScope.read(context);
    if (_saving || app.hideNsfw == hide) return;
    final profiles = ServicesScope.profilesOf(context);
    final token = app.sessionToken;
    final messenger = ScaffoldMessenger.of(context);
    final previous = app.hideNsfw;
    app.setHideNsfw(hide);
    if (profiles == null || token == null) return; // no backend: local only
    setState(() => _saving = true);
    try {
      final saved = await profiles.updatePrivacy(token, hideNsfw: hide);
      app.setHideNsfw(saved.hideNsfw);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            key: const Key('nsfwSaved'),
            content: Text(saved.hideNsfw
                ? 'Saved. NSFW photos and videos stay blurred until you tap them.'
                : 'Saved. NSFW content is shown as it is.')));
    } on SessionRejectedException {
      app.setHideNsfw(previous);
      app.endSession();
    } catch (error) {
      app.setHideNsfw(previous);
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
    final hide = AppScope.of(context).hideNsfw;
    return SettingsGroup(children: [
      SettingsRow(
        icon: Icons.visibility_off_outlined,
        title: "Don't show NSFW content",
        subtitle: 'Blur adult content in Threads and warn before albums open',
        trailing: Switch(
          key: const Key('nsfwSwitch'),
          value: hide,
          onChanged: _saving ? null : _save,
        ),
      ),
      SettingsRow(
        key: const Key('openNsfwGuidelines'),
        icon: Icons.info_outline_rounded,
        title: 'What is NSFW?',
        subtitle: 'What counts and how HUNTR handles it',
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const NsfwGuidelinesScreen())),
      ),
    ]);
  }
}
