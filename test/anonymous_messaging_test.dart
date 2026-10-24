import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huntr/models/models.dart';
import 'package:huntr/screens/anonymous_profile_screen.dart';
import 'package:huntr/screens/chat_screen.dart';
import 'package:huntr/screens/chats_screen.dart';
import 'package:huntr/screens/profile_screen.dart';
import 'package:huntr/screens/unmatched_users_screen.dart';
import 'package:huntr/services/huntr_backend.dart';
import 'package:huntr/services/messaging_service.dart';
import 'package:huntr/state/app_state.dart';
import 'package:huntr/state/messaging_state.dart';
import 'package:huntr/theme.dart';

final _t0 = DateTime(2026, 10, 20, 12);

/// The backend's JSON for my anonymous conversations: id 5, where
/// "QuietWolf" writes to me (I don't know who), and id 6, where I write as
/// "CozyFox" to Sam (id 7).
Map<String, dynamic> _received(
        {Map<String, dynamic>? reveal, bool canSend = true}) =>
    {
      'id': 5,
      'other': {
        'id': null,
        'anonymous': true,
        'display_name': 'QuietWolf',
        'anonymous_avatar': 'wolf',
        'presence': 'online',
        'blocked': null,
      },
      'anonymous': {
        'i_am_anonymous': false,
        'name': 'QuietWolf',
        'avatar': 'wolf'
      },
      'reveal': reveal,
      'can_send': canSend,
      'last_message': {
        'id': 50,
        'conversation_id': 5,
        'sender_id': null,
        'from_me': false,
        'body': 'guess who',
        'client_id': null,
        'created_at': _t0.toUtc().toIso8601String(),
      },
      'unread_count': 1,
    };

Map<String, dynamic> _sent(
        {Map<String, dynamic>? reveal, bool canSend = true}) =>
    {
      'id': 6,
      'other': {
        'id': 7,
        'display_name': 'Sam',
        'age': 30,
        'presence': 'online'
      },
      'anonymous': {'i_am_anonymous': true, 'name': 'CozyFox', 'avatar': 'fox'},
      'reveal': reveal,
      'can_send': canSend,
      'last_message': {
        'id': 60,
        'conversation_id': 6,
        'sender_id': 99,
        'from_me': true,
        'body': 'hey you',
        'client_id': 'c1',
        'created_at': _t0.toUtc().toIso8601String(),
      },
      'unread_count': 0,
    };

const _pending = {'status': 'pending', 'expires_at': '2026-10-23T12:00:00Z'};

class _Fake extends MessagingService {
  List<Map<String, dynamic>> anonymous = [_received(), _sent()];
  final List<String> calls = [];
  Object? startError;
  AnonymousProfile profile = const AnonymousProfile(
      conversationId: 5,
      name: 'QuietWolf',
      avatar: 'wolf',
      online: true,
      distanceKm: 3,
      canRequestReveal: true);

  @override
  Future<ConversationPage> fetchConversations(String token,
          {String? before}) async =>
      ConversationPage(conversations: [
        ConversationSummary(
            id: 1,
            other: Profile.nearby(
                {'id': 8, 'display_name': 'Direct Dan', 'age': 25}),
            lastMessage: null,
            unreadCount: 0),
      ]);

  @override
  Future<ConversationPage> fetchAnonymousConversations(String token,
          {String? before}) async =>
      ConversationPage(conversations: [
        for (final c in anonymous) ConversationSummary.fromJson(c)
      ]);

  @override
  Future<MessageTarget> startConversation(String token, int userId) async {
    calls.add('start $userId');
    if (startError != null) throw startError!;
    return MessageTarget(
        conversationId: 6,
        anonymous:
            ConversationSummary.fromJson({..._sent(), 'last_message': null}));
  }

  // ---- unmatching ----

