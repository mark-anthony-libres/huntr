import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:huntr/main.dart';
import 'package:huntr/models/models.dart';
import 'package:huntr/services/huntr_backend.dart';
import 'package:huntr/services/location_service.dart';
import 'package:huntr/services/profile_service.dart';
import 'package:huntr/state/app_state.dart';

MyProfile _profile({int? age, double? latitude, double? longitude}) =>
    MyProfile(
      name: 'Mark Libres',
      displayName: 'Marky',
      age: age,
      latitude: latitude,
      longitude: longitude,
      lookingFor: const ['chat', 'dates'],
      onboarded: age != null && latitude != null && longitude != null,
    );

/// Serves a fixed profile and records what onboarding and app opens saved.
class _FakeProfiles extends ProfileService {
  _FakeProfiles(this.fetch);

  final Future<MyProfile> Function() fetch;
  OnboardingAnswers? saved;
  final List<GeoPoint> locationUpdates = [];

  @override
  Future<ProfileConfig> fetchConfig(String token) async => const ProfileConfig(
      bioMaxLength: 500, displayNameMaxLength: 12, minAge: 18, maxAge: 99);

  @override
  Future<MyProfile> fetchMine(String token) => fetch();

  @override
  Future<void> updateLocation(String token, GeoPoint location) async =>
      locationUpdates.add(location);

  @override
  Future<MyProfile> saveOnboarding(
      String token, OnboardingAnswers answers) async {
    saved = answers;
    return _profile(
        age: answers.age,
        latitude: answers.location.latitude,
        longitude: answers.location.longitude);
  }
}

const _here = GeoPoint(latitude: 10.3, longitude: 123.9);

Future<AppState> _open(WidgetTester tester, _FakeProfiles profiles,
    {LocateDevice? locate}) async {
  final state = AppState()..startSession('token');
  await tester.pumpWidget(HuntrApp(
    state: state,
    profiles: profiles,
    locate: locate ?? () async => _here,
  ));
  await tester.pumpAndSettle();
  return state;
}

void main() {
  testWidgets('a profile with age and location skips onboarding',
      (tester) async {
    final state = await _open(
        tester,
        _FakeProfiles(
            () async => _profile(age: 27, latitude: 14.6, longitude: 121)));
    expect(find.text('Explore'), findsWidgets);
    expect(state.myName, 'Marky');
    expect(state.myAge, 27);
    expect(state.myLookingFor, {LookingFor.chat, LookingFor.dates});
  });

  testWidgets('opening the app records the current location', (tester) async {
    final profiles = _FakeProfiles(
        () async => _profile(age: 27, latitude: 14.6, longitude: 121));
    final state = await _open(tester, profiles);
    expect(profiles.locationUpdates, [_here]);
    expect(state.myLocation, _here);
  });

  testWidgets('the app still opens when the location is unavailable',
      (tester) async {
    final profiles = _FakeProfiles(
        () async => _profile(age: 27, latitude: 14.6, longitude: 121));
    await _open(tester, profiles,
        locate: () async => throw const LocationException('denied'));
    expect(find.text('Explore'), findsWidgets);
    expect(profiles.locationUpdates, isEmpty);
  });

  testWidgets('a profile without location shows onboarding', (tester) async {
    final profiles = _FakeProfiles(() async => _profile(age: 27));
    await _open(tester, profiles);
    expect(find.text('Meet people\nright around you.'), findsOneWidget);
    expect(find.text('Explore'), findsNothing);
    expect(profiles.locationUpdates, isEmpty);
  });

  testWidgets('a profile without age shows onboarding', (tester) async {
    await _open(tester,
        _FakeProfiles(() async => _profile(latitude: 14.6, longitude: 121)));
    expect(find.text('Meet people\nright around you.'), findsOneWidget);
  });

  testWidgets('a rejected session goes back to sign-in', (tester) async {
    final state = await _open(tester,
        _FakeProfiles(() async => throw const SessionRejectedException()));
    expect(state.signedIn, isFalse);
    expect(find.text('Sign in with Google'), findsOneWidget);
    // (the message itself is replaced here by the Google plugin's own
    // error, since the plugin doesn't exist in widget tests)
    expect(find.byKey(const Key('googleSignInError')), findsOneWidget);
    expect(find.text('Explore'), findsNothing);
  });

  testWidgets('finishing onboarding saves the answers to the backend',
      (tester) async {
    final profiles = _FakeProfiles(() async => _profile());
    final state = await _open(tester, profiles);
    final next = find.byKey(const Key('onboardNext'));
    await tester.tap(next);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('onboardName')), 'Marky');
    await tester.tap(find.byKey(const Key('onboardAdult')));
    await tester.pump();
    await tester.tap(next);
    await tester.pumpAndSettle();
    await tester.tap(next);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboardLocation')));
    await tester.pumpAndSettle();
    await tester.tap(next);
    await tester.pumpAndSettle();

    expect(profiles.saved?.displayName, 'Marky');
    expect(profiles.saved?.location, _here);
    expect(state.onboarded, isTrue);
    expect(find.text('Explore'), findsWidgets);
  });

  test('saveMyOnboarding sends the answers with the session token', () async {
    final profile = await saveMyOnboarding(
      backendUrl: 'http://huntr.test/api',
      token: 'abc',
      displayName: null,
      age: 27,
      latitude: 14.6,
      longitude: 121,
      lookingFor: const ['chat'],
      client: MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.toString(),
            'http://huntr.test/api/profile/me/onboarding');
        expect(request.headers['Authorization'], 'Bearer abc');
        expect(jsonDecode(request.body), {
          'display_name': null,
          'age': 27,
          'latitude': 14.6,
          'longitude': 121,
          'looking_for': ['chat'],
        });
        return http.Response(
            jsonEncode({
              'data': {
                'name': 'Mark',
                'display_name': null,
                'age': 27,
                'latitude': 14.6,
                'longitude': 121,
                'looking_for': ['chat'],
                'onboarded': true,
              }
            }),
            200);
      }),
    );
    expect(profile.onboarded, isTrue);
    expect(profile.longitude, 121.0);
  });

  test('a 401 from the profile API means the session was rejected', () {
    expect(
      fetchMyProfile(
        backendUrl: 'http://huntr.test/api',
        token: 'old',
        client: MockClient((_) async => http.Response('', 401)),
      ),
      throwsA(isA<SessionRejectedException>()),
    );
  });

  testWidgets('onboarding limits the display name to the backend limit',
      (tester) async {
    await _open(tester, _FakeProfiles(() async => _profile()));
    await tester.tap(find.byKey(const Key('onboardNext')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('onboardName')), 'A very long display name');
    await tester.pump();
    final field =
        tester.widget<TextField>(find.byKey(const Key('onboardName')));
    expect(field.controller!.text, 'A very long ');
    expect(find.text('12/12'), findsOneWidget);
  });
}
