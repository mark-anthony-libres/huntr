import 'package:flutter_test/flutter_test.dart';
import 'package:huntr/services/location_permission.dart';

class _Permissions implements LocationPermissions {
  _Permissions({required this.grantOutlivesPrompt});

  LocationAccessStatus now = LocationAccessStatus.denied;

  @override
  final bool grantOutlivesPrompt;

  @override
  Future<LocationAccessStatus> check() async => now;

  @override
  Future<LocationAccessStatus> request() async =>
      now = LocationAccessStatus.granted;

  @override
  bool get canOpenSettings => false;

  @override
  Future<void> openSettings() async {}
}

void main() {
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
