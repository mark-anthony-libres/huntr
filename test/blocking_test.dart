import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:huntr/models/models.dart';
import 'package:huntr/screens/blocked_users_screen.dart';
import 'package:huntr/screens/chat_screen.dart';
import 'package:huntr/screens/profile_screen.dart';
import 'package:huntr/services/block_service.dart';
import 'package:huntr/services/huntr_backend.dart';
import 'package:huntr/services/messaging_service.dart';
import 'package:huntr/state/app_state.dart';
import 'package:huntr/state/block_state.dart';
import 'package:huntr/state/messaging_state.dart';
import 'package:huntr/theme.dart';
import 'package:huntr/widgets/avatar.dart';

Profile _person(int id, {String name = 'Sam', Map<String, dynamic>? blocked}) =>
    Profile.nearby({
      'id': id,
      'display_name': name,
      'age': 30,
      'presence': 'online',
      'bio': 'Coffee and long walks',
      if (blocked != null) 'blocked': blocked,
    });

/// The backend's blocks, as seen by me.
class _FakeBlocks extends BlockService {
  final Map<int, BlockStatus> statuses = {};
  final List<String> calls = [];
  List<BlockedPerson> list = [];
  Object? listError;

  @override
  Future<BlockStatus> status(String token, int userId) async =>
      statuses[userId] ?? BlockStatus.none;

  @override
  Future<void> block(String token, int userId) async {
    calls.add('block $userId');
    statuses[userId] = BlockStatus(
        blockedByMe: true,
        unblockAvailableAt: DateTime.now().add(const Duration(days: 30)));
  }

  @override
  Future<void> unblock(String token, int userId) async {
    calls.add('unblock $userId');
    statuses[userId] = BlockStatus.none;
    list = [
      for (final p in list)
        if (p.userId != userId) p
    ];
  }

  @override
  Future<List<BlockedPerson>> mine(String token) async {
    if (listError != null) throw listError!;
    return list;
  }
}

class _FakeMessaging extends MessagingService {
  _FakeMessaging(this.history);
  final List<ChatMessage> history;

  @override
  Future<ConversationPage> fetchConversations(String token,
          {String? before}) async =>
      ConversationPage(conversations: []);
  @override
  Future<MessagePage> fetchMessages(String token, int conversationId,
          {int? before, int? after}) async =>
      MessagePage(messages: after == null ? history : [], hasMore: false);
  @override
  Future<void> markRead(String token, int conversationId) async {}
  @override
  Future<void> typing(String token, int conversationId, bool active) async {}
}

ChatMessage _msg(int id, {bool mine = false}) => ChatMessage(
    id: id,
    conversationId: 1,
    fromMe: mine,
    body: 'message $id',
    sentAt: DateTime(2026, 10, 20, 12, id));

