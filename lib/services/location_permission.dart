import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'location_service.dart' show webLocationSettings;

/// Whether Huntr may use the device location.
enum LocationAccessStatus {
  /// Not checked yet.
  unknown,
  granted,

  /// Not allowed (yet): asking again can show the system dialog.
  denied,

  /// Denied for good (or restricted): the system won't ask again; only the
  /// device (or browser) settings can allow it.
  blocked,

  /// Asked, and the browser couldn't give a location: the computer's own
  /// location is off (or not allowed for the browser), or none came in time.
  unavailable,
}

/// The device's location permission (Android, iOS, web, desktop). Tests use
/// their own.
abstract class LocationPermissions {
  /// The current status, without asking the user.
  Future<LocationAccessStatus> check();

  /// Shows the system dialog when it still can; the resulting status.
  Future<LocationAccessStatus> request();

  /// This device can open Huntr's settings page (phones, desktop; not web).
  bool get canOpenSettings;

  Future<void> openSettings();
}

class GeolocatorPermissions implements LocationPermissions {
  const GeolocatorPermissions();

  static LocationAccessStatus _of(LocationPermission permission) =>
      switch (permission) {
        LocationPermission.always ||
        LocationPermission.whileInUse =>
          LocationAccessStatus.granted,
        LocationPermission.deniedForever => LocationAccessStatus.blocked,
        // not asked yet (or the browser can't tell): asking is possible
        LocationPermission.denied ||
        LocationPermission.unableToDetermine =>
          LocationAccessStatus.denied,
      };

  @override
  Future<LocationAccessStatus> check() async =>
      _of(await Geolocator.checkPermission());

  /// On the web, asking is asking for the position. Not through the plugin's
  /// requestPermission: it counts every failure as blocked for good (so the
  /// help said to unblock a site that wasn't blocked) and waits for ever
  /// when the browser doesn't answer.
  @override
  Future<LocationAccessStatus> request() async {
    if (!kIsWeb) return _of(await Geolocator.requestPermission());
    try {
      await Geolocator.getCurrentPosition(
          locationSettings: webLocationSettings);
      return LocationAccessStatus.granted;
    } on PermissionDeniedException {
      // blocked for this site; otherwise the computer doesn't let the
      // browser use location
      final now = await check();
      return now == LocationAccessStatus.blocked
          ? LocationAccessStatus.blocked
          : LocationAccessStatus.unavailable;
    } catch (_) {
      return LocationAccessStatus.unavailable;
    }
  }

  @override
  bool get canOpenSettings => !kIsWeb;

  @override
  Future<void> openSettings() => Geolocator.openAppSettings();
}

/// The app's location permission, kept up to date: checked when the app
/// starts and comes back to the foreground (e.g. from Settings), and
/// requested only when the user asks (Enable Location).
class LocationAccess extends ChangeNotifier {
  LocationAccess(this.permissions);

  final LocationPermissions permissions;

  LocationAccessStatus _status = LocationAccessStatus.unknown;
  LocationAccessStatus get status => _status;
  bool get granted => _status == LocationAccessStatus.granted;

  /// The user was just asked and didn't allow it (for the message).
  bool justDenied = false;

  bool _busy = false;

  /// Asking now (Enable Location, Try again): it can take a while.
  bool get asking => _busy;

  /// The status now (never shows a dialog). Some browsers can't say (the
  /// iPhone's WebKit browsers - Brave, in-app browsers like Messenger's -
  /// throw on the permission question): then, the first time, it counts as
  /// not asked yet, so Enable Location shows (asking for the position works
  /// there) instead of a check that never ends. Once known, a failed recheck
  /// keeps what was known.
  Future<void> refresh() async {
    if (_busy) return;
    try {
      final status = await permissions.check();
      // the browser may say it's allowed while the computer still gives no
      // location: only Try again (or a block) changes that
      if (_status == LocationAccessStatus.unavailable &&
          status != LocationAccessStatus.blocked) {
        return;
      }
      _set(status);
    } catch (error) {
      debugPrint('Location permission not checked: $error');
      if (_status == LocationAccessStatus.unknown) {
        _set(LocationAccessStatus.denied);
      }
    }
  }

  /// Asks the user (Enable Location): the system dialog when it still can.
  Future<void> request() async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      final status = await permissions.request();
      justDenied = status != LocationAccessStatus.granted;
      _set(status, notify: false);
      notifyListeners();
    } catch (error) {
      debugPrint('Location permission not requested: $error');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> openSettings() async {
    try {
      await permissions.openSettings();
    } catch (error) {
      debugPrint('Settings not opened: $error');
    }
  }

  void _set(LocationAccessStatus status, {bool notify = true}) {
    if (status == LocationAccessStatus.granted) justDenied = false;
    if (status == _status) return;
    _status = status;
    if (notify) notifyListeners();
  }
}
