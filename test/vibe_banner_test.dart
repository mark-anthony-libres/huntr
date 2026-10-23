import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huntr/main.dart';
import 'package:huntr/models/models.dart';
import 'package:huntr/state/app_state.dart';

void main() {
  AppState onboardedState() {
    final s = AppState(replyDelay: const Duration(milliseconds: 200))
      ..startSession('test-session-token');
    s.completeOnboarding(name: 'Mark', age: 27, lookingFor: {LookingFor.chat});
    return s;
  }

  Future<AppState> openExplore(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = onboardedState();
    await tester.pumpWidget(HuntrApp(state: state));
    await tester.pumpAndSettle();
    return state;
  }

  testWidgets('swiping "Find your vibe" left hides it', (tester) async {
    final state = await openExplore(tester);
    expect(find.byKey(const Key('findYourVibe')), findsOneWidget);

    await tester.drag(
        find.byKey(const Key('dismissVibeBanner')), const Offset(-700, 0));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('findYourVibe')), findsNothing);
    expect(state.showVibeBanner, isFalse);
  });

  testWidgets('swiping "Find your vibe" right hides it', (tester) async {
    final state = await openExplore(tester);

    await tester.drag(
        find.byKey(const Key('dismissVibeBanner')), const Offset(700, 0));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('findYourVibe')), findsNothing);
    expect(state.showVibeBanner, isFalse);
  });

  testWidgets('the Settings switch turns "Find your vibe" off and back on',
      (tester) async {
    final state = await openExplore(tester);

    await tester.tap(find.text('Me'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('openSettings')));
    await tester.pumpAndSettle();

    final toggle = find.byKey(const Key('settingsShowVibeBanner'));
    expect(tester.widget<Switch>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(state.showVibeBanner, isFalse);
    expect(tester.widget<Switch>(toggle).value, isFalse);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(state.showVibeBanner, isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Explore').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('findYourVibe')), findsOneWidget);
  });

  testWidgets('hiding "Find your vibe" shows it off in Settings',
      (tester) async {
    final state = await openExplore(tester);
    state.showVibeBanner = false;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('findYourVibe')), findsNothing);

    await tester.tap(find.text('Me'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('openSettings')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Switch>(find.byKey(const Key('settingsShowVibeBanner')))
            .value,
        isFalse);
  });
}
