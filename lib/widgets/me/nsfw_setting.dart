import 'package:flutter/material.dart';

import '../../screens/nsfw_guidelines_screen.dart';
import '../../services/huntr_backend.dart';
import '../../services/services_scope.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import 'settings_group.dart';

/// "Show NSFW warning": Yes (the default) or No, and What is NSFW? under
/// it. Yes blurs NSFW photos and videos in Threads and warns before albums
/// open ([AppState.hideNsfw]). Saved on the backend; the choice moves at once and back
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
    // turning the warning off: asked first (a second step, as the stores
    // require for showing sexual content)
    if (!hide && !await confirmNsfwOff(context)) return;
    if (!mounted) return;
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
                ? 'Saved. NSFW content shows a warning first.'
                : 'Saved. NSFW content is shown without a warning.')));
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
        title: 'Show NSFW warning',
        subtitle: 'Blur adult posts and warn before albums',
        trailing: _YesNo(value: hide, onChanged: _saving ? null : _save),
      ),
      SettingsRow(
        key: const Key('openNsfwGuidelines'),
        icon: Icons.info_outline_rounded,
        title: 'What is NSFW?',
        subtitle: 'What counts and how HUNTR handles it',
        onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NsfwGuidelinesScreen())),
      ),
    ]);
  }
}

/// Two small buttons, Yes and No, the chosen one filled with the accent.
class _YesNo extends StatelessWidget {
  const _YesNo({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    Widget option(String label, bool choice) {
      final on = value == choice;
      return Material(
        color: on ? HuntrColors.orange : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          key: Key(choice ? 'nsfwWarningYes' : 'nsfwWarningNo'),
          borderRadius: BorderRadius.circular(999),
          onTap: onChanged == null || on ? null : () => onChanged!(choice),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 34),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(label,
                    style: TextStyle(
                        color: on ? Colors.black : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: 'Show NSFW warning: ${value ? 'Yes' : 'No'}',
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: HuntrColors.surfaceHigh,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: HuntrColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          option('Yes', true),
          option('No', false),
        ]),
      ),
    );
  }
}

/// Asks before NSFW content shows with no warning (Show NSFW warning: No):
/// true when confirmed. A second step, so it's never turned off by one tap.
Future<bool> confirmNsfwOff(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('nsfwOffConfirm'),
        title: const Text('Show NSFW content without a warning?'),
        content: const Text(
            'Photos and videos tagged NSFW may show nudity or sexual content. '
            'They will appear as they are, with no blur. You must be 18 or '
            'older. You can turn the warning back on in Settings at any time.'),
        actions: [
          TextButton(
              key: const Key('nsfwOffCancel'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep the warning')),
          TextButton(
              key: const Key('nsfwOffConfirmButton'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Show without warning')),
        ],
      ),
    ) ??
    false;
