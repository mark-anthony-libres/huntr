import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huntr/models/models.dart';
import 'package:huntr/screens/chat_screen.dart';
import 'package:huntr/screens/chats_screen.dart';
import 'package:huntr/screens/profile_screen.dart';
import 'package:huntr/services/huntr_backend.dart';
import 'package:huntr/services/messaging_service.dart';
import 'package:huntr/state/app_state.dart';
import 'package:huntr/state/messaging_state.dart';
import 'package:huntr/theme.dart';

final _t0 = DateTime(2026, 10, 20, 12);

Profile _person(int id, {String name = 'Sam'}) => Profile.nearby({
      'id': id,
      'display_name': name,
      'age': 30,
      'presence': 'online',
    });

ChatMessage _msg(int id,
        {int conv = 1, bool fromMe = false, String? body, String? clientId}) =>
    ChatMessage(
      id: id,
      conversationId: conv,
      fromMe: fromMe,
      body: body ?? 'message $id',
      sentAt: _t0.add(Duration(minutes: id)),
      clientId: clientId,
    );

Map<String, dynamic> _event(int id, {int conv = 1, String body = 'hi'}) => {
      'type': 'message.new',
      'conversation_id': conv,
      'message': {
        'id': id,
        'conversation_id': conv,
        'sender_id': 7,
        'from_me': false,
        'body': body,
        'client_id': null,
        'created_at': _t0.add(Duration(minutes: id)).toUtc().toIso8601String(),
      },
      'sender': {'id': 7, 'display_name': 'Sam'},
    };

/// A backend in memory: one conversation (id 1) with person 7.
class _FakeMessaging extends MessagingService {
  _FakeMessaging({List<ChatMessage>? history, this.unread = 0})
      : history = history ?? [];

  final List<ChatMessage> history;
  int unread;
  final List<String> calls = [];
  final List<String> sentClientIds = [];
  final Map<String, ChatMessage> _byClientId = {};
  int _nextId = 1000;
  Object? sendError;
  Completer<void>? sendGate;
  Object? fetchError;

  @override
  Future<ConversationPage> fetchConversations(String token,
      {String? before}) async {
    calls.add('list');
    return ConversationPage(conversations: [
      ConversationSummary(
          id: 1,
          other: _person(7),
          lastMessage: history.isEmpty ? null : history.last,
          unreadCount: unread),
    ]);
  }

  @override
  Future<MessageTarget> startConversation(String token, int userId) async {
    calls.add('open $userId');
    return const MessageTarget(conversationId: 1);
  }

  @override
  Future<MessagePage> fetchMessages(String token, int conversationId,
      {int? before, int? after}) async {
    calls.add('messages before=$before after=$after');
    if (fetchError != null) throw fetchError!;
    const size = 3;
    if (after != null) {
      final newer = history.where((m) => m.id! > after).toList();
      return MessagePage(
          messages: newer.take(size).toList(), hasMore: newer.length > size);
    }
    final older =
        history.where((m) => before == null || m.id! < before).toList();
    final page =
        older.length > size ? older.sublist(older.length - size) : older;
    return MessagePage(messages: page, hasMore: older.length > size);
  }

  @override
  Future<ChatMessage> send(String token,
      {required int recipientId,
      required String body,
      required String clientId,
      int? replyToId,
      String? gifId}) async {
    sentClientIds.add(clientId);
    await sendGate?.future;
    if (sendError != null) throw sendError!;
    return store(clientId, body);
  }

  /// Saves a message of mine, once per client id (like the backend).
  ChatMessage store(String clientId, String body) {
    return _byClientId.putIfAbsent(clientId, () {
      final m = _msg(_nextId++, fromMe: true, body: body, clientId: clientId);
      history.add(m);
      return m;
    });
  }

  // typing is relayed live; nothing to fake
  @override
  Future<void> typing(String token, int conversationId, bool active) async {}

  @override
  Future<void> markRead(String token, int conversationId) async {
    calls.add('read $conversationId');
    unread = 0;
  }
}

class _Sound {
  int plays = 0;
  void play() => plays++;
}

MessagingState _state(_FakeMessaging service, _Sound sound) => MessagingState(
    service: service, token: () => 'token', playSound: sound.play);

