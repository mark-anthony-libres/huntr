// Nearby: the feed (sort, distance filter, states), writing a post, the
// discussion (threaded comments, replies), hearts, delete and report - with
// the backend faked.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huntr/screens/nearby_post_screen.dart';
import 'package:huntr/screens/nearby_screen.dart';
import 'package:huntr/services/huntr_backend.dart';
import 'package:huntr/services/nearby_service.dart';
import 'package:huntr/services/services_scope.dart';
import 'package:huntr/state/app_state.dart';
import 'package:huntr/theme.dart';

final _now = DateTime.now();

NearbyPost _post(int id,
        {String name = 'ChillCorgi',
        int? distance = 300,
        bool mine = false,
        int comments = 0,
        int likes = 0,
        bool liked = false}) =>
    NearbyPost(
        id: id,
        author: AnonymousName(name: name, avatar: 'fox'),
        body: 'Post $id',
        distanceM: mine ? 120 : distance,
        createdAt: _now.subtract(const Duration(minutes: 12)),
        likeCount: likes,
        liked: liked,
        commentCount: comments,
        mine: mine,
        radiusM: mine ? 5000 : null);

NearbyComment _comment(int id, String name, String body,
        {int? parent,
        List<NearbyComment> replies = const [],
        bool mine = false}) =>
    NearbyComment(
        id: id,
        parentId: parent,
        author: AnonymousName(name: name, avatar: 'cat'),
        body: body,
        distanceM: 1200,
        createdAt: _now.subtract(const Duration(minutes: 5)),
        likeCount: 0,
        liked: false,
        mine: mine,
        byAuthor: false,
        replies: replies);

class _FakeNearby extends NearbyService {
  List<NearbyPost> posts = [];
  int? next;
  Object? feedError;
  final calls = <String>[];
  List<NearbyComment> comments = [];

  @override
  Future<NearbyFeedPage> feed(String token,
      {String sort = 'nearby', int? withinM, int offset = 0}) async {
    calls.add('feed $sort ${withinM ?? '-'} $offset');
    if (feedError != null) throw feedError!;
    return NearbyFeedPage(
        posts: offset == 0 ? posts : [_post(99, name: 'LostPenguin')],
        nextOffset: offset == 0 ? next : null);
  }

  @override
  Future<NearbyFeedPage> mine(String token, {int offset = 0}) async =>
      NearbyFeedPage(posts: [
        for (final p in posts)
          if (p.mine) p
      ], nextOffset: null);

  @override
  Future<NearbyPost> post(String token,
      {required String body,
      required int radiusM,
      AnonymousName? as,
      List<int> tagIds = const []}) async {
    calls.add('post $radiusM ${as?.name} $body');
    return NearbyPost(
        id: 50,
        author: const AnonymousName(name: 'HappyMango', avatar: 'bear'),
        body: body,
        distanceM: null,
        createdAt: DateTime.now(),
        likeCount: 0,
        liked: false,
        commentCount: 0,
        mine: true,
        radiusM: radiusM);
  }

  @override
  Future<NearbyDiscussion> discussion(String token, int postId) async =>
      NearbyDiscussion(
          post: posts.firstWhere((p) => p.id == postId), comments: comments);

  @override
  Future<NearbyDiscussion> comment(String token, int postId,
      {required String body, int? parentId}) async {
    calls.add('comment $postId ${parentId ?? '-'} $body');
    if (parentId == null) {
      comments = [_comment(30, 'SunnyWolf', body, mine: true), ...comments];
    } else {
      comments = [
        for (final c in comments)
          c.id == parentId
              ? _comment(c.id, c.author.name, c.body, replies: [
                  ...c.replies,
                  _comment(31, 'SunnyWolf', body, parent: parentId, mine: true)
                ])
              : c
      ];
    }
    return discussion(token, postId);
  }

  @override
  Future<({int count, bool liked})> like(String token, int postId,
      {int? commentId, required bool like}) async {
    calls.add('like $postId ${commentId ?? '-'} $like');
    return (count: like ? 1 : 0, liked: like);
  }

  @override
  Future<void> delete(String token, {int? postId, int? commentId}) async =>
      calls.add('delete ${postId ?? '-'} ${commentId ?? '-'}');

  @override
  Future<void> report(String token, int postId,
          {int? commentId, required String reason}) async =>
      calls.add('report $postId ${commentId ?? '-'} $reason');
}

