// A profile's stickers: "Testimonials" on someone else's, "What others say
// about you" on mine, right after Expectation, and usable on narrow screens.
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

Future<void> _open(WidgetTester tester, Profile person,
    {int? me, double width = 390}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = AppState()..startSession('t');
  app.myUserId = me;
  await tester.pumpWidget(AppScope(
    state: app,
    child: MaterialApp(
        theme: buildHuntrTheme(), home: ProfileScreen.person(person: person)),
  ));
  await tester.pumpAndSettle();
}

String _title(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('stickerShelfTitle'))).data!;

double _top(WidgetTester tester, Finder finder) =>
    tester.getTopLeft(finder).dy;

void main() {
  testWidgets("someone else's profile says Testimonials", (tester) async {
    await _open(tester, _person(7, stickers: _stickers), me: 99);
    expect(_title(tester), 'Testimonials');
  });

  testWidgets('my own profile says What others say about you',
      (tester) async {
    await _open(tester, _person(7, stickers: _stickers), me: 7);
    expect(_title(tester), 'What others say about you');
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
    expect(find.text('Testimonials'), findsNothing);
  });

  for (final width in [320.0, 390.0, 768.0, 1280.0]) {
    testWidgets('fits at $width wide, long names included', (tester) async {
      await _open(tester, _person(7, stickers: _stickers),
          me: 7, width: width);
      expect(tester.takeException(), isNull); // no overflow
      final title = tester.getRect(find.byKey(const Key('stickerShelfTitle')));
      final seeAll = tester.getRect(find.byKey(const Key('stickersSeeAll')));
      expect(title.overlaps(seeAll), isFalse);
      // compact cards of one size, never stretched
      final first = tester.getSize(find.byKey(const Key('stickerCount-1')));
      final long = tester.getSize(find.byKey(const Key('stickerCount-2')));
      expect(first, long);
      expect(first.width, inInclusiveRange(64, 92));
    });
  }
}
