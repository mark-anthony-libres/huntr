import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:huntr/main.dart';
import 'package:huntr/services/huntr_backend.dart';
import 'package:huntr/services/session_service.dart';
import 'package:huntr/state/app_state.dart';

/// Answers restore with a fixed outcome instead of storage and the backend.
class _FakeSessions extends SessionService {
  _FakeSessions(this.restore);

  final Future<String?> Function() restore;

  @override
  Future<String?> restoreVerifiedToken() => restore();

  @override
  Future<void> remember(String token) async {}
}

void main() {
  group('isBackendSessionValid', () {
    Future<bool> verifyWith(int status) => isBackendSessionValid(
          backendUrl: 'http://huntr.test/api/',
          token: 'abc',
          client: MockClient((request) async {
            expect(request.url.toString(), 'http://huntr.test/api/auth/verify');
            expect(request.headers['Authorization'], 'Bearer abc');
            return http.Response('', status);
          }),
        );

    test('accepts an active session', () async {
      expect(await verifyWith(200), isTrue);
    });

    test('rejects an expired or revoked session', () async {
      expect(await verifyWith(401), isFalse);
      expect(await verifyWith(403), isFalse);
    });

    test('reports when the backend cannot answer', () async {
      expect(verifyWith(500), throwsA(isA<BackendException>()));
    });
  });

  testWidgets('a verified saved session skips sign-in', (tester) async {
    final state = AppState();
    await tester.pumpWidget(HuntrApp(
        state: state, sessions: _FakeSessions(() async => 'saved-token')));
    await tester.pumpAndSettle();
    expect(state.sessionToken, 'saved-token');
    expect(find.text('Meet people\nright around you.'), findsOneWidget);
  });

  testWidgets('a rejected saved session goes back to sign-in', (tester) async {
    final state = AppState();
    await tester.pumpWidget(
        HuntrApp(state: state, sessions: _FakeSessions(() async => null)));
    await tester.pumpAndSettle();
    expect(state.signedIn, isFalse);
    expect(find.text('Sign in with Google'), findsOneWidget);
  });

  testWidgets('an unreachable backend goes to sign-in with the reason',
      (tester) async {
    final state = AppState();
    await tester.pumpWidget(HuntrApp(
        state: state,
        sessions: _FakeSessions(() async => throw const BackendException(
            'Could not reach the Huntr server.'))));
    await tester.pumpAndSettle();
    expect(state.signedIn, isFalse);
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.byKey(const Key('googleSignInError')), findsOneWidget);
  });
}
