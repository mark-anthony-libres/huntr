import 'package:flutter/material.dart';

import '../../services/huntr_backend.dart';
import '../../services/services_scope.dart';
import '../../state/app_state.dart';
import '../explore/explore_map.dart' show mapEnabled;
import 'settings_group.dart';

/// "Show my distance" and "Show when I'm online". Each change is saved to the
/// backend; the switch moves at once and moves back if the save fails.
class PrivacySettingsGroup extends StatefulWidget {
  const PrivacySettingsGroup({super.key, this.moreRows = const []});

  /// Shown after the switches, in the same card (e.g. Blocked users).
  final List<Widget> moreRows;

  @override
  State<PrivacySettingsGroup> createState() => _PrivacySettingsGroupState();
}

class _PrivacySettingsGroupState extends State<PrivacySettingsGroup> {
  /// A switch is locked while its change is being saved.
  bool _savingDistance = false;
  bool _savingOnline = false;
  bool _savingMap = false;

  Future<void> _save(
      {bool? showDistance, bool? showOnline, bool? showOnMap}) async {
    final app = AppScope.read(context);
    final profiles = ServicesScope.profilesOf(context);
    final token = app.sessionToken;
    final messenger = ScaffoldMessenger.of(context);
    final previous = (
      distance: app.showDistance,
      online: app.showOnline,
      map: app.showOnMap
    );

    app.updateMe(distance: showDistance, online: showOnline, onMap: showOnMap);
    if (profiles == null || token == null) return; // no backend: local only

    setState(() {
      if (showDistance != null) _savingDistance = true;
      if (showOnline != null) _savingOnline = true;
      if (showOnMap != null) _savingMap = true;
    });
    try {
      final saved = await profiles.updatePrivacy(token,
          showDistance: showDistance,
          showOnline: showOnline,
          showOnMap: showOnMap);
      app.updateMe(
          distance: saved.showDistance,
          online: saved.showOnline,
          onMap: saved.showOnMap);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          key: const Key('privacySaved'),
          content: Text(_savedMessage(
              showDistance: showDistance == null ? null : saved.showDistance,
              showOnline: showOnline == null ? null : saved.showOnline,
              showOnMap: showOnMap == null ? null : saved.showOnMap)),
        ));
    } on SessionRejectedException {
      app.updateMe(
          distance: previous.distance,
          online: previous.online,
          onMap: previous.map);
      app.endSession();
    } catch (error) {
      app.updateMe(
          distance: previous.distance,
          online: previous.online,
          onMap: previous.map);
      messenger.showSnackBar(SnackBar(
        content: Text(error is BackendException
            ? error.message
            : 'Your privacy setting could not be saved. Please try again.'),
      ));
    } finally {
      if (mounted) {
        setState(() {
          if (showDistance != null) _savingDistance = false;
          if (showOnline != null) _savingOnline = false;
          if (showOnMap != null) _savingMap = false;
        });
      }
    }
  }

  /// What was saved, for the confirmation shown after a change.
  static String _savedMessage(
      {bool? showDistance, bool? showOnline, bool? showOnMap}) {
    if (showOnMap != null) {
      return showOnMap
          ? "Saved. You're on the map (never your exact spot)."
          : "Saved. You're off the map.";
    }
    if (showDistance != null) {
      return showDistance
          ? 'Saved. Others can see your distance.'
          : 'Saved. Your distance is hidden.';
    }
    return showOnline == true
        ? 'Saved. Others can see when you\'re online.'
        : 'Saved. You\'re browsing without the green dot.';
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return SettingsGroup(children: [
      SettingsRow(
        icon: Icons.location_on_outlined,
        title: 'Show my distance',
        subtitle: 'Others see roughly how far away you are',
        trailing: Switch(
          key: const Key('privacyShowDistance'),
          value: app.showDistance,
          onChanged:
              _savingDistance ? null : (value) => _save(showDistance: value),
        ),
      ),
      // only while the map is on (MAP_ENABLED)
      if (mapEnabled)
        SettingsRow(
          icon: Icons.map_outlined,
          title: 'Show me on the map',
          subtitle: app.showDistance
              ? 'Others see you in your area, never your exact spot'
              : 'Off while your distance is hidden',
          trailing: Switch(
            key: const Key('privacyShowOnMap'),
            value: app.showOnMap && app.showDistance,
            onChanged: _savingMap || !app.showDistance
                ? null
                : (value) => _save(showOnMap: value),
          ),
        ),
      SettingsRow(
        icon: Icons.visibility_outlined,
        title: 'Show when I\'m online',
        subtitle: 'Turn off to browse without the green dot',
        trailing: Switch(
          key: const Key('privacyShowOnline'),
          value: app.showOnline,
          onChanged: _savingOnline ? null : (value) => _save(showOnline: value),
        ),
      ),
      ...widget.moreRows,
    ]);
  }
}
