import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huntr/models/stickers.dart';
import 'package:huntr/services/messaging_service.dart';
import 'package:huntr/state/app_state.dart';
import 'package:huntr/state/messaging_state.dart';
import 'package:huntr/theme.dart';
import 'package:huntr/widgets/chat/gif_picker.dart';

// The chat's sticker picker: HUNTR's stickers in the server's groups, and a
// one-per-person group's rule shown before sending.

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

class _Catalog extends MessagingService {
  _Catalog(this.groups);

  final List<HuntrStickerGroup> groups;
  int loads = 0;

  @override
  Future<List<HuntrStickerGroup>> fetchStickers(String token) async {
    loads++;
    return groups;
  }
}

void main() {
  late ChatPick? picked;

  Future<_Catalog> open(WidgetTester tester,
      {List<HuntrStickerGroup> groups = const [_compliments, _roasts],
      Set<int> sent = const {}}) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final service = _Catalog(groups);
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
    return service;
  }

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

    // the one already sent: as before
    await tester.tap(find.byKey(const Key('huntrSticker-11')));
    await tester.pump();
    expect(find.textContaining('You already sent “Pogi”'), findsOneWidget);

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
}
