import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huntr/flows/chat_attachments.dart';
import 'package:huntr/models/models.dart';
import 'package:huntr/screens/album_trade_screen.dart';
import 'package:huntr/screens/chat_media_viewer_screen.dart';
import 'package:huntr/screens/chat_screen.dart';
import 'package:huntr/screens/my_album_screen.dart';
import 'package:huntr/screens/traded_album_viewer_screen.dart';
import 'package:huntr/services/album_service.dart';
import 'package:huntr/services/huntr_backend.dart';
import 'package:huntr/services/messaging_service.dart';
import 'package:huntr/services/services_scope.dart';
import 'package:huntr/state/app_state.dart';
import 'package:huntr/state/messaging_state.dart';
import 'package:huntr/theme.dart';
import 'package:image_picker/image_picker.dart';

/// A real 4x4 WebP (a valid photo for previews).
final _webp = base64Decode(
    'UklGRjgAAABXRUJQVlA4ICwAAABwAQCdASoEAAQAAUAmJaACdAF1AAD+694v/SbP/6TZ//SbPkkZ2rY+uwAAAA==');

/// The start of an MP4 file (an `ftyp` box).
final _mp4 =
    Uint8List.fromList([0, 0, 0, 24, ...utf8.encode('ftypisom'), 0, 0, 2, 0]);

final _t0 = DateTime(2026, 10, 20, 12);

Profile _sam() => Profile.nearby(
    {'id': 7, 'display_name': 'Sam', 'age': 30, 'presence': 'online'});

ChatMessage _media(int id,
        {bool fromMe = false,
        bool video = false,
        DateTime? expiresAt,
        bool expired = false}) =>
    ChatMessage(
      id: id,
      conversationId: 1,
      fromMe: fromMe,
      body: '',
      sentAt: _t0,
      type: video ? ChatMessageType.video : ChatMessageType.image,
      attachment: ChatAttachment(
          id: id * 10,
          isVideo: video,
          width: 600,
          height: 800,
          durationMs: video ? 12000 : null,
          previewUrl: 'https://s3.test/p$id.webp',
          expiresAt: expiresAt,
          expired: expired),
    );

ChatMessage _trade(int id,
        {required bool fromMe,
        TradeStatus status = TradeStatus.pending,
        String? returned,
        DateTime? theirsExpiresAt,
        bool theirsExpired = false}) =>
    ChatMessage(
      id: id,
      conversationId: 1,
      fromMe: fromMe,
      body: '',
      sentAt: _t0,
      type: ChatMessageType.albumTrade,
      trade: AlbumTrade(
        id: id * 10,
        status: status,
        fromMe: fromMe,
        offeredAlbum: TradeAlbum(
            id: 50,
            name: 'Beach',
            photoCount: 3,
            videoCount: 1,
            previews: [
              for (var i = 0; i < 4; i++)
                TradePreview(url: 'https://s3.test/b$i.webp', isVideo: i == 3)
            ],
            // my access to the offered album, when it's theirs
            expiresAt: fromMe ? null : theirsExpiresAt,
            expired: !fromMe && theirsExpired),
        returnedAlbum: returned == null
            ? null
            : TradeAlbum(
                id: 60,
                name: returned,
                photoCount: 1,
                expiresAt: fromMe ? theirsExpiresAt : null,
                expired: fromMe && theirsExpired),
        canRespond: !fromMe && status == TradeStatus.pending,
        canCancel: status == TradeStatus.pending,
      ),
    );

/// The messaging backend in memory: conversation 1 with Sam (7).
class _FakeMessaging extends MessagingService {
  _FakeMessaging({List<ChatMessage>? history}) : history = history ?? [];

  final List<ChatMessage> history;
  final List<String> calls = [];
  final Map<int, ChatMessage> served = {};
  Object? sendError;
  Object? offerError;
  Object? openError;
  Completer<void>? sendGate;
  int _nextId = 500;

