// The blue check: a verified person has it by their name (from the
// backend's "verified"), and tapping it explains what it means.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huntr/models/models.dart';
import 'package:huntr/screens/profile_screen.dart';
import 'package:huntr/state/app_state.dart';
import 'package:huntr/theme.dart';
import 'package:huntr/widgets/verified_badge.dart';

Profile _person({bool? verified}) => Profile.nearby({
      'id': 7,
      'display_name': 'Sam',
      'age': 30,
      'bio': 'Hello there',
      if (verified != null) 'verified': verified,
    });

Future<void> _open(WidgetTester tester, Profile person,
    {double width = 390}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = AppState()..startSession('t');
  app.myUserId = 99;
  await tester.pumpWidget(AppScope(
    state: app,
    child: MaterialApp(
        theme: buildHuntrTheme(), home: ProfileScreen.person(person: person)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('profiles read it from the backend (none from older ones)', () {
    expect(_person(verified: true).verified, isTrue);
    expect(_person(verified: false).verified, isFalse);
    expect(_person().verified, isFalse);
  });

  testWidgets('a verified person has the blue check by their name',
      (tester) async {
    await _open(tester, _person(verified: true));
    final check = tester.widget<Icon>(find.byKey(const Key('verifiedBadge')));
    expect(check.color, verifiedBlue);
    final name = tester.getRect(find.text('Sam, 30'));
    final badge = tester.getRect(find.byKey(const Key('verifiedBadge')));
    expect(badge.left, greaterThanOrEqualTo(name.right));
    expect((badge.center.dy - name.center.dy).abs(), lessThan(name.height));
  });

  testWidgets('nobody else has it', (tester) async {
    await _open(tester, _person(verified: false));
    expect(find.byKey(const Key('verifiedBadge')), findsNothing);
  });

  testWidgets('tapping it explains it in plain words', (tester) async {
    await _open(tester, _person(verified: true));
    await tester.tap(find.byKey(const Key('verifiedBadgeButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('verifiedInfo')), findsOneWidget);
    expect(find.text('Sam is verified'), findsOneWidget);
    expect(find.textContaining('ID document'), findsOneWidget);
    expect(find.textContaining('fake accounts'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('verifiedInfo')), findsNothing);
  });

  testWidgets('hovering says so', (tester) async {
    await _open(tester, _person(verified: true));
    final tooltip = tester.widget<Tooltip>(find.ancestor(
        of: find.byKey(const Key('verifiedBadge')),
        matching: find.byType(Tooltip)));
    expect(tooltip.message, contains('identity confirmed'));
  });

  for (final width in [280.0, 1280.0]) {
    testWidgets('fits at $width wide', (tester) async {
      await _open(
          tester,
          Profile.nearby({
            'id': 7,
            'display_name': 'A very long display name indeed',
            'age': 30,
            'verified': true,
          }),
          width: width);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('verifiedBadge')), findsOneWidget);
    });
  }
}