Widget _app(AppState app, MessagingState messaging, Widget home) => AppScope(
      state: app,
      child: MessagingScope(
        state: messaging,
        child: MaterialApp(theme: buildHuntrTheme(), home: home),
      ),
    );

void main() {
  group('MessagingState', () {
    test('loads conversations with unread counts, and marks them read',
        () async {
      final service = _FakeMessaging(history: [_msg(1)], unread: 2);
      final state = _state(service, _Sound());
      await state.refresh();
      expect(state.conversations!.single.other.backendId, 7);
      expect(state.unreadTotal, 2);

      await state.markRead(1);
      expect(state.unreadTotal, 0);
      expect(service.calls, contains('read 1'));
    });

    test('loads the newest page, then older pages', () async {
      final service =
          _FakeMessaging(history: [for (var i = 1; i <= 7; i++) _msg(i)]);
      final state = _state(service, _Sound());
      await state.load(1);
      expect(state.messagesOf(1).map((m) => m.id), [5, 6, 7]);
      expect(state.hasOlder(1), isTrue);

      await state.loadOlder(1);
      await state.loadOlder(1);
      expect(state.messagesOf(1).map((m) => m.id), [1, 2, 3, 4, 5, 6, 7]);
      expect(state.hasOlder(1), isFalse);
      expect(service.calls, contains('messages before=5 after=null'));
    });

    test('a failed load can be retried', () async {
      final service = _FakeMessaging(history: [_msg(1)])
        ..fetchError = const BackendException('Server is down.');
      final state = _state(service, _Sound());
      await state.load(1);
      expect(state.isLoaded(1), isFalse);
      expect(state.loadErrorOf(1), 'Server is down.');

      service.fetchError = null;
      await state.load(1);
      expect(state.loadErrorOf(1), isNull);
      expect(state.messagesOf(1).map((m) => m.id), [1]);
    });

    test('shows my message at once, then the saved one', () async {
      final service = _FakeMessaging()..sendGate = Completer();
      final state = _state(service, _Sound());
      await state.load(1);
      final sending = state.send(1, _person(7), '  hello  ');
      expect(state.messagesOf(1).single.pending, isTrue);
      expect(state.messagesOf(1).single.body, 'hello');
      expect(state.conversations!.single.lastMessage!.body, 'hello');

      service.sendGate!.complete();
      await sending;
      final saved = state.messagesOf(1).single;
      expect(saved.pending, isFalse);
      expect(saved.id, 1000);
    });

    test('a failed send is retried with the same client id, stored once',
        () async {
      final service = _FakeMessaging()..sendError = Exception('offline');
      final state = _state(service, _Sound());
      await state.load(1);
      await state.send(1, _person(7), 'hello');
      final failed = state.messagesOf(1).single;
      expect(failed.failed, isTrue);

      service.sendError = null;
      await state.retry(1, _person(7), failed.clientId!);
      await state.retry(1, _person(7), failed.clientId!); // nothing to retry
      expect(service.sentClientIds, [failed.clientId, failed.clientId]);
      expect(state.messagesOf(1).single.failed, isFalse);
      expect(state.messagesOf(1).single.id, 1000);
      expect(service.history, hasLength(1));
    });

    test('a sync bringing in my message before the reply shows it once',
        () async {
      final service = _FakeMessaging()..sendGate = Completer();
      final state = _state(service, _Sound());
      await state.load(1);
      state.setViewing(1);
      final sending = state.send(1, _person(7), 'hello');
      // the server stores it, a sync fetches it, then the reply arrives
      await Future<void>.delayed(Duration.zero);
      final saved =
          service.store(state.messagesOf(1).single.clientId!, 'hello');
      await state.load(1); // already loaded: catches up
      service.sendGate!.complete();
      await sending;
      expect(state.messagesOf(1).map((m) => m.id), [saved.id]);
    });

    test('incoming messages: added once, unread, and one sound', () async {
      final service = _FakeMessaging(history: [_msg(1)]);
      final sound = _Sound();
      final state = _state(service, sound);
      await state.refresh();
      await state.load(1);

      state.handleEvent(_event(2, body: 'hey'));
      state.handleEvent(_event(2, body: 'hey')); // delivered twice
      expect(state.messagesOf(1).map((m) => m.id), [1, 2]);
      expect(state.unreadTotal, 1);
      expect(state.conversations!.single.lastMessage!.body, 'hey');
      expect(sound.plays, 1);
    });

    test('no sound or unread for the conversation on screen', () async {
      final service = _FakeMessaging();
      final sound = _Sound();
      final state = _state(service, sound);
      await state.refresh();
      await state.load(1);
      state.setViewing(1);

      state.handleEvent(_event(5));
      await Future<void>.delayed(Duration.zero);
      expect(sound.plays, 0);
      expect(state.unreadTotal, 0);
      expect(service.calls, contains('read 1'));

      // in the background it counts and sounds again
      state.setForeground(false);
      state.handleEvent(_event(6));
      expect(sound.plays, 1);
      expect(state.unreadTotal, 1);
    });

    test('no sound for history, syncs or my own messages', () async {
      final service = _FakeMessaging(history: [_msg(1), _msg(2)], unread: 2);
      final sound = _Sound();
      final state = _state(service, sound);
      await state.refresh();
      await state.load(1);
      await state.send(1, _person(7), 'mine');
      service.history.add(_msg(1001)); // their reply, fetched by the sync
      state.setViewing(1);
      await state.sync();
      expect(state.messagesOf(1).map((m) => m.id), [1, 2, 1000, 1001]);
      expect(sound.plays, 0);
    });

    test('sync (reconnect / foreground) catches up only newer messages',
        () async {
      final service =
          _FakeMessaging(history: [for (var i = 1; i <= 3; i++) _msg(i)]);
      final state = _state(service, _Sound());
      await state.load(1);
      state.setViewing(1);
      service.history.addAll([for (var i = 4; i <= 8; i++) _msg(i)]);
      service.unread = 5;
      service.calls.clear();

      await state.sync();
      expect(service.calls.first, 'list');
      expect(service.calls, contains('messages before=null after=3'));
      expect(service.calls, contains('messages before=null after=6'));
      expect(state.messagesOf(1).map((m) => m.id), [1, 2, 3, 4, 5, 6, 7, 8]);
      expect(state.unreadTotal, 0); // read: it's on screen
    });

    test('an event for an unknown conversation refreshes the list', () async {
      final service = _FakeMessaging();
      final sound = _Sound();
      final state = _state(service, sound);
      state.handleEvent(_event(3, conv: 1));
      await Future<void>.delayed(Duration.zero);
      expect(service.calls, contains('list'));
      expect(sound.plays, 1);
    });

    test('a read event marks my messages read, up to that id', () async {
      final service = _FakeMessaging(history: [
        _msg(1, fromMe: true),
        _msg(2, fromMe: true),
        _msg(3, fromMe: true),
      ]);
      final sound = _Sound();
      final state = _state(service, sound);
      await state.refresh();
      await state.load(1);

      state.handleEvent(
          {'type': 'message.read', 'conversation_id': 1, 'read_up_to': 2});
      expect(state.messagesOf(1).map((m) => m.read), [true, true, false]);
      expect(state.conversations!.single.lastMessage!.read, isFalse);

      state.handleEvent(
          {'type': 'message.read', 'conversation_id': 1, 'read_up_to': 3});
      expect(state.messagesOf(1).map((m) => m.read), [true, true, true]);
      expect(state.conversations!.single.lastMessage!.read, isTrue);
      expect(sound.plays, 0);
    });

    test('a sync picks up reads missed while away', () async {
      final service = _FakeMessaging(history: [_msg(1, fromMe: true)]);
      final state = _state(service, _Sound());
      await state.load(1);
      state.setViewing(1);
      service.history[0] = service.history[0].copyWith(read: true);

      await state.sync();
      expect(state.messagesOf(1).single.read, isTrue);
    });

    test('ending the session forgets everything', () async {
      final state = _state(_FakeMessaging(history: [_msg(1)]), _Sound());
      await state.refresh();
      await state.load(1);
      state.clear();
      expect(state.conversations, isNull);
      expect(state.messagesOf(1), isEmpty);
    });
  });

  group('screens', () {
    testWidgets('the chat list shows previews and unread counts',
        (tester) async {
      final service =
          _FakeMessaging(history: [_msg(1, body: 'See you')], unread: 3);
      final messaging = _state(service, _Sound());
      await messaging.refresh();
      await tester.pumpWidget(_app(AppState()..startSession('token'), messaging,
          ChatsScreen(onExplore: () {})));
      await tester.pump();

      expect(find.text('See you'), findsOneWidget);
      expect(find.byKey(const Key('unread-1')), findsOneWidget);
      expect(find.text('Unread (3)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('conversation-1')));
      await tester.pumpAndSettle();
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.byKey(const Key('unread-1')), findsNothing);
    });

    testWidgets('the chat list shows typing… while they type', (tester) async {
      final service = _FakeMessaging(history: [_msg(1, body: 'See you')]);
      final messaging = _state(service, _Sound());
      await messaging.refresh();
      await tester.pumpWidget(_app(AppState()..startSession('token'), messaging,
          ChatsScreen(onExplore: () {})));
      await tester.pump();
      expect(find.text('See you'), findsOneWidget);

      messaging.handleEvent(
          {'type': 'typing', 'conversation_id': 1, 'active': true});
      await tester.pump();
      expect(find.byKey(const Key('typingRow-1')), findsOneWidget);
      expect(find.text('typing…'), findsOneWidget);
      expect(find.text('See you'), findsNothing);

      // they stopped (or it timed out): the preview is back
      messaging.handleEvent(
          {'type': 'typing', 'conversation_id': 1, 'active': false});
      await tester.pump();
      expect(find.byKey(const Key('typingRow-1')), findsNothing);
      expect(find.text('See you'), findsOneWidget);

      messaging.handleEvent(
          {'type': 'typing', 'conversation_id': 1, 'active': true});
      await tester.pump(const Duration(seconds: 7));
      expect(find.text('See you'), findsOneWidget);
    });

    testWidgets('a conversation sends, and a failed message retries on tap',
        (tester) async {
      final service = _FakeMessaging(history: [_msg(1, body: 'Hi there')])
        ..sendError = Exception('offline');
      final messaging = _state(service, _Sound());
      await tester.pumpWidget(_app(AppState()..startSession('token'), messaging,
          ChatScreen.conversation(conversationId: 1, other: _person(7))));
      await tester.pumpAndSettle();
      expect(find.text('Hi there'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Coffee?');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
      expect(find.text('Coffee?'), findsOneWidget);
      expect(find.text('Not sent · Tap to retry'), findsOneWidget);

      service.sendError = null;
      await tester.tap(find.text('Coffee?'));
      await tester.pumpAndSettle();
      expect(find.text('Not sent · Tap to retry'), findsNothing);
      expect(find.text('Sent'), findsOneWidget);
      expect(service.history.map((m) => m.body), ['Hi there', 'Coffee?']);
    });

    testWidgets('my newest message shows Read once they read it',
        (tester) async {
      final service =
          _FakeMessaging(history: [_msg(1, fromMe: true, body: 'Hello')]);
      final messaging = _state(service, _Sound());
      await tester.pumpWidget(_app(AppState()..startSession('token'), messaging,
          ChatScreen.conversation(conversationId: 1, other: _person(7))));
      await tester.pumpAndSettle();
      expect(find.text('Sent'), findsOneWidget);

      messaging.handleEvent(
          {'type': 'message.read', 'conversation_id': 1, 'read_up_to': 1});
      await tester.pump();
      expect(find.text('Read'), findsOneWidget);
      expect(find.text('Sent'), findsNothing);
    });

    testWidgets("a real person's profile opens my conversation with them",
        (tester) async {
      final service = _FakeMessaging(history: [_msg(1, body: 'Earlier')]);
      final messaging = _state(service, _Sound());
      final app = AppState()
        ..startSession('token')
        ..setNearby([_person(7)], nextOffset: null);
      await tester.pumpWidget(
          _app(app, messaging, const ProfileScreen(profileId: 'user-7')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('messageButton')));
      await tester.pumpAndSettle();
      expect(service.calls, contains('open 7'));
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('Earlier'), findsOneWidget);
    });
  });
}
