import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huntr/models/models.dart';
import 'package:huntr/screens/chat_screen.dart';
import 'package:huntr/services/huntr_backend.dart';
import 'package:huntr/services/messaging_service.dart';
import 'package:huntr/state/app_state.dart';
import 'package:huntr/state/messaging_state.dart';
import 'package:huntr/theme.dart';

final _t0 = DateTime(2026, 10, 20, 12);

Profile _person(int id) => Profile.nearby(
    {'id': id, 'display_name': 'Sam', 'age': 30, 'presence': 'online'});

ChatMessage _msg(int id,
        {ChatMessageType type = ChatMessageType.text,
        bool fromMe = false,
        List<MessageReaction> reactions = const []}) =>
    ChatMessage(
      id: id,
      conversationId: 1,
      fromMe: fromMe,
      body: type == ChatMessageType.text ? 'message $id' : '',
      sentAt: _t0.add(Duration(minutes: id)),
      type: type,
      reactions: reactions,
      attachment: type == ChatMessageType.image
          ? const ChatAttachment(
              id: 20, isVideo: false, width: 600, height: 800, expired: false)
          : null,
      liveLocation: type == ChatMessageType.liveLocation
          ? const LiveLocationInfo(status: 'ended', requestedByMe: false)
          : null,
    );

/// Conversation 1 with person 7; reactions are kept like the backend does
/// (one each).
class _Fake extends MessagingService {
  _Fake(List<ChatMessage> history)
      : messages = {for (final m in history) m.id!: m};

  final Map<int, ChatMessage> messages;
  final List<String> calls = [];
  Object? reactError;

  @override
  Future<MessagePage> fetchMessages(String token, int conversationId,
          {int? before, int? after}) async =>
      MessagePage(
          messages: after == null ? messages.values.toList() : [],
          hasMore: false);

  @override
  Future<ChatMessage> fetchMessage(String token, int messageId) async =>
      messages[messageId]!;

  @override
  Future<void> markRead(String token, int conversationId) async {}

  @override
  Future<void> typing(String token, int conversationId, bool active) async {}

  @override
  Future<ChatMessage> react(String token, int messageId, String? emoji) async {
    calls.add('react $messageId $emoji');
    if (reactError != null) throw reactError!;
    return theyReact(messageId, emoji, mine: true);
  }

  /// Sets one person's reaction (me, or them).
  ChatMessage theyReact(int messageId, String? emoji, {bool mine = false}) {
    final m = messages[messageId]!;
    return messages[messageId] = m.copyWith(reactions: [
      for (final r in m.reactions)
        if (r.fromMe != mine) r,
      if (emoji != null) MessageReaction(emoji: emoji, fromMe: mine),
    ]);
  }
}

MessagingState _state(_Fake service) =>
    MessagingState(service: service, token: () => 'token', playSound: () {});