  List<UnmatchedPerson> unmatched = [
    UnmatchedPerson(userId: 9, name: 'Uma', unmatchedAt: _t0),
    UnmatchedPerson(
        name: 'QuietWolf',
        anonymousConversationId: 5,
        anonymousAvatar: 'wolf',
        unmatchedAt: _t0),
  ];

  @override
  Future<List<UnmatchedPerson>> fetchUnmatches(String token) async => unmatched;

  @override
  Future<void> unmatch(String token, int userId) async {
    calls.add('unmatch $userId');
  }

  @override
  Future<void> removeUnmatch(String token, int userId) async {
    calls.add('remove unmatch $userId');
    unmatched = [
      for (final u in unmatched)
        if (u.userId != userId) u
    ];
  }

  @override
  Future<Profile> fetchUnmatchedProfile(String token, int userId) async =>
      Profile.nearby(
          {'id': userId, 'display_name': 'Uma', 'age': 27, 'unmatched': true});

  @override
  Future<void> setAnonymousUnmatch(
      String token, int conversationId, bool unmatched) async {
    calls.add('anonymous unmatch $conversationId $unmatched');
    // gone from both lists
    if (unmatched) {
      anonymous = [
        for (final c in anonymous)
          if (c['id'] != conversationId) c
      ];
    }
  }

  /// Conversation 1's history (e.g. a reveal).
  List<ChatMessage> history = [];

  @override
  Future<MessagePage> fetchMessages(String token, int conversationId,
          {int? before, int? after}) async =>
      MessagePage(
          messages: conversationId == 1 && after == null ? history : const [],
          hasMore: false);

  @override
  Future<ChatMessage> send(String token,
      {required int recipientId,
      required String body,
      required String clientId,
      int? replyToId,
      String? gifId}) async {
    calls.add('direct $recipientId $body');
    throw StateError('an anonymous chat must not send directly');
  }

  @override
  Future<ChatMessage> sendAnonymous(String token,
      {required int conversationId,
      required String body,
      required String clientId,
      int? replyToId,
      String? gifId}) async {
    calls.add('anonymous $conversationId $body');
    return ChatMessage(
        id: 70,
        conversationId: conversationId,
        fromMe: true,
        body: body,
        sentAt: _t0,
        clientId: clientId);
  }

  @override
  Future<void> markRead(String token, int conversationId) async {}

  @override
  Future<void> typing(String token, int conversationId, bool active) async {}

  @override
  Future<AnonymousProfile> fetchAnonymousProfile(
      String token, int conversationId) async {
    calls.add('profile $conversationId');
    return profile;
  }

  @override
  Future<AnonymousProfile> requestReveal(
      String token, int conversationId) async {
    calls.add('reveal $conversationId');
    anonymous = [_received(reveal: _pending), _sent()];
    return profile = AnonymousProfile(
        conversationId: 5,
        name: 'QuietWolf',
        avatar: 'wolf',
        online: true,
        distanceKm: 3,
        reveal: RevealRequest.fromJson(_pending));
  }

  @override
  Future<RevealAnswer> answerReveal(
      String token, int conversationId, bool accept) async {
    calls.add('answer $conversationId $accept');
    anonymous = [
      _received(),
      _sent(reveal: {'status': 'declined'}, canSend: false)
    ];
    return RevealAnswer(accepted: accept);
  }

  @override
  Future<void> reportAnonymous(String token, int conversationId,
      {required String reason, String? details}) async {
    calls.add('report $conversationId $reason ${details?.trim()}');
  }

  @override
  Future<bool> setAnonymousMessaging(String token, bool enabled) async {
    calls.add('setting $enabled');
    return enabled;
  }
}

MessagingState _state(_Fake fake) =>
    MessagingState(service: fake, token: () => 'token', playSound: () {});

Future<void> _pump(WidgetTester tester, AppState app, MessagingState messaging,
    Widget home) async {
  tester.view.physicalSize = const Size(700, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppScope(
    state: app,
    child: MessagingScope(
      state: messaging,
      child: MaterialApp(theme: buildHuntrTheme(), home: home),
    ),
  ));
  await tester.pumpAndSettle();
}

