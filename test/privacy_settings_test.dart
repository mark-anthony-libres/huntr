import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:huntr/main.dart';
import 'package:huntr/models/models.dart';
import 'package:huntr/services/huntr_backend.dart';
import 'package:huntr/services/profile_service.dart';
import 'package:huntr/state/app_state.dart';

/// The backend, faked: a stored profile whose privacy settings can change.
class _FakeProfiles extends ProfileService {
  _FakeProfiles({this.stored = const PrivacySettings()});

  PrivacySettings stored;
  Object? failSaveWith;
  final List<({bool? showOnline, bool? showDistance})> saves = [];

  @override
  Future<MyProfile> fetchMine(String token) async => MyProfile(
        name: 'Mark',
        displayName: 'Marky',
        age: 21,
        latitude: 14.6,
        longitude: 121,
        lookingFor: const ['chat'],
        onboarded: true,
        privacy: stored,
      );

  @override
  Future<void> updateLocation(String token, GeoPoint location) async {}

  @override
  Future<PrivacySettings> updatePrivacy(String token,
      {bool? showOnline, bool? showDistance, bool? showOnMap}) async {
    saves.add((showOnline: showOnline, showDistance: showDistance));
    if (failSaveWith != null) throw failSaveWith!;
    stored = PrivacySettings(
      showOnline: showOnline ?? stored.showOnline,
      showDistance: showDistance ?? stored.showDistance,
    );
    return stored;
  }
}

Future<AppState> _openMe(WidgetTester tester, _FakeProfiles profiles,
    {bool settings = false}) async {
  tester.view.physicalSize = const Size(800, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final state = AppState()..startSession('token');
  await tester.pumpWidget(HuntrApp(
    state: state,
    profiles: profiles,
    locate: () async => const GeoPoint(latitude: 14.6, longitude: 121),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Me'));
  await tester.pumpAndSettle();
  if (settings) {
    // privacy is in Settings (the gear on Me)
    await tester.tap(find.byKey(const Key('openSettings')));
    await tester.pumpAndSettle();
  }
  return state;
}

bool _switchValue(WidgetTester tester, String key) =>
    tester.widget<Switch>(find.byKey(Key(key))).value;

void main() {
  testWidgets('saved privacy settings are loaded on sign-in', (tester) async {
    final state = await _openMe(
        tester,
        _FakeProfiles(
            stored:
                const PrivacySettings(showOnline: false, showDistance: false)),
        settings: true);
    expect(state.showOnline, isFalse);
    expect(state.showDistance, isFalse);
    expect(_switchValue(tester, 'privacyShowOnline'), isFalse);
    expect(_switchValue(tester, 'privacyShowDistance'), isFalse);
  });

  testWidgets('turning a switch off saves it', (tester) async {
    final profiles = _FakeProfiles();
    final state = await _openMe(tester, profiles, settings: true);
    await tester.tap(find.byKey(const Key('privacyShowDistance')));
    await tester.pumpAndSettle();
    expect(profiles.saves, [(showOnline: null, showDistance: false)]);
    expect(state.showDistance, isFalse);
    expect(profiles.stored.showDistance, isFalse);

    await tester.tap(find.byKey(const Key('privacyShowOnline')));
    await tester.pumpAndSettle();
    expect(profiles.saves.last, (showOnline: false, showDistance: null));
    expect(state.showOnline, isFalse);
  });

  testWidgets('a failed save moves the switch back and says so',
      (tester) async {
    final profiles = _FakeProfiles()
      ..failSaveWith =
          const BackendException('Could not reach the Huntr server.');
    final state = await _openMe(tester, profiles, settings: true);
    await tester.tap(find.byKey(const Key('privacyShowOnline')));
    await tester.pumpAndSettle();
    expect(state.showOnline, isTrue);
    expect(_switchValue(tester, 'privacyShowOnline'), isTrue);
    expect(find.text('Could not reach the Huntr server.'), findsOneWidget);
  });

  testWidgets('the profile preview uses the saved settings', (tester) async {
    await _openMe(
        tester,
        _FakeProfiles(
            stored:
                const PrivacySettings(showOnline: false, showDistance: false)));
    await tester.tap(find.byKey(const Key('viewMyProfile')));
    await tester.pumpAndSettle();
    expect(find.text('Distance hidden'), findsOneWidget);
    expect(find.text('Online now'), findsNothing);
  });

  test('only the changed setting is sent', () async {
    final saved = await updateMyPrivacy(
      backendUrl: 'http://huntr.test/api',
      token: 'abc',
      showDistance: false,
      client: MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(
            request.url.toString(), 'http://huntr.test/api/profile/me/privacy');
        expect(request.headers['Authorization'], 'Bearer abc');
        expect(jsonDecode(request.body), {'show_distance': false});
        return http.Response(
            '{"data": {"show_online": true, "show_distance": false}}', 200);
      }),
    );
    expect(saved.showOnline, isTrue);
    expect(saved.showDistance, isFalse);
  });
}
