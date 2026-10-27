import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huntr/models/stickers.dart';
import 'package:huntr/services/messaging_service.dart';
import 'package:huntr/state/app_state.dart';
import 'package:huntr/state/messaging_state.dart';
import 'package:huntr/theme.dart';
import 'package:huntr/widgets/chat/gif_picker.dart';

// The chat's sticker picker: HUNTR's stickers in the server's groups, a
// one-per-person group's rule shown before sending, and prices in Beans
// (what I can't afford is greyed out and can't be picked).

const _compliments = HuntrStickerGroup(
  id: 1,
  name: 'Compliments',
  onePerGroupPerRecipient: true,
  stickers: [
    HuntrSticker(id: 11, name: 'Pogi', groupId: 1),
    HuntrSticker(id: 12, name: 'Cute', groupId: 1),
  ],
);
const _roasts = HuntrStickerGroup(
  id: 2,
  name: 'Roasts',
  stickers: [
    HuntrSticker(id: 21, name: 'Ulol', groupId: 2),
    HuntrSticker(id: 22, name: 'Eww', groupId: 2),
  ],
);

/// The server's picker: [pageSize] stickers a page (in order, with their
/// groups), found by name with a query.
class _Catalog extends MessagingService {
  _Catalog(this.groups, this.beans, {this.pageSize = 100});

  final List<HuntrStickerGroup> groups;
  int beans;
  final int pageSize;
  int loads = 0;
  final offsets = <int>[];

  @override
  Future<StickerCatalog> fetchStickers(String token,
      {int offset = 0, String query = ''}) async {
    loads++;
    offsets.add(offset);
    final all = [
      for (final g in groups)
        for (final s in g.stickers)
          if (s.name.toLowerCase().contains(query.toLowerCase())) (g, s),
    ];
    final page = all.skip(offset).take(pageSize).toList();
    return StickerCatalog(
      groups: [
        for (final g in groups)
          if (page.any((p) => p.$1.id == g.id))
            HuntrStickerGroup(
                id: g.id,
                name: g.name,
                description: g.description,
                onePerGroupPerRecipient: g.onePerGroupPerRecipient,
                stickers: [
                  for (final p in page)
                    if (p.$1.id == g.id) p.$2
                ]),
      ],
      beansBalance: beans,
      nextOffset: offset + pageSize < all.length ? offset + pageSize : null,
    );
  }
}

// Beans prices (the example: 500 Beans to spend)
const _priced = HuntrStickerGroup(id: 3, name: 'Priced', stickers: [
  HuntrSticker(id: 31, name: 'Pogi', groupId: 3, beansCost: 500),
  HuntrSticker(id: 32, name: 'Chudai', groupId: 3, beansCost: 1000),
  HuntrSticker(id: 33, name: 'Cheap', groupId: 3, beansCost: 300),
  HuntrSticker(id: 34, name: 'Pricey', groupId: 3, beansCost: 700),
  HuntrSticker(id: 35, name: 'Gift', groupId: 3),
]);

