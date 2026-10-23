import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:huntr/main.dart';
import 'package:huntr/models/models.dart';
import 'package:huntr/services/agreement_service.dart';
import 'package:huntr/services/huntr_backend.dart';
import 'package:huntr/state/app_state.dart';

const _terms = '# Huntr Terms\n\nYou must be **18 or older**.';

/// Serves the agreement; fails the first [failures] loads.
class _FakeAgreements extends AgreementService {
  _FakeAgreements({this.failures = 0, this.text = _terms});

  int failures;
  final String text;
  int loads = 0;
  final List<String> declinedWith = [];
  Object? failDeclineWith;

  @override
  Future<String> fetch() async {
    loads++;
    if (failures > 0) {
      failures--;
      throw const BackendException('Could not reach the Huntr server.');
    }
    return text;
  }

  @override
  Future<void> decline(String token) async {
    if (failDeclineWith != null) throw failDeclineWith!;
    declinedWith.add(token);
  }
}

Future<void> _open(WidgetTester tester, AppState state,
    {_FakeAgreements? agreements}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(HuntrApp(
    state: state,
    agreements: agreements ?? _FakeAgreements(),
    locate: () async => const GeoPoint(latitude: 14.6, longitude: 121),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a new user sees the agreement before onboarding',
      (tester) async {
    await _open(tester, AppState()..startSession('token'));
    expect(find.text('Huntr Terms'), findsOneWidget); // rendered Markdown
    expect(find.text('Meet people\nright around you.'), findsNothing);
  });

  testWidgets('agreeing continues to onboarding', (tester) async {
    final state = AppState()..startSession('token');
    await _open(tester, state);
    await tester.tap(find.byKey(const Key('agreementAccept')));
    await tester.pumpAndSettle();
    expect(state.agreementAccepted, isTrue);
    expect(find.text('Meet people\nright around you.'), findsOneWidget);
  });

  testWidgets('declining deactivates the account and signs out',
      (tester) async {
    final agreements = _FakeAgreements();
    final state = AppState()..startSession('token');
    await _open(tester, state, agreements: agreements);
    await tester.tap(find.byKey(const Key('agreementDecline')));
    await tester.pumpAndSettle();
    expect(find.text('Decline and deactivate?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('agreementDeclineConfirm')));
    await tester.pumpAndSettle();
    expect(agreements.declinedWith, ['token']);
    expect(state.signedIn, isFalse);
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text('Meet people\nright around you.'), findsNothing);
  });

  testWidgets('cancelling the decline keeps the user on the agreement',
      (tester) async {
    final agreements = _FakeAgreements();
    final state = AppState()..startSession('token');
    await _open(tester, state, agreements: agreements);
    await tester.tap(find.byKey(const Key('agreementDecline')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(agreements.declinedWith, isEmpty);
    expect(state.signedIn, isTrue);
    expect(find.text('Huntr Terms'), findsOneWidget);
  });

  testWidgets('a failed decline is reported and does not sign out',
      (tester) async {
    final agreements = _FakeAgreements()
      ..failDeclineWith =
          const BackendException('Could not reach the Huntr server.');
    final state = AppState()..startSession('token');
    await _open(tester, state, agreements: agreements);
    await tester.tap(find.byKey(const Key('agreementDecline')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('agreementDeclineConfirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agreementDeclineError')), findsOneWidget);
    expect(state.signedIn, isTrue);
  });

  test('signing in to a deactivated account says so', () {
    expect(
      signInToBackendWithGoogle(
        backendUrl: 'http://huntr.test/api',
        idToken: 'google-id-token',
        client: MockClient((_) async => http.Response(
            '{"detail": "This account has been deactivated."}', 403)),
      ),
      throwsA(isA<BackendException>().having(
          (e) => e.message, 'message', 'This account has been deactivated.')),
    );
  });

  test('declining sends the session token', () async {
    await declineAgreement(
      backendUrl: 'http://huntr.test/api',
      token: 'abc',
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(
            request.url.toString(), 'http://huntr.test/api/agreement/decline');
        expect(request.headers['Authorization'], 'Bearer abc');
        return http.Response('{"data": {"deactivated": true}}', 200);
      }),
    );
  });

  testWidgets('agreeing unlocks only after scrolling to the end',
      (tester) async {
    final long = [
      '# HUNTR Terms',
      for (var i = 1; i <= 60; i++) ...['## Section $i', 'Rule number $i.'],
      'End of terms.',
    ].join(String.fromCharCodes([10, 10]));
    final state = AppState()..startSession('token');
    await _open(tester, state, agreements: _FakeAgreements(text: long));

    FilledButton accept() =>
        tester.widget<FilledButton>(find.byKey(const Key('agreementAccept')));
    expect(accept().onPressed, isNull);
    expect(find.text('Scroll to the end to agree'), findsOneWidget);

    // part way down is not enough
    await tester.drag(
        find.byKey(const Key('agreementContent')), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(accept().onPressed, isNull);

    await tester.scrollUntilVisible(find.text('End of terms.'), 500,
        scrollable: find.descendant(
            of: find.byKey(const Key('agreementContent')),
            matching: find.byType(Scrollable)));
    await tester.drag(
        find.byKey(const Key('agreementContent')), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(accept().onPressed, isNotNull);
    expect(find.text('Scroll to the end to agree'), findsNothing);

    await tester.tap(find.byKey(const Key('agreementAccept')));
    await tester.pumpAndSettle();
    expect(state.agreementAccepted, isTrue);
  });

  testWidgets('a short agreement that fits on screen can be agreed to',
      (tester) async {
    await _open(tester, AppState()..startSession('token'));
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('agreementAccept')))
            .onPressed,
        isNotNull);
  });

  testWidgets('agreeing is only possible once the text has loaded',
      (tester) async {
    final agreements = _FakeAgreements(failures: 1);
    await _open(tester, AppState()..startSession('token'),
        agreements: agreements);
    expect(find.text('Could not reach the Huntr server.'), findsOneWidget);
    final accept =
        tester.widget<FilledButton>(find.byKey(const Key('agreementAccept')));
    expect(accept.onPressed, isNull);

    await tester.tap(find.byKey(const Key('agreementRetry')));
    await tester.pumpAndSettle();
    expect(find.text('Huntr Terms'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('agreementAccept')))
            .onPressed,
        isNotNull);
  });

  testWidgets('users who finished onboarding are not asked again',
      (tester) async {
    final state = AppState()
      ..startSession('token')
      ..completeOnboarding(
          name: 'Mark', age: 27, lookingFor: {LookingFor.chat});
    final agreements = _FakeAgreements();
    await _open(tester, state, agreements: agreements);
    expect(find.text('Explore'), findsWidgets);
    expect(agreements.loads, 0);
  });

  testWidgets('the agreement can be read from the Me screen', (tester) async {
    final state = AppState()
      ..startSession('token')
      ..completeOnboarding(
          name: 'Mark', age: 27, lookingFor: {LookingFor.chat});
    await _open(tester, state);
    await tester.tap(find.text('Me'));
    await tester.pumpAndSettle();
    // account and terms are in Settings (the gear on Me)
    await tester.tap(find.byKey(const Key('openSettings')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('openAgreement')), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('openAgreement')));
    await tester.pumpAndSettle();
    expect(find.text('Huntr Terms'), findsOneWidget);
    // read-only: nothing to accept or decline
    expect(find.byKey(const Key('agreementAccept')), findsNothing);
    expect(find.byKey(const Key('agreementDecline')), findsNothing);
  });

  test('the agreement is fetched without a session token', () async {
    final content = await fetchAgreement(
      backendUrl: 'http://huntr.test/api',
      client: MockClient((request) async {
        expect(request.url.toString(), 'http://huntr.test/api/agreement');
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.Response('{"data": {"content": "# Terms"}}', 200);
      }),
    );
    expect(content, '# Terms');
  });
}