AppState _app() => AppState()..startSession('token');

void main() {
  test('anonymous conversations are kept apart from direct ones', () async {
    final messaging = _state(_Fake());
    await messaging.refresh();
    await messaging.refreshAnonymous();
    expect(messaging.conversations!.map((c) => c.id), [1]);
    expect(messaging.anonymousConversations!.map((c) => c.id), [5, 6]);
    expect(messaging.anonymousUnread, 1);
    expect(messaging.unreadTotal, 1);
    // the sender of 5 has no id, only a name and an animal
    final hidden = messaging.summary(5)!.other;
    expect(hidden.backendId, isNull);
    expect(hidden.name, 'QuietWolf');
    expect(hidden.anonymousAvatar, 'wolf');
    // the same after a "restart" (loaded again)
    final again = _state(_Fake());
    await again.refresh();
    await again.refreshAnonymous();
    expect(again.summary(5)!.other.name, 'QuietWolf');
    expect(again.summary(5)!.other.anonymousAvatar, 'wolf');
  });

  test('sending in an anonymous chat goes by conversation, never directly',
      () async {
    final fake = _Fake();
    final messaging = _state(fake);
    await messaging.refresh();
    await messaging.refreshAnonymous();
    await messaging.load(5);
    await messaging.send(5, messaging.summary(5)!.other, 'who are you?');
    await messaging.load(6);
    await messaging.send(6, messaging.summary(6)!.other, 'just me');
    expect(fake.calls, ['anonymous 5 who are you?', 'anonymous 6 just me']);
    expect(
        messaging.anonymousConversations!.first.lastMessage!.body, 'just me');
    expect(messaging.conversations!.map((c) => c.id), [1]);
  });

  testWidgets('Direct and Anonymous tabs', (tester) async {
    final messaging = _state(_Fake());
    await messaging.refresh();
    await messaging.refreshAnonymous();
    await _pump(tester, _app(), messaging,
        Scaffold(body: ChatsScreen(onExplore: () {})));
    expect(find.text('Direct Dan, 25'), findsOneWidget);
    expect(find.text('QuietWolf'), findsNothing);
    await tester.tap(find.byKey(const Key('anonymousTab')));
    await tester.pumpAndSettle();
    expect(find.text('Direct Dan, 25'), findsNothing);
    expect(find.text('QuietWolf'), findsOneWidget);
    expect(find.byKey(const Key('anonymousAnimal-wolf')), findsOneWidget);
    expect(find.text('guess who'), findsOneWidget);
    expect(find.byKey(const Key('unread-5')), findsOneWidget);
    // where I'm anonymous: whom they see me as
    expect(find.text('Sam, 30'), findsOneWidget);
    expect(find.text('as CozyFox'), findsOneWidget);
  });

  testWidgets('empty Anonymous tab', (tester) async {
    final fake = _Fake()..anonymous = [];
    final messaging = _state(fake);
    await messaging.refresh();
    await messaging.refreshAnonymous();
    await _pump(tester, _app(), messaging,
        Scaffold(body: ChatsScreen(onExplore: () {})));
    await tester.tap(find.byKey(const Key('anonymousTab')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('noAnonymousChats')), findsOneWidget);
  });

  testWidgets('a received anonymous chat: text only, their anonymous profile',
      (tester) async {
    final fake = _Fake();
    final messaging = _state(fake);
    await messaging.refresh();
    await messaging.refreshAnonymous();
    final c = messaging.summary(5)!;
    await _pump(tester, _app(), messaging,
        ChatScreen.conversation(conversationId: 5, other: c.other));
    // no photos, videos, albums or locations
    expect(find.byKey(const Key('attachButton')), findsNothing);
    expect(find.byKey(const Key('messageInput')), findsOneWidget);
    expect(find.text('QuietWolf'), findsOneWidget);
    // their anonymous profile, never the real one
    await tester.tap(find.byKey(const Key('chatHeader')));
    await tester.pumpAndSettle();
    expect(find.byType(AnonymousProfileScreen), findsOneWidget);
    expect(find.byType(ProfileScreen), findsNothing);
    expect(find.byKey(const Key('anonymousName')), findsOneWidget);
    expect(find.byKey(const Key('anonymousAnimal-wolf')), findsOneWidget);
    expect(find.text('About 3 km away'), findsOneWidget);
    expect(find.text('Online now'), findsOneWidget);
    expect(fake.calls, ['profile 5']);

    // ask to see their profile
    await tester.tap(find.byKey(const Key('requestReveal')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmRequestReveal')));
    await tester.pumpAndSettle();
    expect(fake.calls.last, 'reveal 5');
    expect(find.byKey(const Key('revealRequested')), findsOneWidget);
    expect(find.byKey(const Key('revealStatus-pending')), findsOneWidget);
    expect(messaging.summary(5)!.reveal!.status, RevealStatus.pending);

    // report them
    await tester.tap(find.byKey(const Key('reportAnonymous')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('reportReason-harassment')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('reportDetails')), 'rude');
    await tester.tap(find.byKey(const Key('sendReport')));
    await tester.pumpAndSettle();
    expect(fake.calls.last, 'report 5 harassment rude');
    expect(find.byKey(const Key('reportSent')), findsOneWidget);
  });

  testWidgets('as the anonymous one: who they see, and answering a request',
      (tester) async {
    final fake = _Fake()
      ..anonymous = [_received(), _sent(reveal: _pending, canSend: false)];
    final messaging = _state(fake);
    await messaging.refresh();
    await messaging.refreshAnonymous();
    final c = messaging.summary(6)!;
    await _pump(tester, _app(), messaging,
        ChatScreen.conversation(conversationId: 6, other: c.other));
    expect(find.byKey(const Key('anonymousAsHeader')), findsOneWidget);
    // the one who wrote first: no Unmatch, no Block
    expect(find.byKey(const Key('unmatchButton')), findsNothing);
    expect(find.byKey(const Key('chatMenu')), findsNothing);
    expect(find.text('Block'), findsNothing);
    expect(find.text('You’re CozyFox to them'), findsOneWidget);
    // a pending request: no messages until I answer
    expect(find.byKey(const Key('revealBanner-pending')), findsOneWidget);
    expect(find.byKey(const Key('messageInput')), findsNothing);
    expect(find.byKey(const Key('anonymousClosedBar')), findsOneWidget);
    await tester.tap(find.byKey(const Key('declineReveal')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmRevealAnswer')));
    await tester.pumpAndSettle();
    expect(fake.calls.last, 'answer 6 false');
    expect(find.byKey(const Key('revealBanner-declined')), findsOneWidget);
    expect(find.byKey(const Key('messageInput')), findsNothing);
  });

  testWidgets('Message with no conversation yet starts an anonymous one',
      (tester) async {
    final fake = _Fake();
    final messaging = _state(fake);
    final sam = Profile.nearby(
        {'id': 7, 'display_name': 'Sam', 'age': 30, 'presence': 'online'});
    await _pump(tester, _app(), messaging, ProfileScreen.person(person: sam));
    // one button: Message (no separate anonymous one)
    expect(find.byKey(const Key('anonymousMessageButton')), findsNothing);
    await tester.tap(find.byKey(const Key('messageButton')));
    await tester.pumpAndSettle();
    expect(fake.calls, ['start 7']);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.byKey(const Key('anonymousIntro')), findsOneWidget);
    expect(find.byKey(const Key('anonymousIntroAvatar')), findsOneWidget);
    expect(find.byKey(const Key('attachButton')), findsNothing);
    await tester.enterText(find.byKey(const Key('messageInput')), 'hi Sam');
    await tester.pump();
    await tester.tap(find.byKey(const Key('sendButton')));
    await tester.pumpAndSettle();
    expect(fake.calls.last, 'anonymous 6 hi Sam');
  });

  testWidgets('Message while they wait for my answer opens that chat',
      (tester) async {
    final fake = _Fake()
      ..anonymous = [_received(), _sent(reveal: _pending, canSend: false)];
    final sam = Profile.nearby({'id': 7, 'display_name': 'Sam', 'age': 30});
    final messaging = _state(fake);
    await messaging.refresh();
    await messaging.refreshAnonymous();
    await _pump(tester, _app(), messaging, ProfileScreen.person(person: sam));
    await tester.tap(find.byKey(const Key('messageButton')));
    await tester.pumpAndSettle();
    // straight into the chat, to answer; no message box
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.byKey(const Key('revealBanner-pending')), findsOneWidget);
    expect(find.byKey(const Key('acceptReveal')), findsOneWidget);
    expect(find.byKey(const Key('messageInput')), findsNothing);
  });

  testWidgets('the backend refusing Message says why', (tester) async {
    final fake = _Fake()
      ..startError = const BackendException('You two aren’t matched anymore.');
    final sam = Profile.nearby({'id': 7, 'display_name': 'Sam', 'age': 30});
    await _pump(
        tester, _app(), _state(fake), ProfileScreen.person(person: sam));
    await tester.tap(find.byKey(const Key('messageButton')));
    await tester.pumpAndSettle();
    expect(find.text('You two aren’t matched anymore.'), findsOneWidget);
    expect(find.byType(ChatScreen), findsNothing);
  });

  for (final fromMe in [false, true]) {
    testWidgets(
        fromMe
            ? 'the reveal, for the one who showed it'
            : 'the reveal, for the one who asked', (tester) async {
      final fake = _Fake()
        ..history = [
          ChatMessage(
              id: 90,
              conversationId: 1,
              fromMe: fromMe,
              body: 'TurboPig',
              sentAt: _t0,
              type: ChatMessageType.reveal,
              revealedAvatar: 'pig'),
        ];
      final messaging = _state(fake);
      await messaging.refresh();
      await messaging.refreshAnonymous();
      await _pump(
          tester,
          _app(),
          messaging,
          ChatScreen.conversation(
              conversationId: 1, other: messaging.summary(1)!.other));
      expect(find.byKey(const Key('revealedCard')), findsOneWidget);
      // the animal they were shown as
      expect(find.byKey(const Key('anonymousAnimal-pig')), findsOneWidget);
      if (fromMe) {
        expect(find.text('Mask off! 🎉'), findsOneWidget);
        expect(find.textContaining('now knows'), findsOneWidget);
      } else {
        expect(find.text('Surprise! TurboPig revealed themselves 🎉'),
            findsOneWidget);
        expect(find.byKey(const Key('revealedViewProfile')), findsOneWidget);
      }
      expect(
          fake.history.single.preview,
          fromMe
              ? '🎉 You revealed yourself'
              : '🎉 TurboPig revealed themselves');
    });
  }

  testWidgets('Unmatched users: both kinds, opened and removed',
      (tester) async {
    final fake = _Fake();
    final messaging = _state(fake);
    await _pump(tester, _app(), messaging, const UnmatchedUsersScreen());
    expect(find.text('Uma'), findsOneWidget);
    expect(find.text('QuietWolf'), findsOneWidget);
    expect(find.byKey(const Key('anonymousAnimal-wolf')), findsOneWidget);
    // their profile: Remove from Unmatch List instead of Message
    await tester.tap(find.text('Uma'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.byKey(const Key('messageButton')), findsNothing);
    await tester.tap(find.byKey(const Key('removeUnmatchButton')));
    await tester.pumpAndSettle();
    expect(fake.calls, contains('remove unmatch 9'));
    // back on the list, refreshed
    expect(find.byType(ProfileScreen), findsNothing);
    expect(find.text('Uma'), findsNothing);
    // someone anonymous: their anonymous profile, never the real one
    fake.profile = const AnonymousProfile(
        conversationId: 5,
        name: 'QuietWolf',
        avatar: 'wolf',
        online: false,
        unmatched: true);
    await tester.tap(find.text('QuietWolf'));
    await tester.pumpAndSettle();
    expect(find.byType(AnonymousProfileScreen), findsOneWidget);
    expect(find.byKey(const Key('requestReveal')), findsNothing);
    await tester.tap(find.byKey(const Key('removeUnmatchButton')));
    await tester.pumpAndSettle();
    expect(fake.calls, contains('anonymous unmatch 5 false'));
  });

  testWidgets('no one unmatched', (tester) async {
    final fake = _Fake()..unmatched = [];
    await _pump(tester, _app(), _state(fake), const UnmatchedUsersScreen());
    expect(find.byKey(const Key('noUnmatchedUsers')), findsOneWidget);
  });

  testWidgets('unmatching in an anonymous chat closes and removes it',
      (tester) async {
    final fake = _Fake();
    final messaging = _state(fake);
    await messaging.refresh();
    await messaging.refreshAnonymous();
    final c = messaging.summary(5)!;
    await _pump(tester, _app(), messaging,
        Scaffold(body: Builder(builder: (context) {
      return TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  ChatScreen.conversation(conversationId: 5, other: c.other))),
          child: const Text('open'));
    })));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // in the header's ⋯ menu
    await tester.tap(find.byKey(const Key('anonymousChatMenu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('requestRevealButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('unmatchButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmUnmatch')));
    await tester.pumpAndSettle();
    expect(fake.calls, contains('anonymous unmatch 5 true'));
    expect(find.byType(ChatScreen), findsNothing);
    expect(messaging.summary(5), isNull);
    expect(messaging.isGone(5), isTrue);
  });

  testWidgets('their reveal request arrives as an unread message',
      (tester) async {
    final fake = _Fake();
    final messaging = _state(fake);
    await messaging.refresh();
    await messaging.refreshAnonymous();
    expect(messaging.anonymousUnread, 1); // conversation 5's "guess who"
    final asked = {
      'id': 61,
      'conversation_id': 6,
      'sender_id': 7,
      'from_me': false,
      'type': 'reveal_request',
      'body': '',
      'client_id': null,
      'created_at': _t0.toUtc().toIso8601String(),
    };
    fake.history = [ChatMessage.fromJson(asked)];
    messaging.handleEvent({
      'type': 'message.new',
      'conversation_id': 6,
      'anonymous': true,
      'message': asked,
      'sender': {'id': 7, 'display_name': 'Sam'},
    });
    // one more unread (the Chats badge), and the list says what it is
    expect(messaging.anonymousUnread, 2);
    expect(messaging.unreadTotal, 2);
    expect(
        messaging.summary(6)!.lastMessage!.preview, '👀 Curious who you are');
  });

  for (final fromMe in [false, true]) {
    testWidgets('the request card, ${fromMe ? 'mine' : 'theirs'}',
        (tester) async {
      final fake = _Fake()
        ..history = [
          ChatMessage(
              id: 91,
              conversationId: 1,
              fromMe: fromMe,
              body: '',
              sentAt: _t0,
              type: ChatMessageType.revealRequest),
        ];
      final messaging = _state(fake);
      await messaging.refresh();
      await _pump(
          tester,
          _app(),
          messaging,
          ChatScreen.conversation(
              conversationId: 1, other: messaging.summary(1)!.other));
      expect(find.byKey(const Key('revealRequestCard')), findsOneWidget);
      expect(
          find.text(fromMe
              ? 'You asked to see who they are 👀'
              : 'They’re curious who you are 👀'),
          findsOneWidget);
    });
  }
}
