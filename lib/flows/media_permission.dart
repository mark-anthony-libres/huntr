import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;

/// Runs a photo / video / camera pick that may need the device's camera,
/// microphone or photos permission. The system asks the first time (the
/// picker does that); after a denial this explains why it's needed, and
/// offers Try again (which asks again whenever the system still can) and
/// Open Settings (phones). Coming back from Settings runs the pick again by
/// itself. Null when the user gives up (or cancels the pick).
///
/// Only the action that needs the permission waits; nothing else is blocked.
Future<T?> withMediaPermission<T>(
    BuildContext context, Future<T?> Function() pick) async {
  while (true) {
    try {
      return await pick();
    } on PlatformException catch (error) {
      final what = _needed(error.code);
      if (what == null) rethrow; // not a permission problem
      if (!context.mounted) return null;
      final choice = await _explain(context, what);
      if (!context.mounted || choice == null) return null;
      if (choice == _Choice.settings) {
        await openAppSettingsAndWait();
        if (!context.mounted) return null;
      }
      // try again (it asks again when the system still can)
    }
  }
}

enum _Choice { retry, settings }

/// What the denied permission is for, worded for the user.
({String name, String why})? _needed(String code) => switch (code) {
      'camera_access_denied' => (
          name: 'Camera',
          why: 'Huntr needs the camera to take a photo or video for you to '
              'send.'
        ),
      'microphone_access_denied' => (
          name: 'Microphone',
          why: 'Huntr needs the microphone to record sound with your video.'
        ),
      'photo_access_denied' => (
          name: 'Photos',
          why: 'Huntr needs access to your photos to send them or add them to '
              'an album.'
        ),
      _ => null,
    };

Future<_Choice?> _explain(
    BuildContext context, ({String name, String why}) what) {
  final settings = !kIsWeb;
  return showDialog<_Choice>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('mediaPermission'),
      title: Text('${what.name} access needed'),
      content: Text(settings
          ? '${what.why} If no request appears when you try again, allow it '
              'for Huntr in Settings.'
          : '${what.why} Allow it for this site in your browser, then try '
              'again.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Not now')),
        if (settings)
          TextButton(
              key: const Key('mediaPermissionSettings'),
              onPressed: () => Navigator.of(context).pop(_Choice.settings),
              child: const Text('Open Settings')),
        FilledButton(
            key: const Key('mediaPermissionRetry'),
            onPressed: () => Navigator.of(context).pop(_Choice.retry),
            child: const Text('Try again')),
      ],
    ),
  );
}

/// Opens Huntr's settings page (phones) and waits until the user comes
/// back.
Future<void> openAppSettingsAndWait() async {
  final back = Completer<void>();
  final listener = AppLifecycleListener(onResume: () {
    if (!back.isCompleted) back.complete();
  });
  try {
    await Geolocator.openAppSettings();
    // if the app wasn't left (or doesn't report it), don't wait forever
    await back.future.timeout(const Duration(minutes: 10), onTimeout: () {});
  } catch (error) {
    debugPrint('Settings not opened: $error');
  } finally {
    listener.dispose();
  }
}