  @override
  Future<ConversationPage> fetchConversations(String token,
          {String? before}) async =>
      ConversationPage(conversations: [
        ConversationSummary(
            id: 1,
            other: _sam(),
            lastMessage: history.isEmpty ? null : history.last,
            unreadCount: 0)
      ]);

  @override
  Future<MessagePage> fetchMessages(String token, int conversationId,
          {int? before, int? after}) async =>
      MessagePage(
          messages: after == null
              ? history
              : history.where((m) => m.id! > after).toList(),
          hasMore: false);

  // typing is relayed live; nothing to fake
  @override
  Future<void> typing(String token, int conversationId, bool active) async {}

  @override
  Future<void> markRead(String token, int conversationId) async {}

  @override
  Future<ChatMessage> fetchMessage(String token, int messageId) async {
    calls.add('fetch $messageId');
    return served[messageId] ?? history.firstWhere((m) => m.id == messageId);
  }

  @override
  Future<ChatMessage> sendMedia(String token,
      {required int recipientId,
      required List<int> bytes,
      required String filename,
      required String clientId,
      int? replyToId,
      void Function(double sent)? onProgress}) async {
    calls.add('media $filename $clientId');
    onProgress?.call(0.5);
    await sendGate?.future;
    onProgress?.call(1);
    if (sendError != null) throw sendError!;
    final video = bytes.length > 4 && bytes[4] == 0x66;
    final m = _media(_nextId++, fromMe: true, video: video);
    final saved = ChatMessage(
        id: m.id,
        conversationId: 1,
        fromMe: true,
        body: '',
        sentAt: _t0,
        clientId: clientId,
        type: m.type,
        attachment: m.attachment);
    history.add(saved);
    return saved;
  }

  @override
  Future<MediaAccess> openMedia(String token, int attachmentId) async {
    calls.add('open $attachmentId');
    if (openError != null) throw openError!;
    return MediaAccess(
        url: 'https://api.test/media-views/content?token=v$attachmentId',
        isVideo: false,
        view: MediaView(
            token: 'v$attachmentId',
            heartbeat: const Duration(seconds: 20),
            countdownPaused: true));
  }

  @override
  Future<ChatMessage> offerAlbum(String token,
      {required int recipientId,
      required int albumId,
      required String clientId,
      int? replyToId}) async {
    calls.add('offer $albumId $clientId');
    if (offerError != null) throw offerError!;
    final m = _trade(_nextId++, fromMe: true);
    history.add(m);
    return m;
  }

  @override
  Future<ChatMessage> respondToTrade(
      String token, int tradeId, int albumId) async {
    calls.add('respond $tradeId $albumId');
    final i = history.indexWhere((m) => m.trade?.id == tradeId);
    final done = _trade(history[i].id!,
        fromMe: false, status: TradeStatus.completed, returned: 'Mine');
    history[i] = done;
    return done;
  }

  @override
  Future<TradedAlbumAccess> viewTradedAlbum(String token, int tradeId) async {
    calls.add('viewAlbum $tradeId');
    if (openError != null) throw openError!;
    return TradedAlbumAccess(
        name: 'Beach',
        items: const [
          StoredAlbumItem(
              id: 1,
              isVideo: false,
              url: 'https://s3.test/full1.webp',
              width: 4,
              height: 4),
          StoredAlbumItem(
              id: 2,
              isVideo: false,
              url: 'https://s3.test/full2.webp',
              width: 4,
              height: 4),
        ],
        view: MediaView(
            token: 'a$tradeId',
            heartbeat: const Duration(seconds: 20),
            countdownPaused: true));
  }

  @override
  Future<void> viewHeartbeat(String token, String viewToken) async =>
      calls.add('heartbeat $viewToken');

  @override
  Future<void> endView(String token, String viewToken) async =>
      calls.add('end $viewToken');

  @override
  Future<ChatMessage> cancelTrade(String token, int tradeId) async {
    calls.add('cancel $tradeId');
    final i = history.indexWhere((m) => m.trade?.id == tradeId);
    final m = history[i];
    final cancelled =
        _trade(m.id!, fromMe: m.fromMe, status: TradeStatus.cancelled);
    history[i] = cancelled;
    return cancelled;
  }
}

