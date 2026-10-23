import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:huntr/main.dart';
import 'package:huntr/models/models.dart';
import 'package:huntr/services/huntr_backend.dart';
import 'package:huntr/services/profile_service.dart';
import 'package:huntr/services/session_service.dart';
import 'package:huntr/state/app_state.dart';

class _FakeProfiles extends ProfileService {
  final List<String> deletedWith = [];
  Object? failDeleteWith;

  @override
  Future<MyProfile> fetchMine(String token) async => const MyProfile(
        name: 'Mark',
        displayName: 'Marky',
        age: 27,
        latitude: 14.6,
        longitude: 121,
        lookingFor: ['chat'],
        onboarded: true,
      );

  @override
  Future<void> updateLocation(String token, GeoPoint location) async {}

  @override
  Future<void> deleteAccount(String token) async {
    if (failDeleteWith != null) throw failDeleteWith!;
    deletedWith.add(token);
  }
}

/// Keeps the session restored from "storage" and records forgetting it.
class _FakeSessions extends SessionService {
  bool forgotten = false;

  @override
  Future<String?> restoreVerifiedToken() async => 'token';

  @override
  Future<void> remember(String token) async {}

  @override
  Future<void> forget() async => forgotten = true;
}

Future<AppState> _openMe(
    WidgetTester tester, _FakeProfiles profiles, _FakeSessions sessions) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final state = AppState()..startSession('token');
  await tester.pumpWidget(HuntrApp(
    state: state,
    profiles: profiles,
    sessions: sessions,
    locate: () async => const GeoPoint(latitude: 14.6, longitude: 121),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Me'));
  await tester.pumpAndSettle();
  // account and terms are in Settings (the gear on Me)
  await tester.tap(find.byKey(const Key('openSettings')));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
      find.byKey(const Key('deactivateAccount')), 300,
      scrollable: find.byType(Scrollable).first);
  await tester.tap(find.byKey(const Key('deactivateAccount')));
  await tester.pumpAndSettle();
  return state;
}

void main() {
  testWidgets('deactivating asks for confirmation first', (tester) async {
    await _openMe(tester, _FakeProfiles(), _FakeSessions());
    expect(find.text('Deactivate your account?'), findsOneWidget);
    expect(find.textContaining("can't be undone"), findsOneWidget);
  });

  testWidgets('cancelling deletes nothing', (tester) async {
    final profiles = _FakeProfiles();
    final sessions = _FakeSessions();
    final state = await _openMe(tester, profiles, sessions);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(profiles.deletedWith, isEmpty);
    expect(sessions.forgotten, isFalse);
    expect(state.signedIn, isTrue);
  });

  testWidgets('confirming deletes the account and signs out', (tester) async {
    final profiles = _FakeProfiles();
    final sessions = _FakeSessions();
    final state = await _openMe(tester, profiles, sessions);
    await tester.tap(find.byKey(const Key('deactivateAccountConfirm')));
    await tester.pumpAndSettle();
    expect(profiles.deletedWith, ['token']);
    expect(sessions.forgotten, isTrue);
    expect(state.signedIn, isFalse);
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text('Your account and data were deleted.'), findsOneWidget);
  });

  testWidgets('a failed delete keeps the user signed in', (tester) async {
    final profiles = _FakeProfiles()
      ..failDeleteWith =
          const BackendException('Could not reach the Huntr server.');
    final sessions = _FakeSessions();
    final state = await _openMe(tester, profiles, sessions);
    await tester.tap(find.byKey(const Key('deactivateAccountConfirm')));
    await tester.pumpAndSettle();
    expect(find.text('Could not reach the Huntr server.'), findsOneWidget);
    expect(sessions.forgotten, isFalse);
    expect(state.signedIn, isTrue);
  });

  test('deleting sends DELETE with the session token', () async {
    await deleteMyAccount(
      backendUrl: 'http://huntr.test/api',
      token: 'abc',
      client: MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.toString(), 'http://huntr.test/api/profile/me');
        expect(request.headers['Authorization'], 'Bearer abc');
        return http.Response('{"data": {"deleted": true}}', 200);
      }),
    );
  });
}
