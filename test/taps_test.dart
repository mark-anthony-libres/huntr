import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huntr/models/models.dart';
import 'package:huntr/screens/chat_screen.dart';
import 'package:huntr/screens/profile_screen.dart';
import 'package:huntr/screens/taps_screen.dart';
import 'package:huntr/services/huntr_backend.dart';
import 'package:huntr/services/messaging_service.dart';
import 'package:huntr/services/tap_service.dart';
import 'package:huntr/state/app_state.dart';
import 'package:huntr/state/messaging_state.dart';
import 'package:huntr/state/tap_state.dart';
import 'package:huntr/theme.dart';

Profile _person(int id, {String name = 'Sam'}) => Profile.nearby({
      'id': id,
      'display_name': name,
      'age': 30,
      'presence': 'online',
    });

ReceivedTap _tap(int id, {bool read = false, String name = 'Alex'}) =>
    ReceivedTap(
      id: id,
      sender: _person(100 + id, name: name),
      answers: const [],
      isRead: read,
      receivedAt: DateTime.now().subtract(const Duration(minutes: 5)),
    );

/// The backend's taps, as seen by me.
class _FakeTaps extends TapService {
  List<ReceivedTap> inbox = [];
  Object? sendError;
  final List<String> calls = [];

  @override
  Future<List<ReceivedTap>> fetchInbox(String token) async {
    calls.add('inbox');
    return inbox;
  }

  @override
  Future<void> send(String token, int recipientId) async {
    if (sendError != null) throw sendError!;
    calls.add('send $recipientId');
  }

  @override
  Future<void> markRead(String token, int tapId) async =>
      calls.add('read $tapId');

  @override
  Future<TapResponse> respond(String token, int tapId,
      {required String body, required String clientId}) async {
    calls.add('respond $tapId $body');
    inbox = [...inbox.where((t) => t.id != tapId)];
    return TapResponse(
        conversationId: 5,
        message: ChatMessage(
            id: 2,
            conversationId: 5,
            fromMe: true,
            body: body,
            sentAt: DateTime.now()));
  }
}

