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

  testWidgets('onboarding needs a name and the 18+ confirmation',
      (tester) async {
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

  testWidgets('explore shows people and the online filter narrows the grid',
      (tester) async {
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

  testWidgets(
      'a chat request must be accepted before messaging; accepting shares the album',
      (tester) async {
    final state = AppState(
        replyDelay: const Duration(milliseconds: 200),
        acceptDelay: const Duration(seconds: 30));
    state.completeOnboarding(
        name: 'Mark', age: 27, lookingFor: {LookingFor.chat});
    await tester.pumpWidget(HuntrApp(state: state));
    await tester.pumpAndSettle();

    final p = state.visibleProfiles
        .firstWhere((x) => state.connectionWith(x.id) == Connection.none);
    expect(state.canChat(p.id), isFalse);
    state.send(p, 'sneaky');
    expect(state.conversationWith(p).messages, isEmpty,
        reason: 'no messaging before approval');

    final tile = find.bySemanticsLabel(RegExp('^${p.name},'));
    await tester.scrollUntilVisible(tile, 200,
        scrollable: find
            .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable))
            .first);
    await tester.ensureVisible(tile.first);
    await tester.pumpAndSettle();
    await tester.tap(tile.first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sendRequest')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('requestNote')), 'Hi from the test');
    await tester.tap(find.byKey(const Key('confirmRequest')));
    await tester.pumpAndSettle();
    expect(state.connectionWith(p.id), Connection.outgoing);
    expect(find.text('Request sent · waiting'), findsOneWidget);

    // they accept: their album arrives and the chat opens up
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(state.canChat(p.id), isTrue);
    final msgs = state.conversationWith(p).messages;
    final album = msgs.firstWhere((m) => m.kind == MessageKind.album);
    expect(album.fromMe, isFalse);
    expect(album.album, p.album);
    expect(msgs.first.text, 'Hi from the test');

    await tester.tap(find.text('Message'));
    await tester.pumpAndSettle();
    expect(find.text('${p.name} shared their album'), findsOneWidget);
    expect(find.text('View ${p.album.length} photos'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('messageInput')), 'Hello!');
    await tester.pump();
    await tester.tap(find.byKey(const Key('sendButton')));
    await tester.pump();
    expect(state.conversationWith(p).messages.last.text, 'Hello!');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(
        msgs.where((m) => !m.fromMe && m.kind == MessageKind.text), isNotEmpty);
  });

  testWidgets('accepting an incoming request sends my album to them',
      (tester) async {
    final state = onboardedState();
    await tester.pumpWidget(HuntrApp(state: state));
    await tester.pumpAndSettle();
    final req = state.incomingRequests.first;
    final p = state.profileById(req.profileId)!;

    await tester.tap(find.text('Chats'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('requestsTab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('accept-${p.id}')));
    await tester.pumpAndSettle();

    expect(state.canChat(p.id), isTrue);
    final album = state
        .conversationWith(p)
        .messages
        .firstWhere((m) => m.kind == MessageKind.album);
    expect(album.fromMe, isTrue);
    expect(album.album.map((x) => x.id), state.myAlbum.map((x) => x.id));
    expect(find.text('You shared your album'), findsOneWidget);
  });

  test('declining and cancelling clear the request', () {
    final state = AppState(acceptDelay: const Duration(hours: 1));
    final incoming = state.incomingRequests.first.profileId;
    state.declineRequest(incoming);
    expect(state.connectionWith(incoming), Connection.none);
    final p = state.visibleProfiles
        .firstWhere((x) => state.connectionWith(x.id) == Connection.none);
    state.sendRequest(p);
    expect(state.outgoingRequests.single.profileId, p.id);
    state.cancelRequest(p.id);
    expect(state.connectionWith(p.id), Connection.none);
  });

  test('filters match by age, distance and search', () {
    final state = AppState();
    state.filters =
        const ExploreFilters(ageRange: RangeValues(20, 25), maxDistanceKm: 5);
    expect(
        state.visibleProfiles
            .every((p) => p.age >= 20 && p.age <= 25 && p.distanceKm <= 5),
        isTrue);
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
