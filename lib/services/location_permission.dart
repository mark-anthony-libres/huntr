import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

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

  @override
  Future<LocationAccessStatus> request() async =>
      _of(await Geolocator.requestPermission());

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

  /// The status now (never shows a dialog).
  Future<void> refresh() async {
    if (_busy) return;
    try {
      _set(await permissions.check());
    } catch (error) {
      debugPrint('Location permission not checked: $error');
    }
  }

  /// Asks the user (Enable Location): the system dialog when it still can.
  Future<void> request() async {
    if (_busy) return;
    _busy = true;
    try {
      final status = await permissions.request();
      justDenied = status != LocationAccessStatus.granted;
      _set(status, notify: false);
      notifyListeners();
    } catch (error) {
      debugPrint('Location permission not requested: $error');
    } finally {
      _busy = false;
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
