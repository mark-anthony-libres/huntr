import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huntr/main.dart';
import 'package:huntr/models/models.dart';
import 'package:huntr/state/app_state.dart';

void main() {
  AppState onboardedState() {
    final s = AppState(replyDelay: const Duration(milliseconds: 200));
    s.completeOnboarding(name: 'Mark', age: 27, lookingFor: {LookingFor.chat});
    return s;
  }

  testWidgets('onboarding needs a name and the 18+ confirmation', (tester) async {
    await tester.pumpWidget(HuntrApp(state: AppState()));
    await tester.tap(find.byKey(const Key('onboardNext')));
    await tester.pumpAndSettle();

    final next = find.byKey(const Key('onboardNext'));
    expect(tester.widget<FilledButton>(next).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('onboardName')), 'Mark');
    await tester.tap(find.byKey(const Key('onboardAdult')));
    await tester.pump();
    expect(tester.widget<FilledButton>(next).onPressed, isNotNull);

    await tester.tap(next);
    await tester.pumpAndSettle();
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('Explore'), findsWidgets);
  });

  testWidgets('explore shows people and the online filter narrows the grid', (tester) async {
    final state = onboardedState();
    await tester.pumpWidget(HuntrApp(state: state));
    await tester.pumpAndSettle();

    final everyone = state.visibleProfiles.length;
    expect(everyone, greaterThan(10));
    await tester.tap(find.text('Online now'));
    await tester.pumpAndSettle();
    expect(state.visibleProfiles.length, lessThan(everyone));
    expect(state.visibleProfiles.every((p) => p.online), isTrue);
  });

  testWidgets('sending a message shows it and gets a reply', (tester) async {
    final state = onboardedState();
    await tester.pumpWidget(HuntrApp(state: state));
    await tester.pumpAndSettle();

    final first = state.visibleProfiles.first;
    await tester.tap(find.bySemanticsLabel(RegExp('^${first.name},')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Message'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('messageInput')), 'Hello from the test');
    await tester.pump();
    await tester.tap(find.byKey(const Key('sendButton')));
    await tester.pump();
    expect(find.text('Hello from the test'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 50));
    final conv = state.conversationWith(first);
    expect(conv.messages.where((m) => !m.fromMe), isNotEmpty);
    expect(conv.messages.firstWhere((m) => m.fromMe).status, MessageStatus.read);
  });

  test('filters match by age, distance and search', () {
    final state = AppState();
    state.filters = const ExploreFilters(ageRange: RangeValues(20, 25), maxDistanceKm: 5);
    expect(state.visibleProfiles.every((p) => p.age >= 20 && p.age <= 25 && p.distanceKm <= 5), isTrue);
    state.filters = const ExploreFilters(query: 'coffee');
    expect(state.visibleProfiles, isNotEmpty);
  });

  test('blocking removes the person everywhere', () {
    final state = AppState();
    final p = state.conversations.first.profile;
    state.toggleFavorite(p.id);
    state.block(p.id);
    expect(state.visibleProfiles.any((x) => x.id == p.id), isFalse);
    expect(state.favoriteProfiles.any((x) => x.id == p.id), isFalse);
    expect(state.conversations.any((c) => c.profile.id == p.id), isFalse);
  });
}