class _FakeMessaging extends MessagingService {
  _FakeMessaging([this.history = const []]);
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

Future<TapState> _open(WidgetTester tester, _FakeTaps service, Widget home,
    {List<Profile> nearby = const [],
    List<ChatMessage> history = const []}) async {
  final app = AppState()
    ..startSession('t')
    ..setNearby(nearby, nextOffset: null);
  // signed in, the home screen loads the inbox
  final taps = TapState(service: service, token: () => 't');
  await taps.refresh();
  final messaging = MessagingState(
      service: _FakeMessaging(history), token: () => 't', playSound: () {});
  await tester.pumpWidget(AppScope(
    state: app,
    child: MessagingScope(
      state: messaging,
      child: TapScope(
        state: taps,
        child:
            MaterialApp(theme: buildHuntrTheme(), home: Scaffold(body: home)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return taps;
}

void main() {
  group('Tap data from the backend', () {
    test('a tap card message, with or without answers', () {
      ChatMessage card(List<dynamic> tap) => ChatMessage.fromJson({
            'id': 1,
            'conversation_id': 2,
            'from_me': false,
            'body': '',
            'created_at': '2026-10-22T10:00:00Z',
            'type': 'tap',
            'tap': tap,
          });
      final now = card([]);
      expect(now.type, ChatMessageType.tap);
      expect(now.tapAnswers, isEmpty);
      expect(now.preview, '👋 They tapped you');
      // sent while Tap had questions
      final earlier = card([
        {'question': 'Q1', 'required': true, 'answer': 'A1'},
      ]);
      expect(earlier.tapAnswers.map((a) => (a.question, a.answer)),
          [('Q1', 'A1')]);
    });

    test('an inbox tap parses its sender', () {
      final tap = ReceivedTap.fromJson({
        'id': 3,
        'sender': {'id': 9, 'display_name': 'Alex', 'age': 28},
        'answers': [],
        'is_read': false,
        'created_at': '2026-10-22T10:00:00Z',
      });
      expect(tap.sender.backendId, 9);
      expect(tap.sender.name, 'Alex');
      expect(tap.isRead, isFalse);
      expect(tap.read().isRead, isTrue);
    });
  });

  group('Tapping someone from their profile', () {
    testWidgets('one tap sends it, nothing to fill in', (tester) async {
      final service = _FakeTaps();
      await _open(tester, service, const ProfileScreen(profileId: 'user-7'),
          nearby: [_person(7)]);
      await tester.tap(find.byKey(const Key('tapButton')));
      await tester.pumpAndSettle();
      expect(service.calls, contains('send 7'));
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Tap sent 👋 Sam will see it in their Taps.'),
          findsOneWidget);
    });

    testWidgets("the backend's refusal is shown", (tester) async {
      final service = _FakeTaps()
        ..sendError = const BackendException(
            'You already tapped them 👋 Give them a little time to answer.');
      await _open(tester, service, const ProfileScreen(profileId: 'user-7'),
          nearby: [_person(7)]);
      await tester.tap(find.byKey(const Key('tapButton')));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'You already tapped them 👋 Give them a little time to answer.'),
          findsOneWidget);
    });
  });

  group('My Taps inbox', () {
    testWidgets('empty: says so', (tester) async {
      await _open(tester, _FakeTaps(), const TapsScreen());
      expect(find.text('No taps yet'), findsOneWidget);
    });

    testWidgets(
        'unread taps are marked; opening one marks it read; responding '
        'opens the chat and the tap leaves the inbox', (tester) async {
      final service = _FakeTaps()
        ..inbox = [_tap(1), _tap(2, read: true, name: 'Jo')];
      final taps = await _open(tester, service, const TapsScreen());
      expect(taps.unreadCount, 1);
      expect(find.text('Alex tapped you 👋'), findsOneWidget);
      expect(find.text('Jo tapped you 👋'), findsOneWidget);
      expect(find.byKey(const Key('tapUnread-1')), findsOneWidget);
      expect(find.byKey(const Key('tapUnread-2')), findsNothing);

      await tester.tap(find.byKey(const Key('tap-1')));
      await tester.pumpAndSettle();
      expect(service.calls, contains('read 1'));
      expect(taps.unreadCount, 0);

      // nothing written: not sent
      await tester.tap(find.byKey(const Key('tapRespond')));
      await tester.pumpAndSettle();
      expect(find.text('Write something to send.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('tapReply')), 'Hey Alex!');
      await tester.tap(find.byKey(const Key('tapRespond')));
      await tester.pumpAndSettle();
      expect(service.calls, contains('respond 1 Hey Alex!'));
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(taps.taps!.map((t) => t.id), [2]);
    });

    testWidgets('a new tap event reloads the inbox', (tester) async {
      final service = _FakeTaps();
      final taps = await _open(tester, service, const TapsScreen());
      service.calls.clear();
      taps.handleEvent({'type': 'message.new'});
      expect(service.calls, isEmpty);
      service.inbox = [_tap(3)];
      taps.handleEvent({'type': 'tap.new', 'tap_id': 3});
      await tester.pumpAndSettle();
      expect(service.calls, ['inbox']);
      expect(taps.unreadCount, 1);
    });
  });

  testWidgets('a chat begins with the tap as a card', (tester) async {
    final card = ChatMessage(
      id: 1,
      conversationId: 5,
      fromMe: false,
      body: '',
      sentAt: DateTime(2026, 10, 22, 10),
      type: ChatMessageType.tap,
    );
    final reply = ChatMessage(
        id: 2,
        conversationId: 5,
        fromMe: true,
        body: 'Hey Alex!',
        sentAt: DateTime(2026, 10, 22, 10, 1));
    await _open(
        tester,
        _FakeTaps(),
        ChatScreen.conversation(
            conversationId: 5, other: _person(9, name: 'Alex')),
        history: [card, reply]);
    expect(find.byKey(const Key('tapCard')), findsOneWidget);
    expect(find.text('Alex tapped you 👋'), findsOneWidget);
    expect(find.text('Hey Alex!'), findsOneWidget);
  });
}
