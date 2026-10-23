import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/models.dart';

/// Why the device location could not be read, worded for the user.
class LocationException implements Exception {
  const LocationException(this.message);
  final String message;
}

/// Finds where the device is, asking for permission if needed.
typedef LocateDevice = Future<GeoPoint> Function();

Future<GeoPoint> locateDevice() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw const LocationException(
        'Location is turned off. Turn it on and try again.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied) {
    throw const LocationException(
        'Huntr needs your location to show people near you.');
  }
  if (permission == LocationPermission.deniedForever) {
    throw const LocationException(
        'Location access is blocked. Allow it in your settings and try again.');
  }
  try {
    final position = await _recentPosition() ??
        await Geolocator.getCurrentPosition(locationSettings: _quickFix);
    return GeoPoint(latitude: position.latitude, longitude: position.longitude);
  } catch (_) {
    throw const LocationException(
        'Your location could not be found. Check that location is on for this '
        'device and browser, then try again.');
  }
}

/// A position this old is still good enough to show people nearby.
const _maxPositionAge = Duration(minutes: 10);

/// "Nearby" needs roughly the right neighbourhood, not GPS precision, so ask
/// for a coarse fix: it comes back much faster, especially on computers,
/// which estimate location from Wi-Fi or IP instead of GPS.
final LocationSettings _quickFix = kIsWeb
    ? WebSettings(
        accuracy: LocationAccuracy.low,
        // Lets the browser answer at once with a position it already has.
        maximumAge: _maxPositionAge,
        timeLimit: Duration(seconds: 12),
      )
    : LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 12),
      );

/// The phone's last known position, if recent. Not available on web, where
/// the browser's own cache ([WebSettings.maximumAge]) does the same job.
Future<Position?> _recentPosition() async {
  if (kIsWeb) return null;
  try {
    final last = await Geolocator.getLastKnownPosition();
    if (last != null &&
        DateTime.now().difference(last.timestamp) <= _maxPositionAge) {
      return last;
    }
  } catch (_) {
    // No cached position on this platform; fall back to a fresh fix.
  }
  return null;
}
