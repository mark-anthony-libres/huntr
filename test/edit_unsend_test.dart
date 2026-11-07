import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        {bool fromMe = false,
        String? body,
        ChatMessageType type = ChatMessageType.text,
        ReplyPreview? replyTo,
        Duration? editableFor = const Duration(minutes: 50)}) =>
    ChatMessage(
      id: id,
      conversationId: 1,
      fromMe: fromMe,
      body: body ?? 'message $id',
      sentAt: _t0.add(Duration(minutes: id)),
      type: type,
      replyTo: replyTo,
      // as the backend says: only my texts, until the edit window ends
      editableUntil:
          fromMe && type == ChatMessageType.text && editableFor != null
              ? DateTime.now().add(editableFor)
              : null,
    );

/// Conversation 1 with person 7; edits and unsends are kept like the
/// backend does (in place).
class _Fake extends MessagingService {
  _Fake(List<ChatMessage> history)
      : messages = {for (final m in history) m.id!: m};

  final Map<int, ChatMessage> messages;
  final List<String> calls = [];

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
  Future<ChatMessage> editMessage(
      String token, int messageId, String body) async {
    calls.add('edit $messageId $body');
    return edited(messageId, body);
  }

  @override
  Future<ChatMessage> unsendMessage(String token, int messageId) async {
    calls.add('unsend $messageId');
    return unsent(messageId);
  }

  ChatMessage edited(int id, String body) {
    final m = messages[id]!;
    return messages[id] = ChatMessage(
        id: id,
        conversationId: 1,
        fromMe: m.fromMe,
        body: body,
        sentAt: m.sentAt,
        replyTo: m.replyTo,
        editableUntil: m.editableUntil,
        edited: true);
  }

