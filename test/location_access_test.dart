import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:huntr/services/location_permission.dart';

class _Permissions implements LocationPermissions {
  _Permissions({required this.grantOutlivesPrompt});

  LocationAccessStatus now = LocationAccessStatus.denied;

  @override
  final bool grantOutlivesPrompt;

  @override
  Future<LocationAccessStatus> check() async => now;

  /// What asking answers; null: granted. Never completed: the browser
  /// never answers.
  Future<LocationAccessStatus>? answer;

  @override
  Future<LocationAccessStatus> request() async =>
      answer == null ? now = LocationAccessStatus.granted : await answer!;

  @override
  bool get canOpenSettings => false;

  @override
  Future<void> openSettings() async {}
}

/// The browser, faked: what it says about the permission, and whether it
/// gives a position.
class _Browser extends GeolocatorPlatform {
  LocationPermission says = LocationPermission.deniedForever;

  /// Null: a position. Otherwise thrown.
  Exception? fails;
  int positionRequests = 0;

  @override
  Future<LocationPermission> checkPermission() async => says;

  @override
  Future<Position> getCurrentPosition(
      {LocationSettings? locationSettings}) async {
    positionRequests++;
    if (fails case final error?) throw error;
    return Position(
        latitude: 14.6,
        longitude: 121,
        timestamp: DateTime(2026),
        accuracy: 30,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0);
  }
}

void main() {
  group('in a browser', () {
    late _Browser browser;
    late GeolocatorPlatform before;
    setUp(() {
      before = GeolocatorPlatform.instance;
      GeolocatorPlatform.instance = browser = _Browser();
    });
    tearDown(() => GeolocatorPlatform.instance = before);

    test(
        'says blocked while location is allowed (Safari after a reload): '
        'the position lets them in', () async {
      final access = LocationAccess(const GeolocatorPermissions(web: true));
      await access.refresh();
      expect(access.status, LocationAccessStatus.granted);
      expect(browser.positionRequests, 1);
      // on another page, a recheck: still allowed
      await access.refresh();
      expect(access.granted, isTrue);
    });

    test('really blocked: blocked (the browser refuses the position)',
        () async {
      browser.fails = const PermissionDeniedException('denied');
      final access = LocationAccess(const GeolocatorPermissions(web: true));
      await access.refresh();
      expect(access.status, LocationAccessStatus.blocked);
    });

    test('allowed or not asked yet: no position is asked for on a check',
        () async {
      final access = LocationAccess(const GeolocatorPermissions(web: true));
      browser.says = LocationPermission.whileInUse;
      await access.refresh();
      expect(access.granted, isTrue);
      expect(browser.positionRequests, 0);
    });
  });

  test(
      'a request the browser never answers: allowed meanwhile in the site '
      'settings lets them in, and stays so', () async {
    final permissions = _Permissions(grantOutlivesPrompt: true);
    final never = Completer<LocationAccessStatus>();
    permissions.answer = never.future;
    final access = LocationAccess(permissions);
    await access.refresh();
    unawaited(access.request());
    await Future<void>.delayed(Duration.zero);
    expect(access.asking, isTrue);
    permissions.now = LocationAccessStatus.granted;
    await access.refresh();
    expect(access.granted, isTrue);
    // the request ends at last (given up): still allowed
    never.complete(LocationAccessStatus.unavailable);
    await Future<void>.delayed(Duration.zero);
    expect(access.granted, isTrue);
    expect(access.asking, isFalse);
  });

  test(
      'a browser that forgets it was allowed keeps it allowed; a block ends it',
      () async {
    final permissions = _Permissions(grantOutlivesPrompt: true);
    final access = LocationAccess(permissions);
    await access.request();
    expect(access.granted, isTrue);
    // the browser says "not asked yet" again (Aloha with its VPN on)
    permissions.now = LocationAccessStatus.denied;
    await access.refresh();
    expect(access.granted, isTrue);
    // blocked for the site: taken back
    permissions.now = LocationAccessStatus.blocked;
    await access.refresh();
    expect(access.status, LocationAccessStatus.blocked);
  });

  test('on a phone, allowed then not allowed is taken back', () async {
    final permissions = _Permissions(grantOutlivesPrompt: false);
    final access = LocationAccess(permissions);
    await access.request();
    permissions.now = LocationAccessStatus.denied;
    await access.refresh();
    expect(access.status, LocationAccessStatus.denied);
  });
}
