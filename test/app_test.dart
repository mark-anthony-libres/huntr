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

  testWidgets('both chosen albums are sent when the request is approved',
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

    // send the request with my second album ("Weekend")
    final weekend = state.myAlbums[1];
    await tester.tap(find.byKey(const Key('sendRequest')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('pick-${weekend.id}')));
    await tester.enterText(
        find.byKey(const Key('requestNote')), 'Hi from the test');
    await tester.ensureVisible(find.byKey(const Key('confirmShare')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmShare')));
    await tester.pumpAndSettle();
    expect(state.connectionWith(p.id), Connection.outgoing);
    expect(state.requestWith(p.id)!.albumId, weekend.id);
    expect(find.text('Request sent · waiting'), findsOneWidget);

    // they approve: my chosen album and theirs are both sent, and the chat opens
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(state.canChat(p.id), isTrue);
    final msgs = state.conversationWith(p).messages;
    final albums = msgs.where((m) => m.kind == MessageKind.album).toList();
    expect(albums, hasLength(2));
    final mine = albums.firstWhere((m) => m.fromMe);
    final theirs = albums.firstWhere((m) => !m.fromMe);
    expect(mine.albumName, 'Weekend');
    expect(mine.album.map((x) => x.id), weekend.photos.map((x) => x.id));
    expect(p.albums.any((a) => a.name == theirs.albumName), isTrue);
    expect(msgs.first.text, 'Hi from the test');

    await tester.tap(find.text('Message'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('messageInput')), 'Hello!');
    await tester.pump();
    await tester.tap(find.byKey(const Key('sendButton')));
    await tester.pump();
    expect(msgs.last.text, 'Hello!');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  });

  testWidgets('accepting an incoming request: pick my album, receive theirs',
      (tester) async {
    final state = onboardedState();
    await tester.pumpWidget(HuntrApp(state: state));
    await tester.pumpAndSettle();
    final req = state.incomingRequests.first;
    final p = state.profileById(req.profileId)!;
    final mineToSend = state.myAlbums.first;

    await tester.tap(find.text('Chats'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('requestsTab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('accept-${p.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('pick-${mineToSend.id}')));
    await tester.tap(find.byKey(const Key('confirmShare')));
    await tester.pumpAndSettle();

    expect(state.canChat(p.id), isTrue);
    final albums = state
        .conversationWith(p)
        .messages
        .where((m) => m.kind == MessageKind.album)
        .toList();
    expect(albums.firstWhere((m) => m.fromMe).albumName, mineToSend.name);
    expect(albums.firstWhere((m) => !m.fromMe).albumName,
        p.albumById(req.albumId)!.name);
  });

  test('profile photos and albums can be managed', () {
    final state = AppState();
    state.addProfilePhoto(PhotoSubject.gym);
    final added = state.myPhotos.last.id;
    state.makeMainPhoto(added);
    expect(state.myPhotos.first.id, added);
    final a = state.createAlbum('Gym');
    state.addPhotoToAlbum(a.id, PhotoSubject.gym);
    expect(state.myAlbumById(a.id)!.photos, hasLength(1));
    state.renameAlbum(a.id, 'Gym days');
    expect(state.myAlbumById(a.id)!.name, 'Gym days');
    state.deleteAlbum(a.id);
    expect(state.myAlbumById(a.id), isNull);
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