/// My albums on the backend, faked.
/// One photo, so an album can be traded (empty ones can't).
StoredAlbumItem _albumPhoto(int id) => StoredAlbumItem(
    id: id,
    isVideo: false,
    url: 'https://s3.test/a$id.webp',
    width: 4,
    height: 4);

class _FakeAlbums extends AlbumService {
  _FakeAlbums(List<String> names)
      : albums = [
          for (var i = 0; i < names.length; i++)
            StoredAlbum(
                id: 60 + i, name: names[i], items: [_albumPhoto(600 + i)])
        ];

  List<StoredAlbum> albums;
  int loads = 0;

  @override
  Future<AlbumList> fetchMine(String token) async {
    loads++;
    return AlbumList(
        albums: albums,
        maxAlbums: 3,
        maxItems: 6,
        maxPhotoBytes: 10 << 20,
        maxVideoBytes: 50 << 20,
        maxVideoSeconds: 60);
  }

  @override
  Future<StoredAlbum> create(String token, String name) async {
    // as if photos were added on the album screen before coming back
    final album = StoredAlbum(id: 90, name: name, items: [_albumPhoto(900)]);
    albums = [...albums, album];
    return album;
  }
}

class _FakePicker extends ChatMediaPicker {
  _FakePicker({this.camera = true});

  final bool camera;
  final List<XFile> next = [];
  int captures = 0;

  XFile _take() => next.removeAt(0);

  @override
  Future<XFile?> pickImage() async => _take();

  @override
  Future<XFile?> pickVideo() async => _take();

  @override
  Future<XFile?> pickMedia() async => _take();

  @override
  bool get hasCamera => camera;

  @override
  Future<XFile?> takePhoto() async {
    captures++;
    return _take();
  }

  @override
  Future<XFile?> recordVideo({Duration? maxDuration}) async {
    captures++;
    return _take();
  }
}

class _Sound {
  int plays = 0;
  void play() => plays++;
}

MessagingState _state(_FakeMessaging service, [_Sound? sound]) =>
    MessagingState(
        service: service,
        token: () => 'token',
        playSound: (sound ?? _Sound()).play);

