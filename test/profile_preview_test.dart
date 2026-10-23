import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huntr/main.dart';
import 'package:huntr/models/models.dart';
import 'package:huntr/state/app_state.dart';

Future<AppState> _openMe(WidgetTester tester,
    {bool showDistance = true}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final state = AppState()
    ..startSession('token')
    ..completeOnboarding(
        name: 'Marky',
        age: 21,
        lookingFor: {LookingFor.dates},
        bio: 'Coffee, gym and good vibes.')
    ..updateMe(distance: showDistance);
  await tester.pumpWidget(HuntrApp(state: state));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Me'));
  await tester.pumpAndSettle();
  return state;
}

void main() {
  testWidgets('the Me screen offers a preview of your profile', (tester) async {
    await _openMe(tester);
    expect(find.text('See how others see your profile'), findsOneWidget);
    expect(find.byKey(const Key('viewMyProfile')), findsOneWidget);
  });

  testWidgets('the preview shows your profile without other-user actions',
      (tester) async {
    await _openMe(tester);
    await tester.tap(find.byKey(const Key('viewMyProfile')));
    await tester.pumpAndSettle();
    expect(find.text('Marky, 21'), findsOneWidget);
    expect(find.text('Coffee, gym and good vibes.'), findsOneWidget);
    expect(find.text(LookingFor.dates.label), findsOneWidget);
    expect(find.byKey(const Key('profilePreviewNotice')), findsOneWidget);
    // nothing you'd do on someone else's profile
    expect(find.byKey(const Key('sendRequest')), findsNothing);
    expect(find.byTooltip('Add to favorites'), findsNothing);
    expect(find.byTooltip('More'), findsNothing);
    expect(find.text('Interests'), findsNothing); // empty sections hidden
  });

  testWidgets('the preview follows your privacy settings', (tester) async {
    await _openMe(tester, showDistance: false);
    await tester.tap(find.byKey(const Key('viewMyProfile')));
    await tester.pumpAndSettle();
    expect(find.text('Distance hidden'), findsOneWidget);
  });
}
