import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'location_service.dart' show LocationException;

/// Where the device is now, for sharing in a chat (not the coarse fix the
/// profile uses).
class DevicePosition {
  const DevicePosition(
      {required this.latitude, required this.longitude, this.accuracy});

  final double latitude;
  final double longitude;

  /// Metres.
  final double? accuracy;

  /// Metres to [other].
  double distanceTo(DevicePosition other) => Geolocator.distanceBetween(
      latitude, longitude, other.latitude, other.longitude);
}

/// The device's position: once, or as it moves. Tests use their own.
class DeviceLocation {
  const DeviceLocation();

  /// Asks for permission if needed; throws [LocationException] with a
  /// message for the user.
  Future<DevicePosition> current() async {
    await _allowed();
    try {
      final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 20)));
      return _of(p);
    } catch (_) {
      throw const LocationException(
          'Your location could not be found. Check that location is on, then '
          'try again.');
    }
  }

  /// Positions as the device moves (only when it moved [minDistance]
  /// metres, where the platform supports it).
  Stream<DevicePosition> watch({int minDistance = 25}) async* {
    await _allowed();
    yield* Geolocator.getPositionStream(
            locationSettings: LocationSettings(
                accuracy: LocationAccuracy.high, distanceFilter: minDistance))
        .map(_of);
  }

  static DevicePosition _of(Position p) => DevicePosition(
      latitude: p.latitude, longitude: p.longitude, accuracy: p.accuracy);

  static Future<void> _allowed() async {
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
          'Huntr needs your location to share it in this chat.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
          'Location access is blocked. Allow it in your settings and try again.');
    }
  }
}
