// A profile's stickers: "What people say" on everyone's, mine included, right after Expectation, and usable on narrow screens.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huntr/models/models.dart';
import 'package:huntr/screens/profile_screen.dart';
import 'package:huntr/state/app_state.dart';
import 'package:huntr/theme.dart';

Profile _person(int id, {List<Map<String, Object?>>? stickers}) =>
    Profile.nearby({
      'id': id,
      'display_name': 'Sam',
      'age': 30,
      'bio': 'Hello there',
      'looking_for': ['chat', 'dates'],
      if (stickers != null) 'stickers': stickers,
    });

const _stickers = [
  {'id': 1, 'name': 'Pogi', 'count': 3},
  {
    'id': 2,
    'name': 'An exceptionally long sticker name that keeps going',
    'count': 1
  },
  {'id': 3, 'name': 'Big', 'count': 1},
  {'id': 4, 'name': 'Eww', 'count': 1},
  {'id': 5, 'name': 'Ulol', 'count': 1},
  {'id': 6, 'name': 'Small', 'count': 1},
];

/// The profile, with animations off unless [animate] (the carousel would
/// glide forever and never settle).
Future<void> _open(WidgetTester tester, Profile person,
    {int? me, double width = 390, bool animate = false}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = AppState()..startSession('t');
  app.myUserId = me;
  await tester.pumpWidget(AppScope(
    state: app,
    child: MaterialApp(
        theme: buildHuntrTheme(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: !animate),
            child: child!),
        home: ProfileScreen.person(person: person)),
  ));
  if (animate) {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  } else {
    await tester.pumpAndSettle();
  }
}

String _title(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('stickerShelfTitle'))).data!;

double _top(WidgetTester tester, Finder finder) => tester.getTopLeft(finder).dy;