Future<void> _openChat(WidgetTester tester, MessagingState messaging,
    {_FakeAlbums? albums}) async {
  tester.view.physicalSize = const Size(500, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await messaging.refresh();
  await tester.pumpWidget(AppScope(
    state: AppState(sampleAlbums: false)..startSession('token'),
    child: MessagingScope(
      state: messaging,
      child: ServicesScope(
        profiles: null,
        agreements: null,
        albums: albums,
        child: MaterialApp(
          theme: buildHuntrTheme(),
          home: ChatScreen.conversation(conversationId: 1, other: _sam()),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _attach(WidgetTester tester, String option) async {
  await tester.tap(find.byKey(const Key('attachButton')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('attach-$option')));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => ChatMediaPicker.instance = const ChatMediaPicker());

  group('MessagingState', () {
    test('a photo shows at once with its progress, then the saved one',
        () async {
      final service = _FakeMessaging()..sendGate = Completer();
      final state = _state(service);
      await state.load(1);
      final sending = state.sendMedia(1, _sam(),
          LocalUpload(bytes: _webp, filename: 'p.webp', isVideo: false));
      await Future<void>.delayed(Duration.zero);
      final pending = state.messagesOf(1).single;
      expect(pending.pending, isTrue);
      expect(pending.type, ChatMessageType.image);
      expect(pending.upload!.progress, 0.5);
      expect(state.conversations!.single.lastMessage!.preview, '📷 Photo');

      service.sendGate!.complete();
      await sending;
      final saved = state.messagesOf(1).single;
      expect(saved.pending, isFalse);
      expect(saved.attachment, isNotNull);
    });

    test('a failed photo keeps the reason and retries with the same id',
        () async {
      final service = _FakeMessaging()
        ..sendError = const BackendException('The video is too long.');
      final state = _state(service);
      await state.load(1);
      await state.sendMedia(1, _sam(),
          LocalUpload(bytes: _mp4, filename: 'v.mp4', isVideo: true));
      final failed = state.messagesOf(1).single;
      expect(failed.failed, isTrue);
      expect(failed.error, 'The video is too long.');

      service.sendError = null;
      await state.retry(1, _sam(), failed.clientId!);
      expect(service.calls.where((c) => c.startsWith('media')).toSet(),
          {'media v.mp4 ${failed.clientId}'});
      expect(state.messagesOf(1).single.failed, isFalse);
      expect(state.messagesOf(1).single.type, ChatMessageType.video);
    });

    test('an incoming photo is fetched for its preview; one sound', () async {
      final service = _FakeMessaging(history: [_media(1)]);
      final sound = _Sound();
      final state = _state(service, sound);
      await state.refresh();
      await state.load(1);
      final event = {
        'type': 'message.new',
        'conversation_id': 1,
        'message': {
          'id': 2,
          'conversation_id': 1,
          'sender_id': 7,
          'from_me': false,
          'type': 'image',
          'body': '',
          'created_at': _t0.toUtc().toIso8601String(),
          'attachment': {
            'id': 20,
            'media_type': 'image',
            'width': 4,
            'height': 4,
            'preview_url': null,
            'expires_at': null,
            'expired': false,
          },
        },
      };
      service.served[2] = _media(2);
      state.handleEvent(event);
      state.handleEvent(event); // delivered twice
      await Future<void>.delayed(Duration.zero);
      expect(sound.plays, 1);
      expect(service.calls, ['fetch 2']);
      expect(state.messagesOf(1).last.attachment!.previewUrl,
          'https://s3.test/p2.webp');
      expect(state.conversations!.single.lastMessage!.preview, '📷 Photo');
    });

    test('message.updated refreshes a shown message without a sound', () async {
      final service = _FakeMessaging(history: [_trade(3, fromMe: true)]);
      final sound = _Sound();
      final state = _state(service, sound);
      await state.refresh();
      await state.load(1);
      service.served[3] = _trade(3,
          fromMe: true, status: TradeStatus.completed, returned: 'Theirs');
      state.handleEvent(
          {'type': 'message.updated', 'conversation_id': 1, 'message_id': 3});
      state.handleEvent(
          {'type': 'message.updated', 'conversation_id': 1, 'message_id': 99});
      await Future<void>.delayed(Duration.zero);
      expect(service.calls, ['fetch 3']); // not shown: not fetched
      expect(state.messagesOf(1).single.trade!.status, TradeStatus.completed);
      expect(sound.plays, 0);
      expect(state.unreadTotal, 0);
    });

    test('a sync brings the newer state of messages already shown', () async {
      final service = _FakeMessaging(history: [_trade(3, fromMe: false)]);
      final state = _state(service);
      await state.load(1);
      state.setViewing(1);
      service.history[0] =
          _trade(3, fromMe: false, status: TradeStatus.cancelled);
      await state.sync();
      expect(state.messagesOf(1).single.trade!.status, TradeStatus.cancelled);
    });

    test('opening expired media refreshes it and says so', () async {
      final service = _FakeMessaging(history: [_media(4)])
        ..openError = const MediaExpiredException('This photo has expired.');
      final state = _state(service);
      await state.load(1);
      service.served[4] = _media(4, expired: true);
      await expectLater(state.openMedia(state.messagesOf(1).single),
          throwsA(isA<MediaExpiredException>()));
      await Future<void>.delayed(Duration.zero);
      expect(state.messagesOf(1).single.attachment!.expired, isTrue);
    });

    test('my own media past its deadline counts as expired', () {
      final m = _media(5, expiresAt: _t0.add(const Duration(hours: 1)));
      expect(m.attachment!.expiredAt(_t0), isFalse);
      expect(
          m.attachment!.expiredAt(_t0.add(const Duration(hours: 1))), isTrue);
    });
  });

  group('+ menu and album trades', () {
    testWidgets('the + menu offers its options', (tester) async {
      await _openChat(tester, _state(_FakeMessaging()));
      await tester.tap(find.byKey(const Key('attachButton')));
      await tester.pumpAndSettle();
      for (final label in [
        'Trade album',
        'Send photo or video',
        'Open camera'
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      // the text box is still there and still sends
      expect(find.byKey(const Key('messageInput')), findsOneWidget);
    });

    testWidgets('no albums: create one, add to it, and come back to the trade',
        (tester) async {
      final service = _FakeMessaging();
      final albums = _FakeAlbums([]);
      await _openChat(tester, _state(service), albums: albums);
      await _attach(tester, 'trade');

      expect(find.byKey(const Key('noAlbumsForTrade')), findsOneWidget);
      expect(find.text('Create an Album First'), findsOneWidget);
      expect(service.calls.where((c) => c.startsWith('offer')), isEmpty);

      await tester.tap(find.byKey(const Key('createAlbumForTrade')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Summer');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(MyAlbumScreen), findsOneWidget);

      // back from the album: the same trade, refreshed, to choose from
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(albums.loads, 2);
      expect(service.calls.where((c) => c.startsWith('offer')), isEmpty);
      expect(find.byKey(const Key('tradeAlbumList')), findsOneWidget);
      await tester.tap(find.byKey(const Key('tradeAlbum-90')));
      await tester.pumpAndSettle();
      expect(service.calls.single, startsWith('offer 90 '));
      expect(find.byType(AlbumTradeScreen), findsNothing);
      expect(find.byKey(const Key('tradeStatus')), findsOneWidget);
      expect(find.text('Beach'), findsOneWidget);
    });

    testWidgets('cancelling album creation stays in the trade', (tester) async {
      await _openChat(tester, _state(_FakeMessaging()),
          albums: _FakeAlbums([]));
      await _attach(tester, 'trade');
      await tester.tap(find.byKey(const Key('createAlbumForTrade')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Create an Album First'), findsOneWidget);
    });

    testWidgets('one album is listed too, and offered once chosen',
        (tester) async {
      final service = _FakeMessaging();
      await _openChat(tester, _state(service), albums: _FakeAlbums(['Only']));
      await _attach(tester, 'trade');
      expect(find.byKey(const Key('tradeAlbumList')), findsOneWidget);
      expect(service.calls, isEmpty);
      await tester.tap(find.byKey(const Key('tradeAlbum-60')));
      await tester.pumpAndSettle();
      expect(service.calls.single, startsWith('offer 60 '));
      expect(find.byType(AlbumTradeScreen), findsNothing);
    });

    testWidgets('several albums: choose one; closing offers nothing',
        (tester) async {
      final service = _FakeMessaging();
      await _openChat(tester, _state(service),
          albums: _FakeAlbums(['One', 'Two']));
      await _attach(tester, 'trade');
      expect(find.byKey(const Key('tradeAlbumList')), findsOneWidget);
      await tester.tap(find.byKey(const Key('closeTrade')));
      await tester.pumpAndSettle();
      expect(service.calls, isEmpty);

      await _attach(tester, 'trade');
      await tester.tap(find.byKey(const Key('tradeAlbum-61')));
      await tester.pumpAndSettle();
      expect(service.calls.single, startsWith('offer 61 '));
      expect(find.byType(AlbumTradeScreen), findsNothing);
    });

    testWidgets('a failed offer shows why and retries with the same id',
        (tester) async {
      final service = _FakeMessaging()
        ..offerError = const BackendException('Album not found.');
      await _openChat(tester, _state(service), albums: _FakeAlbums(['Only']));
      await _attach(tester, 'trade');
      await tester.tap(find.byKey(const Key('tradeAlbum-60')));
      await tester.pumpAndSettle();
      expect(find.text('Album not found.'), findsOneWidget);

      service.offerError = null;
      await tester.tap(find.byKey(const Key('tradeAlbum-60')));
      await tester.pumpAndSettle();
      final ids = service.calls.map((c) => c.split(' ').last).toSet();
      expect(service.calls, hasLength(2));
      expect(ids, hasLength(1)); // the same client id: stored once
      expect(find.byType(AlbumTradeScreen), findsNothing);
    });

    testWidgets('the recipient answers with their own album', (tester) async {
      final service = _FakeMessaging(history: [_trade(3, fromMe: false)]);
      await _openChat(tester, _state(service), albums: _FakeAlbums(['Mine']));
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Sam sent an album trade', findRichText: true),
          findsOneWidget);
      expect(find.text('3 photos · 1 video'), findsOneWidget);
      expect(find.byKey(const Key('tradeLock')), findsOneWidget);

      await tester.tap(find.byKey(const Key('respondTrade-30')));
      await tester.pumpAndSettle();
      expect(service.calls, isEmpty);
      await tester.tap(find.byKey(const Key('tradeAlbum-60')));
      await tester.pumpAndSettle();
      expect(service.calls, ['respond 30 60']);
      expect(find.byKey(const Key('tradeBack-30')), findsOneWidget);
      // my album chosen in return shows as its own card on my side
      expect(find.byKey(const Key('tradeBack-30')), findsOneWidget);
      expect(find.text('You traded back for “Beach”', findRichText: true),
          findsOneWidget);
      expect(find.text('Mine'), findsOneWidget);
      expect(find.byKey(const Key('openTheirs-30')), findsOneWidget);
      expect(find.byKey(const Key('respondTrade-30')), findsNothing);
      // a green open lock: their album can be opened now
      expect(
          find.descendant(
              of: find.byKey(const Key('openTheirs-30')),
              matching: find.byKey(const Key('tradeUnlocked'))),
          findsOneWidget);
    });

    testWidgets('the recipient with no albums creates one first',
        (tester) async {
      final service = _FakeMessaging(history: [_trade(3, fromMe: false)]);
      await _openChat(tester, _state(service), albums: _FakeAlbums([]));
      await tester.tap(find.byKey(const Key('respondTrade-30')));
      await tester.pumpAndSettle();
      expect(find.text('Create an Album First'), findsOneWidget);
      await tester.tap(find.byKey(const Key('createAlbumForTrade')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Back at you');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(service.calls, isEmpty);
      await tester.tap(find.byKey(const Key('tradeAlbum-90')));
      await tester.pumpAndSettle();
      expect(service.calls, ['respond 30 90']);
      expect(find.byKey(const Key('tradeBack-30')), findsOneWidget);
    });

    testWidgets('the sender can cancel a pending offer', (tester) async {
      final service = _FakeMessaging(history: [_trade(3, fromMe: true)]);
      await _openChat(tester, _state(service));
      expect(
          find.textContaining('Waiting for Sam to trade back'), findsOneWidget);
      await tester.tap(find.byKey(const Key('cancelTrade-30')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirmCancelTrade')));
      await tester.pumpAndSettle();
      expect(service.calls, ['cancel 30']);
      expect(find.text('Cancelled'), findsOneWidget);
    });
  });

  group('opening a traded album', () {
    testWidgets('completed: open their album; the countdown shows',
        (tester) async {
      final service = _FakeMessaging(history: [
        _trade(3,
            fromMe: false, status: TradeStatus.completed, returned: 'Mine')
      ]);
      await _openChat(tester, _state(service));
      expect(
          find.text('Disappears a while after you close it'), findsOneWidget);
      // both covers stay blurred, with View album in their centers
      expect(find.byKey(const Key('openMine-30-60')), findsOneWidget);
      expect(find.text('View album'), findsNWidgets(2));
      expect(service.calls.where((c) => c.startsWith('viewAlbum')), isEmpty);

      await tester.tap(find.byKey(const Key('openTheirs-30')));
      await tester.pump();
      await tester.pump();
      expect(find.byType(TradedAlbumViewerScreen), findsOneWidget);
      expect(service.calls, contains('viewAlbum 30'));
      expect(find.byKey(const Key('countdownPaused')), findsOneWidget);
      expect(find.text('“Beach” · 1 of 2'), findsOneWidget);
    });

    testWidgets('viewing their album never closes; leaving ends the session',
        (tester) async {
      final service = _FakeMessaging(history: [
        _trade(3,
            fromMe: false, status: TradeStatus.completed, returned: 'Mine')
      ]);
      final messaging = _state(service);
      await _openChat(tester, messaging);
      await tester.pumpWidget(MessagingScope(
          state: messaging,
          child: MaterialApp(
              home: TradedAlbumViewerScreen(
                  message: messaging.messagesOf(1).single))));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('tradedAlbumPages')), findsOneWidget);
      expect(find.byKey(const Key('countdownPaused')), findsOneWidget);
      // far past any deadline: still open, kept alive by heartbeats
      await tester.pump(const Duration(hours: 25));
      expect(find.byKey(const Key('tradedAlbumPages')), findsOneWidget);
      expect(service.calls.where((c) => c == 'heartbeat a30'), isNotEmpty);
      expect(service.calls, isNot(contains('end a30')));
      // leaving ends the session (the countdown starts on the backend)
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(service.calls, contains('end a30'));
    });

    testWidgets('an expired album can’t be opened', (tester) async {
      final service = _FakeMessaging(history: [
        _trade(3,
            fromMe: true,
            status: TradeStatus.completed,
            returned: 'Theirs',
            theirsExpired: true)
      ]);
      await _openChat(tester, _state(service));
      expect(find.byKey(const Key('tradeAlbumExpired')), findsOneWidget);
      expect(find.byKey(const Key('openTheirs-30')), findsNothing);
    });

    testWidgets('a pending offer can’t be opened, only seen blurred',
        (tester) async {
      final service = _FakeMessaging(history: [_trade(3, fromMe: false)]);
      await _openChat(tester, _state(service));
      expect(find.byKey(const Key('tradeLock')), findsOneWidget);
      expect(find.byKey(const Key('openTheirs-30')), findsNothing);
      await tester.tap(find.byKey(const Key('tradeLock')));
      await tester.pumpAndSettle();
      expect(find.byType(TradedAlbumViewerScreen), findsNothing);
      expect(service.calls.where((c) => c.startsWith('viewAlbum')), isEmpty);
    });

    testWidgets('my own album opens in my album screen', (tester) async {
      final service = _FakeMessaging(history: [_trade(3, fromMe: true)]);
      await _openChat(tester, _state(service), albums: _FakeAlbums(['Beach']));
      await tester.tap(find.byKey(const Key('openMine-30-50')));
      await tester.pumpAndSettle();
      expect(find.byType(MyAlbumScreen), findsOneWidget);
      expect(service.calls.where((c) => c.startsWith('viewAlbum')), isEmpty);
    });
  });

  group('photos and videos', () {
    testWidgets('a photo shows blurred until opened; opening asks for access',
        (tester) async {
      final service = _FakeMessaging(history: [_media(1)]);
      await _openChat(tester, _state(service));
      expect(find.text('Tap to view'), findsOneWidget);
      expect(service.calls.where((c) => c.startsWith('open')), isEmpty);

      await tester.tap(find.byKey(const Key('media-1')));
      await tester.pump();
      await tester.pump();
      expect(find.byType(ChatMediaViewerScreen), findsOneWidget);
      expect(service.calls, contains('open 10'));
      expect(find.byKey(const Key('countdownPaused')), findsOneWidget);
    });

    testWidgets('expired media shows a placeholder and can’t be opened',
        (tester) async {
      final service = _FakeMessaging(history: [
        _media(1, expired: true),
        _media(2,
            expiresAt: DateTime.now().subtract(const Duration(seconds: 1))),
      ]);
      await _openChat(tester, _state(service));
      expect(find.byKey(const Key('mediaExpired')), findsNWidgets(2));
      await tester.tap(find.byKey(const Key('media-1')));
      await tester.pumpAndSettle();
      expect(find.byType(ChatMediaViewerScreen), findsNothing);
      expect(service.calls.where((c) => c.startsWith('open')), isEmpty);
    });

    testWidgets('viewing a photo never closes it; leaving ends the session',
        (tester) async {
      final service = _FakeMessaging(history: [_media(1)]);
      final messaging = _state(service);
      await _openChat(tester, messaging);
      await tester.pumpWidget(MessagingScope(
        state: messaging,
        child: MaterialApp(
            home: ChatMediaViewerScreen(message: messaging.messagesOf(1)[0])),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('viewerImage')), findsOneWidget);
      expect(find.byKey(const Key('countdownPaused')), findsOneWidget);
      await tester.pump(const Duration(hours: 25));
      expect(find.byKey(const Key('viewerImage')), findsOneWidget);
      expect(find.byKey(const Key('viewerExpired')), findsNothing);
      expect(service.calls.where((c) => c == 'heartbeat v10'), isNotEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(service.calls, contains('end v10'));
    });

    testWidgets('an expired photo can’t be reopened from the viewer',
        (tester) async {
      final service = _FakeMessaging(history: [_media(1)])
        ..openError = const MediaExpiredException('This photo has expired.');
      await _openChat(tester, _state(service));
      await tester.tap(find.byKey(const Key('media-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('viewerExpired')), findsOneWidget);
    });

    testWidgets('sending an image from the library shows its upload',
        (tester) async {
      final picker = _FakePicker()
        ..next.add(XFile.fromData(_webp, name: 'pic.webp', path: 'pic.webp'));
      ChatMediaPicker.instance = picker;
      final service = _FakeMessaging()..sendGate = Completer();
      await _openChat(tester, _state(service));
      await _attach(tester, 'media');
      expect(find.byKey(const Key('uploadProgress')), findsOneWidget);
      expect(find.text('Sending…'), findsOneWidget);
      service.sendGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Tap to view'), findsOneWidget);
      expect(service.calls.where((c) => c.startsWith('media')).single,
          startsWith('media pic.webp'));
    });

    testWidgets('a rejected video shows why and can be retried',
        (tester) async {
      ChatMediaPicker.instance = _FakePicker()
        ..next.add(XFile.fromData(_mp4, name: 'clip.mov'));
      final service = _FakeMessaging()
        ..sendError = const BackendException(
            'The video is too long. The maximum is 60 seconds.');
      await _openChat(tester, _state(service));
      await _attach(tester, 'media');
      expect(find.text('Not sent · Tap to retry'), findsOneWidget);
      expect(find.byKey(const Key('sendError')), findsOneWidget);
    });

    testWidgets('a non-image is refused before upload', (tester) async {
      ChatMediaPicker.instance = _FakePicker()
        ..next.add(XFile.fromData(utf8.encode('GIF89a......'), name: 'a.gif'));
      final service = _FakeMessaging();
      await _openChat(tester, _state(service));
      await _attach(tester, 'media');
      expect(find.textContaining('GIFs aren'), findsOneWidget);
      expect(service.calls, isEmpty);
    });

    testWidgets('the camera capture is previewed; Retake, then Send',
        (tester) async {
      final picker = _FakePicker()
        ..next.addAll([
          XFile.fromData(_webp, name: 'first.webp', path: 'first.webp'),
          XFile.fromData(_webp, name: 'second.webp', path: 'second.webp'),
        ]);
      ChatMediaPicker.instance = picker;
      final service = _FakeMessaging();
      await _openChat(tester, _state(service));
      await _attach(tester, 'camera');
      await tester.tap(find.byKey(const Key('camera-photo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('capturePreview')), findsOneWidget);
      expect(service.calls, isEmpty); // nothing sent before confirming

      await tester.tap(find.byKey(const Key('retakeCapture')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sendCapture')));
      await tester.pumpAndSettle();
      expect(picker.captures, 2);
      expect(service.calls.where((c) => c.startsWith('media')).single,
          startsWith('media second.webp'));
    });

    testWidgets('no camera: says so', (tester) async {
      ChatMediaPicker.instance = _FakePicker(camera: false);
      await _openChat(tester, _state(_FakeMessaging()));
      await _attach(tester, 'camera');
      expect(find.textContaining('no camera'), findsOneWidget);
    });
  });
}
