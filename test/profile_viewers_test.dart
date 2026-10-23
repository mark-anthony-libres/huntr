// Profile viewers: the Viewers tab beside Taps, and recording my visits.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huntr/models/models.dart';
import 'package:huntr/screens/profile_screen.dart';
import 'package:huntr/screens/taps_screen.dart';
import 'package:huntr/services/huntr_backend.dart';
import 'package:huntr/services/tap_service.dart';
import 'package:huntr/state/app_state.dart';
import 'package:huntr/state/tap_state.dart';
import 'package:huntr/theme.dart';

Profile _person(int id, String name) =>
    Profile.nearby({'id': id, 'display_name': name, 'age': 30});

ProfileViewer _viewer(int id, String name, int visits, Duration ago) =>
    ProfileViewer(
        person: _person(id, name),
        visits: visits,
        lastViewedAt: DateTime.now().subtract(ago));

class _FakeTaps extends TapService {
  _FakeTaps({this.viewers = const [], this.fail = false});

  List<ProfileViewer> viewers;
  bool fail;
  final recorded = <(int, String)>[];
  var viewerLoads = 0;

  @override
  Future<List<ReceivedTap>> fetchInbox(String token) async => [
        ReceivedTap(
            id: 1,
            sender: _person(50, 'Tapper'),
            answers: const [],
            isRead: false,
            receivedAt: DateTime.now()),
      ];

  @override
  Future<ViewerPage> fetchViewers(String token, {int offset = 0}) async {
    viewerLoads++;
    if (fail) throw const BackendException('Server is down.');
    return ViewerPage(viewers: viewers, nextOffset: null);
  }

  @override
  Future<void> recordView(String token, int userId, String visitId) async =>
      recorded.add((userId, visitId));
}

Future<TapState> _open(WidgetTester tester, _FakeTaps service, Widget home,
    {int? me}) async {
  final app = AppState()..startSession('t');
  app.myUserId = me;
  final taps = TapState(service: service, token: () => 't');
  await taps.refresh();
  await tester.pumpWidget(AppScope(
    state: app,
    child: TapScope(
      state: taps,
      child: MaterialApp(theme: buildHuntrTheme(), home: Scaffold(body: home)),
    ),
  ));
  await tester.pumpAndSettle();
  return taps;
}

void main() {
  test('visit times read naturally', () {
    final now = DateTime(2026, 10, 23, 12);
    expect(
        visitedAgo(now.subtract(const Duration(seconds: 20)), now), 'Just now');
    expect(visitedAgo(now.subtract(const Duration(minutes: 1)), now),
        '1 minute ago');
    expect(visitedAgo(now.subtract(const Duration(minutes: 10)), now),
        '10 minutes ago');
    expect(
        visitedAgo(now.subtract(const Duration(hours: 1)), now), '1 hour ago');
    expect(
        visitedAgo(now.subtract(const Duration(hours: 5)), now), '5 hours ago');
  });

  testWidgets('Taps stays as it was; Viewers lists who looked, latest first',
      (tester) async {
    final service = _FakeTaps(viewers: [
      _viewer(1, 'Ana', 5, const Duration(seconds: 10)),
      _viewer(2, 'Ben', 2, const Duration(minutes: 10)),
      _viewer(3, 'Cy', 1, const Duration(hours: 1)),
    ]);
    await _open(tester, service, const TapsScreen());
    // Taps first, unchanged
    expect(find.textContaining('Tapper'), findsOneWidget);
    expect(service.viewerLoads, 0, reason: 'nothing loaded until opened');

    await tester.tap(find.byKey(const Key('viewersTab')));
    await tester.pumpAndSettle();
    expect(service.viewerLoads, 1);
    expect(find.textContaining('Tapper'), findsNothing);
    final rows = [
      for (final id in [1, 2, 3])
        tester.getTopLeft(find.byKey(Key('viewer-user-$id'))).dy
    ];
    expect(rows, orderedEquals([...rows]..sort()),
        reason: 'in the given order');
    expect(find.text('5 visits'), findsOneWidget);
    expect(find.text('1 visit'), findsOneWidget);
    expect(find.text('Just now'), findsOneWidget);
    expect(find.text('10 minutes ago'), findsOneWidget);
    expect(find.text('1 hour ago'), findsOneWidget);

    // opened again: loaded again
    await tester.tap(find.byKey(const Key('tapsTab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('viewersTab')));
    await tester.pumpAndSettle();
    expect(service.viewerLoads, 2);
  });

  testWidgets('a viewer opens their profile', (tester) async {
    final service =
        _FakeTaps(viewers: [_viewer(1, 'Ana', 3, const Duration(minutes: 2))]);
    await _open(tester, service, const TapsScreen());
    await tester.tap(find.byKey(const Key('viewersTab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('viewer-user-1')));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  testWidgets('empty and failed states', (tester) async {
    final service = _FakeTaps(fail: true);
    await _open(tester, service, const TapsScreen());
    await tester.tap(find.byKey(const Key('viewersTab')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load your viewers"), findsOneWidget);

    service.fail = false;
    await tester.tap(find.byKey(const Key('viewersRetry')));
    await tester.pumpAndSettle();
    expect(find.text('No viewers yet'), findsOneWidget);
    expect(
        find.textContaining("When someone views your profile"), findsOneWidget);
  });

  testWidgets('someone viewing me refreshes an opened list', (tester) async {
    final service = _FakeTaps();
    final taps = await _open(tester, service, const TapsScreen());
    taps.handleEvent({'type': 'profile.viewed'});
    await tester.pump();
    expect(service.viewerLoads, 0, reason: 'not opened yet: nothing to do');
    await tester.tap(find.byKey(const Key('viewersTab')));
    await tester.pumpAndSettle();
    service.viewers = [_viewer(4, 'Dee', 1, Duration.zero)];
    taps.handleEvent({'type': 'profile.viewed'});
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('viewer-user-4')), findsOneWidget);
  });

  testWidgets('opening a profile records one visit, however often it rebuilds',
      (tester) async {
    final service = _FakeTaps();
    final person = _person(7, 'Sam');
    await _open(tester, service, ProfileScreen.person(person: person));
    // rebuilds of the same opening
    for (var i = 0; i < 3; i++) {
      await tester.pumpWidget(tester.widget(find.byType(AppScope)));
      await tester.pump();
    }
    expect(service.recorded.map((r) => r.$1), [7]);
    expect(service.recorded.single.$2.length, 32);
  });

  testWidgets('each opening is its own visit', (tester) async {
    final service = _FakeTaps();
    final person = _person(7, 'Sam');
    await _open(
        tester,
        service,
        Builder(
          builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ProfileScreen.person(person: person))),
              child: const Text('open')),
        ));
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.byType(ProfileScreen))).pop();
      await tester.pumpAndSettle();
    }
    expect(service.recorded.length, 2);
    expect(service.recorded.first.$2, isNot(service.recorded.last.$2));
  });

  testWidgets('my own profile is not a visit', (tester) async {
    final service = _FakeTaps();
    await _open(tester, service, ProfileScreen.person(person: _person(9, 'Me')),
        me: 9);
    expect(service.recorded, isEmpty);
  });
}