void main() {
  testWidgets("someone else's profile says What people say", (tester) async {
    await _open(tester, _person(7, stickers: _stickers), me: 99);
    expect(_title(tester), 'What people say');
  });

  testWidgets('my own profile says What people say too', (tester) async {
    await _open(tester, _person(7, stickers: _stickers), me: 7);
    expect(_title(tester), 'What people say');
  });

  testWidgets('it comes right after Expectation', (tester) async {
    await _open(tester, _person(7, stickers: _stickers), me: 99);
    final expectation = _top(tester, find.text('EXPECTATION'));
    final shelf = _top(tester, find.byKey(const Key('stickerShelf')));
    expect(shelf, greaterThan(expectation));
    // the sections before Expectation stay before it
    expect(_top(tester, find.text('ABOUT')), lessThan(expectation));
    expect(find.byKey(const Key('stickerShelf')), findsOneWidget);
  });

  testWidgets('no stickers: no section', (tester) async {
    await _open(tester, _person(7, stickers: const []), me: 99);
    expect(find.byKey(const Key('stickerShelf')), findsNothing);
    expect(find.text('What people say'), findsNothing);
  });

  for (final width in [320.0, 390.0, 768.0, 1280.0]) {
    testWidgets('fits at $width wide, long names included', (tester) async {
      await _open(tester, _person(7, stickers: _stickers), me: 7, width: width);
      expect(tester.takeException(), isNull); // no overflow
      final title = tester.getRect(find.byKey(const Key('stickerShelfTitle')));
      final seeAll = tester.getRect(find.byKey(const Key('stickersSeeAll')));
      expect(title.overlaps(seeAll), isFalse);
      // cards of one size, never stretched; long names shown in full
      final first = tester.getSize(find.byKey(const Key('stickerCount-1')));
      final long = tester.getSize(find.byKey(const Key('stickerCount-2')));
      expect(first, long);
      expect(first.width, inInclusiveRange(84, 112));
      final name = tester.widget<Text>(find.byKey(const Key('stickerName-2')));
      expect(name.maxLines, isNull);
      expect(name.overflow, isNot(TextOverflow.ellipsis));
    });
  }

  testWidgets('the carousel glides without stopping, and loops',
      (tester) async {
    await _open(tester, _person(7, stickers: _stickers),
        me: 99, width: 360, animate: true);
    final scroll = tester
        .widget<SingleChildScrollView>(find.byKey(const Key('stickerCarousel')))
        .controller!;
    // it moves a little every frame, never pausing
    var before = scroll.offset;
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      expect(scroll.offset, greaterThan(before));
      before = scroll.offset;
    }
    // the row repeats, so after a whole pass it's back near the start
    expect(find.byKey(const Key('stickerCount-repeat-1')), findsOneWidget);
    var wrapped = false;
    for (var i = 0; i < 400 && !wrapped; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      wrapped = scroll.offset < before;
      before = scroll.offset;
    }
    expect(wrapped, isTrue);
    await tester.pumpWidget(const SizedBox()); // stops it
  });

  testWidgets('animations off: the carousel stays still', (tester) async {
    await _open(tester, _person(7, stickers: _stickers), me: 99, width: 360);
    final scroll = tester
        .widget<SingleChildScrollView>(find.byKey(const Key('stickerCarousel')))
        .controller!;
    await tester.pump(const Duration(seconds: 5));
    expect(scroll.offset, 0);
  });

  testWidgets('a few that fit: no carousel, no repeat', (tester) async {
    await _open(tester, _person(7, stickers: _stickers.take(1).toList()),
        me: 99, animate: true);
    expect(find.byKey(const Key('stickerCount-repeat-1')), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  for (final width in [280.0, 320.0, 390.0, 1280.0]) {
    testWidgets('Expectation: even columns at $width wide', (tester) async {
      final person = Profile.nearby({
        'id': 7,
        'display_name': 'Sam',
        'age': 30,
        'looking_for': [
          'chat',
          'friends',
          'dates',
          'networking',
          'relationship'
        ],
      });
      await _open(tester, person, me: 99, width: width);
      expect(tester.takeException(), isNull); // no overflow
      final pills = find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('lookingFor-'));
      expect(pills, findsNWidgets(5));
      final sizes = {
        for (final e in pills.evaluate())
          tester.getSize(find.byWidget(e.widget))
      };
      expect(sizes, hasLength(1)); // all one size
      final rows = {
        for (final e in pills.evaluate())
          tester.getTopLeft(find.byWidget(e.widget)).dy
      };
      if (width < 1000) expect(rows.length, 3); // two across a phone
    });
  }

  // out of order on purpose: the profile shows most sent first
  const unordered = [
    {'id': 1, 'name': 'One', 'count': 1},
    {'id': 2, 'name': 'Five', 'count': 5},
    {'id': 3, 'name': 'Two', 'count': 2},
    {'id': 4, 'name': 'Nine', 'count': 9},
    {'id': 5, 'name': 'Also one', 'count': 1},
  ];

  double left(WidgetTester tester, int id) =>
      tester.getTopLeft(find.byKey(Key('stickerCount-$id'))).dx;

  testWidgets('most sent first, ties as they came', (tester) async {
    await _open(tester, _person(7, stickers: unordered), me: 99, width: 1280);
    final order = [4, 2, 3, 1, 5].map((id) => left(tester, id)).toList();
    expect([...order]..sort(), order);
  });

  testWidgets('more than 3: the top 3 glow, gold to bronze', (tester) async {
    await _open(tester, _person(7, stickers: unordered), me: 99, width: 1280);
    for (final rank in [1, 2, 3]) {
      expect(find.byKey(Key('stickerRank-$rank')), findsWidgets);
    }
    // the badges sit on Nine, Five and Two
    for (final (rank, id) in [(1, 4), (2, 2), (3, 3)]) {
      final badge =
          tester.getCenter(find.byKey(Key('stickerRank-$rank')).first);
      final card = tester.getRect(find.byKey(Key('stickerCount-$id')));
      expect((badge.dx - card.left).abs(), lessThan(12));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('3 or fewer: none glow', (tester) async {
    await _open(tester, _person(7, stickers: unordered.take(3).toList()),
        me: 99, width: 1280);
    expect(find.byKey(const Key('stickerRank-1')), findsNothing);
  });

  testWidgets('the glow animates (and stops when the profile closes)',
      (tester) async {
    await _open(tester, _person(7, stickers: unordered),
        me: 99, width: 1280, animate: true);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