Future<void> _open(WidgetTester tester, _FakeNearby service,
    {Widget? home}) async {
  tester.view.physicalSize = const Size(500, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(
    state: AppState()..startSession('token'),
    child: ServicesScope(
      profiles: null,
      agreements: null,
      nearby: service,
      child: MaterialApp(
          theme: buildHuntrTheme(),
          home: home ?? const Scaffold(body: NearbyScreen())),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('distances, radii and times read naturally', () {
    expect(nearbyDistanceLabel(0), 'here');
    expect(nearbyDistanceLabel(320), '320 m');
    expect(nearbyDistanceLabel(700), '700 m');
    expect(nearbyDistanceLabel(2300), '2.3 km');
    expect(nearbyDistanceLabel(5000), '5 km');
    expect(nearbyRadiusLabel(500), '500 m');
    expect(nearbyRadiusLabel(10000), '10 km');
    final now = DateTime(2026, 1, 1, 12);
    expect(
        nearbyAgo(now.subtract(const Duration(seconds: 20)), now), 'just now');
    expect(nearbyAgo(now.subtract(const Duration(minutes: 12)), now),
        '12 min ago');
    expect(nearbyAgo(now.subtract(const Duration(hours: 3)), now), '3 h ago');
  });

  testWidgets(
      'the feed: random names, rounded distances, counts; Latest; pages',
      (tester) async {
    final service = _FakeNearby()
      ..posts = [
        _post(1, distance: 320, comments: 14, likes: 28),
        _post(2, name: 'CuriousFrog', distance: 2300),
        _post(3, name: 'Me', mine: true),
      ]
      ..next = 20;
    await _open(tester, service);
    expect(find.text('ChillCorgi'), findsOneWidget);
    expect(find.text('320 m away'), findsOneWidget);
    expect(find.text('2.3 km away'), findsOneWidget);
    expect(find.text('  ·  12m'), findsWidgets);
    expect(find.text('You · 120 m away'), findsOneWidget);
    expect(find.byKey(const Key('nearbyComments-1')), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    expect(find.text('28'), findsOneWidget);
    // the next page as the end comes into view
    await tester.scrollUntilVisible(
        find.byKey(const Key('nearbyPost-99')), 300);
    expect(service.calls, contains('feed nearby - 20'));

    await tester.tap(find.byKey(const Key('nearbySortLatest')));
    await tester.pumpAndSettle();
    expect(service.calls, contains('feed latest - 0'));

    await tester.tap(find.byKey(const Key('nearbyWithin')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nearbyWithin-1000')));
    await tester.pumpAndSettle();
    expect(service.calls, contains('feed latest 1000 0'));
    expect(find.text('1 km'), findsOneWidget);
  });

  testWidgets(
      'without a location: says so; empty: invites a post; errors retry',
      (tester) async {
    final service = _FakeNearby()
      ..feedError = const NearbyNoLocationException('Turn on your location.');
    await _open(tester, service);
    expect(find.byKey(const Key('nearbyNoLocation')), findsOneWidget);
    service.feedError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('nearbyEmpty')), findsOneWidget);
    service.feedError = const BackendException('Server trouble.');
    await tester.drag(
        find.byKey(const Key('nearbyList')), const Offset(0, 400));
    await tester.pumpAndSettle();
    // a failed refresh keeps what was shown
    expect(find.byKey(const Key('nearbyEmpty')), findsOneWidget);
  });

  testWidgets('a new thread: counter, limit, distance, and my posts below',
      (tester) async {
    final service = _FakeNearby()
      ..posts = [_post(1), _post(2, name: 'NightCat', mine: true, comments: 7)];
    await _open(tester, service);
    await tester.tap(find.byKey(const Key('nearbyCompose')));
    await tester.pumpAndSettle();
    expect(find.text('New thread'), findsOneWidget);
    // my posts, below
    expect(find.text('My posts'), findsOneWidget);
    expect(find.byKey(const Key('nearbyMine-2')), findsOneWidget);
    expect(find.byKey(const Key('nearbyMine-1')), findsNothing);
    expect(find.text('Within 5 km'), findsOneWidget);
    final post = find.byKey(const Key('nearbyPost'));
    expect(tester.widget<FilledButton>(post).onPressed, isNull); // empty
    await tester.enterText(find.byKey(const Key('nearbyText')), 'x' * 501);
    await tester.pump();
    expect(find.text('501/500'), findsOneWidget);
    expect(tester.widget<FilledButton>(post).onPressed, isNull); // too long
    await tester.enterText(
        find.byKey(const Key('nearbyText')), 'Any good coffee here?');
    await tester.pump();
    expect(find.text('21/500'), findsOneWidget);
    // how far: 1 km
    await tester.tap(find.byKey(const Key('nearbyRadius')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nearbyRadius-1000')));
    await tester.pumpAndSettle();
    expect(find.text('Within 1 km'), findsOneWidget);
    await tester.tap(post);
    await tester.pumpAndSettle();
    expect(service.calls.last, 'post 1000 null Any good coffee here?');
    // back on the feed, mine first
    expect(find.text('Posted as HappyMango 🎭'), findsOneWidget);
    final mine = tester.getTopLeft(find.byKey(const Key('nearbyPost-50'))).dy;
    expect(mine,
        lessThan(tester.getTopLeft(find.byKey(const Key('nearbyPost-1'))).dy));
  });

  testWidgets('the discussion: threaded, comment and reply to the right one',
      (tester) async {
    final service = _FakeNearby()
      ..posts = [_post(1, comments: 2)]
      ..comments = [
        _comment(10, 'SunnyWolf', 'Try Bean Hub!',
            replies: [_comment(11, 'PeachBunny', '+1 Bean Hub', parent: 10)]),
      ];
    await _open(tester, service);
    await tester.tap(find.byKey(const Key('nearbyPost-1')));
    await tester.pumpAndSettle();
    expect(find.byType(NearbyPostScreen), findsOneWidget);
    expect(find.text('Try Bean Hub!'), findsOneWidget);
    // the reply sits under its comment, indented
    final top = tester.getTopLeft(find.byKey(const Key('nearbyComment-10')));
    final reply = tester.getTopLeft(find.byKey(const Key('nearbyComment-11')));
    expect(reply.dy, greaterThan(top.dy));
    expect(reply.dx, greaterThan(top.dx));

    await tester.enterText(
        find.byKey(const Key('nearbyCommentInput')), 'Kape Tayo!');
    await tester.pump();
    await tester.tap(find.byKey(const Key('nearbySendComment')));
    await tester.pumpAndSettle();
    expect(service.calls.last, 'comment 1 - Kape Tayo!');
    expect(find.text('Kape Tayo!'), findsOneWidget);

    await tester
        .tap(find.byKey(const Key('nearbyReply-11'))); // a reply's Reply
    await tester.pumpAndSettle();
    expect(find.text('Replying to SunnyWolf'), findsOneWidget); // its thread
    await tester.enterText(
        find.byKey(const Key('nearbyCommentInput')), 'Thanks!');
    await tester.pump();
    await tester.tap(find.byKey(const Key('nearbySendComment')));
    await tester.pumpAndSettle();
    expect(service.calls.last, 'comment 1 10 Thanks!');
    expect(find.byKey(const Key('nearbyReplyingTo')), findsNothing);
  });

  testWidgets('hearts at once; delete mine; report theirs', (tester) async {
    final service = _FakeNearby()
      ..posts = [_post(1), _post(2, name: 'Mine', mine: true)];
    await _open(tester, service);
    await tester.tap(find.byKey(const Key('nearbyLike-1')));
    await tester.pumpAndSettle();
    expect(service.calls.last, 'like 1 - true');
    expect(
        find.descendant(
            of: find.byKey(const Key('nearbyLike-1')),
            matching: find.byIcon(Icons.favorite_rounded)),
        findsOneWidget);

    // theirs: report (it leaves my feed)
    await tester.tap(find.descendant(
        of: find.byKey(const Key('nearbyPost-1')),
        matching: find.byIcon(Icons.more_horiz)));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing);
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nearbyReport-spam')));
    await tester.pumpAndSettle();
    expect(service.calls.last, 'report 1 - spam');
    expect(find.byKey(const Key('nearbyPost-1')), findsNothing);

    // mine: delete
    await tester.tap(find.descendant(
        of: find.byKey(const Key('nearbyPost-2')),
        matching: find.byIcon(Icons.more_horiz)));
    await tester.pumpAndSettle();
    expect(find.text('Report'), findsNothing);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nearbyConfirmDelete')));
    await tester.pumpAndSettle();
    expect(service.calls.last, 'delete 2 -');
    expect(find.byKey(const Key('nearbyPost-2')), findsNothing);
  });
}