Future<(AppState, BlockState, MessagingState)> _open(
    WidgetTester tester, _FakeBlocks service, Widget home,
    {List<Profile> nearby = const [],
    List<ChatMessage> history = const []}) async {
  final app = AppState()
    ..startSession('t')
    ..setNearby(nearby, nextOffset: null);
  final blocks = BlockState(service: service, token: () => 't');
  final messaging = MessagingState(
      service: _FakeMessaging(history), token: () => 't', playSound: () {});
  await tester.pumpWidget(AppScope(
    state: app,
    child: MessagingScope(
      state: messaging,
      child: BlockScope(
        state: blocks,
        child: MaterialApp(theme: buildHuntrTheme(), home: home),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return (app, blocks, messaging);
}

void main() {
  group('Blocking someone', () {
    testWidgets('Cancel changes nothing; Block User blocks after confirming',
        (tester) async {
      final service = _FakeBlocks();
      final sam = _person(7);
      final (app, _, _) = await _open(
          tester, service, const ProfileScreen(profileId: 'user-7'),
          nearby: [sam]);
      expect(find.text('Coffee and long walks'), findsOneWidget);

      Future<void> openBlock() async {
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Block'));
        await tester.pumpAndSettle();
      }

      await openBlock();
      expect(find.text('Block this user?'), findsOneWidget);
      expect(
          find.textContaining('You will not be able to unblock this person '
              'for 30 days.'),
          findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.calls, isEmpty);
      expect(app.visibleProfiles.map((p) => p.id), ['user-7']);

      await openBlock();
      await tester.tap(find.byKey(const Key('confirmBlock')));
      await tester.pumpAndSettle();
      expect(service.calls, ['block 7']);
      // the profile closes; Explore's cached list no longer has them
      expect(find.byKey(const Key('blockedScreen')), findsOneWidget);
      expect(find.text('You blocked this person.'), findsOneWidget);
      expect(find.text('Coffee and long walks'), findsNothing);
      expect(app.visibleProfiles, isEmpty);
    });

    testWidgets(
        'blocked by them: a stale profile shows only "You are blocked by this person"',
        (tester) async {
      final service = _FakeBlocks()
        ..statuses[7] = const BlockStatus(blockedMe: true);
      await _open(tester, service, const ProfileScreen(profileId: 'user-7'),
          nearby: [_person(7)]);
      expect(find.byKey(const Key('blockedMessage')), findsOneWidget);
      expect(find.text('You are blocked by this person'), findsOneWidget);
      // nothing of theirs: no name, bio or actions
      expect(find.textContaining('Sam'), findsNothing);
      expect(find.text('Coffee and long walks'), findsNothing);
      expect(find.byTooltip('More'), findsNothing);
      expect(find.byKey(const Key('messageButton')), findsNothing);
    });

    testWidgets('a block made by them reaches me and hides them from Explore',
        (tester) async {
      final service = _FakeBlocks();
      final (app, blocks, messaging) =
          await _open(tester, service, const SizedBox(), nearby: [_person(7)]);
      messaging.onBlockChanged = (id) async {
        final s = await blocks.check(id);
        if (s != null && s.blocked) app.block('user-$id');
      };
      service.statuses[7] = const BlockStatus(blockedMe: true);
      messaging.handleEvent({'type': 'block.changed', 'user_id': 7});
      await tester.pumpAndSettle();
      expect(blocks.statusOf(7)?.blockedMe, isTrue);
      expect(app.visibleProfiles, isEmpty);
    });
  });

  group('A chat while blocked', () {
    testWidgets(
        'history stays; no message box, presence, reply or reactions; header shows the block',
        (tester) async {
      final service = _FakeBlocks()
        ..statuses[7] = const BlockStatus(blockedMe: true);
      await _open(
          tester,
          service,
          ChatScreen.conversation(
              conversationId: 1,
              other: _person(7, blocked: {'by_me': false, 'me': true})),
          history: [_msg(1), _msg(2, mine: true)]);
      expect(find.text('message 1'), findsOneWidget);
      expect(find.text('message 2'), findsOneWidget);
      expect(find.byKey(const Key('blockedComposer')), findsOneWidget);
      expect(find.text('You are blocked by this person'), findsOneWidget);
      expect(find.byKey(const Key('messageInput')), findsNothing);
      expect(find.byKey(const Key('attachButton')), findsNothing);
      expect(find.text('Online now'), findsNothing);
      expect(
          tester.widget<Avatar>(find.byType(Avatar).first).showOnline, isFalse);
      expect(find.byKey(const Key('replyButton-1')), findsNothing);
      expect(find.byKey(const Key('reactButton-1')), findsNothing);
      await tester.longPress(find.byKey(const Key('reactable-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reactionBar')), findsNothing);
      expect(find.byKey(const Key('chatMenu')), findsNothing);

      await tester.tap(find.byKey(const Key('chatHeader')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('blockedScreen')), findsOneWidget);
      expect(find.text('Coffee and long walks'), findsNothing);
    });

    testWidgets('blocking from the chat keeps the history, closes the chat',
        (tester) async {
      final service = _FakeBlocks();
      await _open(tester, service,
          ChatScreen.conversation(conversationId: 1, other: _person(7)),
          history: [_msg(1)]);
      expect(find.byKey(const Key('messageInput')), findsOneWidget);
      await tester.tap(find.byKey(const Key('chatMenu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmBlock')));
      await tester.pumpAndSettle();
      expect(service.calls, ['block 7']);
      expect(find.text('message 1'), findsOneWidget);
      expect(find.text('You blocked this person.'), findsOneWidget);
      expect(find.byKey(const Key('messageInput')), findsNothing);
    });
  });

  group('Blocked users', () {
    BlockedPerson person(int id, {required bool canUnblock}) => BlockedPerson(
        userId: id,
        name: 'Person $id',
        blockedAt: DateTime(2026, 10, 21),
        unblockAvailableAt: DateTime(2026, 11, 20),
        canUnblock: canUnblock);

    testWidgets('lists mine; Unblock only from the date; refreshes after',
        (tester) async {
      final service = _FakeBlocks()
        ..list = [person(7, canUnblock: false), person(8, canUnblock: true)];
      await _open(tester, service, const BlockedUsersScreen());
      expect(find.text('Person 7'), findsOneWidget);
      expect(find.text('Blocked 21 Oct 2026 · unblock from 20 Nov 2026'),
          findsOneWidget);
      expect(
          tester
              .widget<OutlinedButton>(find.byKey(const Key('unblock-7')))
              .onPressed,
          isNull);
      await tester.tap(find.byKey(const Key('unblock-8')));
      await tester.pumpAndSettle();
      expect(service.calls, ['unblock 8']);
      expect(find.text('Person 8'), findsNothing);
      expect(find.text('Person 7'), findsOneWidget);
    });

    testWidgets('empty, and a failure with retry', (tester) async {
      final service = _FakeBlocks()
        ..listError = const BackendException('Something went wrong.');
      await _open(tester, service, const BlockedUsersScreen());
      expect(find.text('Couldn’t load blocked users'), findsOneWidget);
      service.listError = null;
      await tester.tap(find.byKey(const Key('blockedRetry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('noBlockedUsers')), findsOneWidget);
    });
  });

  test('a 409 block answer is a BlockedException (not a lost session)',
      () async {
    Future<Object?> answer(String detail) async {
      try {
        await fetchMessage(
            backendUrl: 'http://huntr.test',
            token: 't',
            messageId: 1,
            client: MockClient((_) async =>
                http.Response(jsonEncode({'detail': detail}), 409)));
      } catch (e) {
        return e;
      }
      return null;
    }

    final them = await answer('You are blocked by this person');
    expect(them, isA<BlockedException>());
    expect((them as BlockedException).byMe, isFalse);
    expect(them.message, 'You are blocked by this person');
    final mine = await answer('You blocked this person.');
    expect((mine as BlockedException).byMe, isTrue);
    expect(await answer('Something else'), isNot(isA<BlockedException>()));
  });
}