Future<void> _open(WidgetTester tester, MessagingState state) async {
  await tester.pumpWidget(AppScope(
    state: AppState()..startSession('token'),
    child: MessagingScope(
      state: state,
      child: MaterialApp(
          theme: buildHuntrTheme(),
          home: ChatScreen.conversation(conversationId: 1, other: _person(7))),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, int messageId, String emoji) async {
  await tester.longPress(find.byKey(Key('reactable-$messageId')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('reactionBar')), findsOneWidget);
  await tester.tap(find.byKey(Key('react-$emoji')));
  await tester.pumpAndSettle();
}

String _pillText(WidgetTester tester) => find
    .descendant(
        of: find.byKey(const Key('reactionPill')), matching: find.byType(Text))
    .evaluate()
    .map((e) => (e.widget as Text).data)
    .join(' ');

void main() {
  group('Reactions state', () {
    test('one each: reacting again replaces it, the same one removes it',
        () async {
      final service = _Fake([_msg(1)]);
      final state = _state(service);
      await state.load(1);

      await state.react(state.messagesOf(1).single, '❤️');
      expect(state.messagesOf(1).single.myReaction, '❤️');
      await state.react(state.messagesOf(1).single, '😆');
      expect(state.messagesOf(1).single.reactions.map((r) => r.emoji), ['😆']);
      await state.react(state.messagesOf(1).single, '😆');
      expect(state.messagesOf(1).single.reactions, isEmpty);
      expect(service.calls, ['react 1 ❤️', 'react 1 😆', 'react 1 null']);
    });

    test('shown at once, and put back when the backend says no', () async {
      final service = _Fake([_msg(1)])
        ..reactError = const BackendException('Message not found.');
      final state = _state(service);
      await state.load(1);

      final reacting = state.react(state.messagesOf(1).single, '👍');
      expect(state.messagesOf(1).single.myReaction, '👍');
      await expectLater(reacting, throwsA(isA<BackendException>()));
      expect(state.messagesOf(1).single.reactions, isEmpty);
    });

    test('albums and live connections take none', () async {
      final service = _Fake([_msg(1, type: ChatMessageType.liveLocation)]);
      final state = _state(service);
      await state.load(1);
      await state.react(state.messagesOf(1).single, '❤️');
      expect(service.calls, isEmpty);
      expect(_msg(1, type: ChatMessageType.albumTrade).canReact, isFalse);
      expect(_msg(1, type: ChatMessageType.location).canReact, isFalse);
      expect(_msg(1, type: ChatMessageType.video).canReact, isTrue);
      // never my own messages
      expect(_msg(1, fromMe: true).canReact, isFalse);
      expect(
          _msg(1, type: ChatMessageType.image, fromMe: true).canReact, isFalse);
    });
  });

  group('Reactions UI', () {
    testWidgets('long-press a message, pick an emoji; again to remove it',
        (tester) async {
      final service = _Fake([_msg(1)]);
      await _open(tester, _state(service));
      expect(find.byKey(const Key('reactionPill')), findsNothing);

      await _pick(tester, 1, '❤️');
      expect(service.calls, ['react 1 ❤️']);
      expect(_pillText(tester), '❤️');

      await _pick(tester, 1, '❤️');
      expect(service.calls.last, 'react 1 null');
      expect(find.byKey(const Key('reactionPill')), findsNothing);
    });

    testWidgets('+ opens every emoji', (tester) async {
      final service = _Fake([_msg(1)]);
      await _open(tester, _state(service));
      await tester.longPress(find.byKey(const Key('reactable-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('moreReactions')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('emojiPicker')), findsOneWidget);
      await tester.tap(find.byKey(const Key('pick-😂')));
      await tester.pumpAndSettle();
      expect(service.calls, ['react 1 😂']);
      expect(_pillText(tester), '😂');
    });

    testWidgets('photos take reactions; live connection cards do not',
        (tester) async {
      final service = _Fake([
        _msg(1, type: ChatMessageType.liveLocation),
        _msg(2, type: ChatMessageType.image),
      ]);
      await _open(tester, _state(service));
      // the live card can be replied to, but takes no reactions
      expect(find.byKey(const Key('reactButton-1')), findsNothing);
      await tester.longPress(find.byKey(const Key('reactable-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reactionBar')), findsNothing);
      await _pick(tester, 2, '😮');
      expect(service.calls, ['react 2 😮']);
      expect(_pillText(tester), '😮');
    });

    testWidgets('my own message: their reaction shows, but I can’t react to it',
        (tester) async {
      final service = _Fake([_msg(1, fromMe: true)]);
      final state = _state(service);
      await _open(tester, state);

      service.theyReact(1, '❤️');
      state.handleEvent(
          {'type': 'message.updated', 'conversation_id': 1, 'message_id': 1});
      await tester.pumpAndSettle();
      expect(_pillText(tester), '❤️');

      // no bar from a long-press or the pill, and no react button
      await tester.longPress(find.byKey(const Key('reactable-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reactionPill')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reactionBar')), findsNothing);
      expect(find.byKey(const Key('reactButton-1')), findsNothing);
      expect(service.calls, isEmpty);
    });
  });
}