void main() {
  late ChatPick? picked;

  Future<_Catalog> open(WidgetTester tester,
      {List<HuntrStickerGroup> groups = const [_compliments, _roasts],
      Set<int> sent = const {},
      int beans = 5000,
      _Catalog? service}) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    service ??= _Catalog(groups, beans);
    picked = null;
    await tester.pumpWidget(AppScope(
      state: AppState()..startSession('t'),
      child: MessagingScope(
        state: MessagingState(
            service: service, token: () => 't', playSound: () {}),
        child: MaterialApp(
          theme: buildHuntrTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    picked = await showGifPicker(context, sentStickers: sent),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return service!;
  }

  Semantics tile(WidgetTester tester, int id) => tester.widget<Semantics>(find
      .ancestor(
          of: find.byKey(Key('huntrSticker-$id')),
          matching: find.byType(Semantics))
      .first);

  double top(WidgetTester tester, String key) =>
      tester.getTopLeft(find.byKey(Key(key))).dy;

  testWidgets('stickers show under their groups, in the server\'s order',
      (tester) async {
    final service = await open(tester);
    expect(service.loads, 1);
    expect(find.text('Compliments'), findsOneWidget);
    expect(find.text('Roasts'), findsOneWidget);
    // each group's stickers under its own header, groups in order
    expect(top(tester, 'stickerGroup-1'),
        lessThan(top(tester, 'huntrSticker-11')));
    expect(top(tester, 'huntrSticker-12'),
        lessThan(top(tester, 'stickerGroup-2')));
    expect(top(tester, 'stickerGroup-2'),
        lessThan(top(tester, 'huntrSticker-21')));
    // the one-per-person rule is shown on its group only
    expect(find.text('One per person'), findsOneWidget);

    // a sticker is sent by tapping it
    await tester.tap(find.byKey(const Key('huntrSticker-21')));
    await tester.pumpAndSettle();
    expect(picked, isA<PickedSticker>());
    expect((picked! as PickedSticker).sticker.id, 21);
  });

  testWidgets('a one-per-person group already used with them waits for an undo',
      (tester) async {
    await open(tester, sent: {11});
    expect(find.byKey(const Key('stickerGroupUsed-1')), findsOneWidget);
    expect(find.textContaining('You sent them “Pogi”'), findsOneWidget);

    // another of that group: explained, not sent
    await tester.tap(find.byKey(const Key('huntrSticker-12')));
    await tester.pump();
    expect(
        find.textContaining('one sticker from “Compliments”'), findsOneWidget);
    expect(picked, isNull);
    expect(
        find.byKey(const Key('huntrSticker-12')), findsOneWidget); // still open

    // another group is free
    await tester.tap(find.byKey(const Key('huntrSticker-22')));
    await tester.pumpAndSettle();
    expect((picked! as PickedSticker).sticker.id, 22);
  });

  testWidgets('a group without the rule only marks what was sent',
      (tester) async {
    await open(tester, sent: {21});
    expect(find.byKey(const Key('stickerGroupUsed-2')), findsNothing);
    await tester.tap(find.byKey(const Key('huntrSticker-22')));
    await tester.pumpAndSettle();
    expect((picked! as PickedSticker).sticker.id, 22);
  });

  testWidgets('search narrows the stickers and hides empty groups',
      (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('gifSearch')), 'eww');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('stickerGroup-1')), findsNothing);
    expect(find.byKey(const Key('huntrSticker-22')), findsOneWidget);
    expect(find.byKey(const Key('huntrSticker-21')), findsNothing);
  });

  testWidgets('no stickers yet', (tester) async {
    await open(tester, groups: const []);
    expect(find.text('No HUNTR stickers yet'), findsOneWidget);
  });

  testWidgets(
      'with 500 Beans: what costs more is greyed out and can\'t be picked',
      (tester) async {
    await open(tester, groups: const [_priced], beans: 500);
    expect(
        find.descendant(
            of: find.byKey(const Key('beansBalance')),
            matching: find.text('500')),
        findsOneWidget);
    // prices under each sticker
    expect(
        find.descendant(
            of: find.byKey(const Key('stickerPrice-32')),
            matching: find.text('1,000')),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('stickerPrice-35')),
            matching: find.text('Free')),
        findsOneWidget);
    // enabled: 500 (exactly enough), 300, free; disabled: 1,000 and 700
    for (final id in [31, 33, 35]) {
      expect(tile(tester, id).properties.enabled, isTrue,
          reason: 'sticker $id');
    }
    for (final id in [32, 34]) {
      expect(tile(tester, id).properties.enabled, isFalse,
          reason: 'sticker $id');
      expect(
          find.descendant(
              of: find.byKey(Key('huntrSticker-$id')),
              matching: find.byType(ColorFiltered)),
          findsOneWidget);
    }
    // a greyed one does nothing
    await tester.tap(find.byKey(const Key('huntrSticker-32')));
    await tester.pumpAndSettle();
    expect(picked, isNull);
    expect(find.byKey(const Key('huntrSticker-32')), findsOneWidget);
    // one I can afford is picked
    await tester.tap(find.byKey(const Key('huntrSticker-31')));
    await tester.pumpAndSettle();
    expect((picked! as PickedSticker).sticker.id, 31);
  });

  testWidgets('after a send the balance and what I can afford are fresh',
      (tester) async {
    final service = _Catalog(const [_priced], 1000);
    await open(tester, service: service);
    expect(tile(tester, 32).properties.enabled, isTrue);
    await tester.tap(find.byKey(const Key('huntrSticker-34'))); // 700
    await tester.pumpAndSettle();
    service.beans = 300; // what the server says now
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(service.loads, 2);
    expect(
        find.descendant(
            of: find.byKey(const Key('beansBalance')),
            matching: find.text('300')),
        findsOneWidget);
    expect(tile(tester, 32).properties.enabled, isFalse);
    expect(tile(tester, 34).properties.enabled, isFalse);
    expect(tile(tester, 33).properties.enabled, isTrue);
  });

  testWidgets('my Beans show beside the search on the HUNTR tab only',
      (tester) async {
    await open(tester, beans: 4200);
    expect(
        find.descendant(
            of: find.byKey(const Key('beansBalance')),
            matching: find.text('4,200')),
        findsOneWidget);
    await tester.tap(find.text('GIFs'));
    await tester.pump();
    expect(find.byKey(const Key('beansBalance')), findsNothing);
    await tester.tap(find.byKey(const Key('huntrStickersTab')));
    await tester.pump();
    expect(find.byKey(const Key('beansBalance')), findsOneWidget);
  });

  testWidgets('scrolling down loads the next page from its offset',
      (tester) async {
    final many = HuntrStickerGroup(id: 9, name: 'Many', stickers: [
      for (var i = 1; i <= 40; i++)
        HuntrSticker(id: 100 + i, name: 'S$i', groupId: 9),
    ]);
    final service = _Catalog([many], 5000, pageSize: 12);
    await open(tester, service: service);
    // the first page first (more only as it's needed)
    expect(service.offsets.first, 0);
    expect(service.offsets.length, lessThan(4));
    expect(find.textContaining('See all'), findsNothing);
    expect(find.byKey(const Key('huntrSticker-140'), skipOffstage: false),
        findsNothing);
    final list = find
        .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(
        find.byKey(const Key('huntrSticker-140')), 300,
        scrollable: list, maxScrolls: 200);
    expect(service.offsets, [0, 12, 24, 36]);
    // each page once, its stickers added to the group's
    expect(find.byKey(const Key('huntrSticker-140')), findsOneWidget);
  });

  testWidgets('a sticker already sent asks to undo it (Beans not given back)',
      (tester) async {
    await open(tester, sent: {11});
    await tester.tap(find.byKey(const Key('huntrSticker-11')));
    await tester.pumpAndSettle();
    expect(find.text('Undo “Pogi”?'), findsOneWidget);
    expect(find.byKey(const Key('undoBeansNote')), findsOneWidget);
    expect(find.textContaining("doesn't give back the Beans"), findsOneWidget);
    // changed my mind: still in the picker
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(picked, isNull);
    // undo it
    await tester.tap(find.byKey(const Key('huntrSticker-11')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('undoStickerConfirm')));
    await tester.pumpAndSettle();
    expect(picked, isA<UndoPickedSticker>());
    expect((picked! as UndoPickedSticker).sticker.id, 11);
  });
}