  ChatMessage unsent(int id) {
    final m = messages[id]!;
    return messages[id] = ChatMessage(
        id: id,
        conversationId: 1,
        fromMe: m.fromMe,
        body: '',
        sentAt: m.sentAt,
        type: m.type,
        unsent: true);
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

Future<void> _menu(WidgetTester tester, int id) async {
  await tester.longPress(find.byKey(Key('reactable-$id')));
  await tester.pumpAndSettle();
}

Finder _action(String name) => find.byKey(Key('messageAction-$name'));

void main() {
  group('Edit and unsend state', () {
    test('an edit changes the message in place; a reply quoting it follows',
        () async {
      final service = _Fake([
        _msg(1, fromMe: true, body: 'See you at 7'),
        _msg(2,
            replyTo: const ReplyPreview(
                id: 1,
                fromMe: true,
                type: ChatMessageType.text,
                body: 'See you at 7')),
      ]);
      final state = _state(service);
      await state.load(1);

      await state.editMessage(state.messagesOf(1).first, 'See you at 8');
      final [mine, reply] = state.messagesOf(1);
      expect((mine.id, mine.body, mine.edited), (1, 'See you at 8', true));
      expect(state.messagesOf(1), hasLength(2));
      expect(reply.replyTo!.body, 'See you at 8');
      // unchanged or empty text isn't sent
      await state.editMessage(mine, '  See you at 8 ');
      await state.editMessage(mine, '   ');
      expect(service.calls, ['edit 1 See you at 8']);
    });

    test('unsent: nothing of it is left, and it can’t be changed again',
        () async {
      final service = _Fake([
        _msg(1, fromMe: true, body: 'Something I regret'),
        _msg(2,
            replyTo: const ReplyPreview(
                id: 1,
                fromMe: true,
                type: ChatMessageType.text,
                body: 'Something I regret')),
      ]);
      final state = _state(service);
      await state.load(1);

      await state.unsendMessage(state.messagesOf(1).first);
      final [mine, reply] = state.messagesOf(1);
      expect(mine.unsent, isTrue);
      expect(mine.preview, 'You unsent a message');
      expect(reply.replyTo!.unsent, isTrue);
      expect(reply.replyTo!.text, 'Message unsent');
      expect(
          mine.canEdit || mine.canUnsend || mine.copyableText != null, isFalse);
      await state.unsendMessage(mine);
      await state.editMessage(mine, 'again');
      expect(service.calls, ['unsend 1']);
    });

    test('Edit is gone once the edit window has passed; Unsend stays', () {
      final old =
          _msg(1, fromMe: true, editableFor: const Duration(minutes: -1));
      expect(old.canEdit, isFalse);
      expect(old.canUnsend, isTrue);
      expect(_msg(1, fromMe: true, editableFor: null).canEdit, isFalse);
    });

    test('only my own sent messages can be edited or unsent', () {
      expect(_msg(1).canEdit, isFalse);
      expect(_msg(1).canUnsend, isFalse);
      expect(_msg(1, fromMe: true).canEdit, isTrue);
      expect(
          _msg(1, fromMe: true, type: ChatMessageType.image).canEdit, isFalse);
      expect(
          _msg(1, fromMe: true, type: ChatMessageType.image).canUnsend, isTrue);
      expect(_msg(1, fromMe: true, type: ChatMessageType.albumTrade).canUnsend,
          isFalse);
    });
  });

  group('Edit and unsend UI', () {
    testWidgets('a message older than the edit window has no Edit',
        (tester) async {
      final service = _Fake([
        _msg(1, fromMe: true, editableFor: const Duration(minutes: -1)),
      ]);
      await _open(tester, _state(service));
      await _menu(tester, 1);
      expect(_action('copy'), findsOneWidget);
      expect(_action('edit'), findsNothing);
      expect(_action('unsend'), findsOneWidget);
    });

    testWidgets('my message: Copy, Edit and Unsend; an edit shows Edited',
        (tester) async {
      final service = _Fake([_msg(1, fromMe: true, body: 'See you at 7')]);
      await _open(tester, _state(service));
      expect(find.byKey(const Key('editedLabel')), findsNothing);

      await _menu(tester, 1);
      expect(find.byKey(const Key('reactionBar')), findsNothing);
      expect(_action('copy'), findsOneWidget);
      expect(_action('edit'), findsOneWidget);
      expect(_action('unsend'), findsOneWidget);

      await tester.tap(_action('edit'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('editMessageInput')), 'See you at 8');
      await tester.pump();
      await tester.tap(find.byKey(const Key('saveEdit')));
      await tester.pumpAndSettle();
      expect(service.calls, ['edit 1 See you at 8']);
      expect(find.text('See you at 8'), findsOneWidget);
      expect(find.text('See you at 7'), findsNothing);
      expect(find.byKey(const Key('editedLabel')), findsOneWidget);
    });

    testWidgets('unsending asks first; then only the placeholder is left',
        (tester) async {
      final service = _Fake([_msg(1, fromMe: true, body: 'Oops')]);
      await _open(tester, _state(service));

      await _menu(tester, 1);
      await tester.tap(_action('unsend'));
      await tester.pumpAndSettle();
      expect(find.text('Unsend this message?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.calls, isEmpty);
      expect(find.text('Oops'), findsOneWidget);

      await _menu(tester, 1);
      await tester.tap(_action('unsend'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmUnsend')));
      await tester.pumpAndSettle();
      expect(service.calls, ['unsend 1']);
      expect(find.text('Oops'), findsNothing);
      expect(find.text('You unsent a message'), findsOneWidget);

      // the placeholder has no menu
      await _menu(tester, 1);
      expect(find.byKey(const Key('messageActions')), findsNothing);
    });

    testWidgets('their message: reactions and Copy, never Edit or Unsend',
        (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      final service = _Fake([_msg(1, body: 'Hello there')]);
      await _open(tester, _state(service));

      await _menu(tester, 1);
      expect(find.byKey(const Key('reactionBar')), findsOneWidget);
      expect(_action('copy'), findsOneWidget);
      expect(_action('edit'), findsNothing);
      expect(_action('unsend'), findsNothing);
      await tester.tap(_action('copy'));
      await tester.pumpAndSettle();
      expect(copied, ['Hello there']);
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('the recipient sees an edit and an unsend live',
        (tester) async {
      final service = _Fake([
        _msg(1, body: 'First version'),
        _msg(2, body: 'Regretted'),
      ]);
      final state = _state(service);
      await _open(tester, state);

      service.edited(1, 'Second version');
      state.handleEvent(
          {'type': 'message.updated', 'conversation_id': 1, 'message_id': 1});
      service.unsent(2);
      state.handleEvent(
          {'type': 'message.updated', 'conversation_id': 1, 'message_id': 2});
      await tester.pumpAndSettle();

      expect(find.text('Second version'), findsOneWidget);
      expect(find.byKey(const Key('editedLabel')), findsOneWidget);
      expect(find.text('Regretted'), findsNothing);
      expect(find.text('Message unsent'), findsOneWidget);
    });
  });
}
