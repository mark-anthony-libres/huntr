import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../models/models.dart';
import '../services/huntr_backend.dart';
import '../services/device_location.dart';
import '../services/location_service.dart' show LocationException;
import '../services/messaging_service.dart';

/// My direct messages, from the backend.
///
/// - Sending shows my message at once (pending), then swaps in the saved
///   one; a failed send can be retried with the same client id, so it's
///   stored once.
/// - New messages arrive as `message.new` events on the app's WebSocket; a
///   message already shown (same id) is never added twice.
/// - After a reconnect or coming back to the foreground, [sync] fetches what
///   was missed: the conversation list, and only the newer messages of the
///   conversation on screen.
/// - A `message.read` event (or a sync) marks my messages read ("Read").
/// - Photos, videos and album trades arrive without links; the message is
///   then fetched (GET /messages/{id}), as it is on `message.updated` (a
///   trade answered, a photo opened or expired).
/// - The incoming-message sound plays once per new message from the live
///   event, never for history, syncs, my own messages, or the conversation
///   I'm looking at.
class MessagingState extends ChangeNotifier {
  MessagingState({
    required this.service,
    required this.token,
    required this.playSound,
    this.onSessionRejected,
    this.location = const DeviceLocation(),
  });

  final MessagingService service;

  /// Where the device is, for sharing it (tests use their own).
  final DeviceLocation location;

  /// The current session token (null when signed out).
  final String? Function() token;
  final void Function() playSound;
  final void Function()? onSessionRejected;

  final Random _random = Random.secure();

  // ---- conversations ----

  /// Null until first loaded.
  List<ConversationSummary>? conversations;
  bool loading = false;
  String? loadError;

  /// My anonymous conversations (the Anonymous tab), both those I write
  /// anonymously and those written to me. Null until first loaded.
  List<ConversationSummary>? anonymousConversations;
  String? anonymousLoadError;

  /// Anonymous conversations I started that have no messages yet (the
  /// backend lists only those with messages).
  final Map<int, ConversationSummary> _started = {};

  /// Anonymous conversations that became direct ones (an accepted reveal):
  /// old id -> the direct conversation's id.
  final Map<int, int> _movedToDirect = {};

  // ---- pages: each list loads CONVERSATION_PAGE_SIZE at a time ----

  /// Where each list's next page starts (null: all of it is here).
  String? _directNext;
  String? _anonymousNext;
  bool _loadingMoreDirect = false;
  bool _loadingMoreAnonymous = false;

  /// Unread messages in conversations not loaded yet (the badge counts
  /// them too).
  int _directUnreadElsewhere = 0;
  int _anonymousUnreadElsewhere = 0;

  /// More of that list to load as it's scrolled.
  bool hasMore({required bool anonymous}) =>
      (anonymous ? _anonymousNext : _directNext) != null;

  static int _unreadIn(Iterable<ConversationSummary> list) =>
      list.fold<int>(0, (sum, c) => sum + c.unreadCount);

  int get directUnread =>
      _unreadIn(conversations ?? const []) + _directUnreadElsewhere;

  int get anonymousUnread =>
      _unreadIn(anonymousConversations ?? const []) + _anonymousUnreadElsewhere;

  /// Unread messages in both tabs (the Chats badge).
  int get unreadTotal => directUnread + anonymousUnread;

  ConversationSummary? summary(int conversationId) {
    for (final c in [
      ...?conversations,
      ...?anonymousConversations,
      ..._started.values
    ]) {
      if (c.id == conversationId) return c;
    }
    return null;
  }

  /// An anonymous conversation (sent text-only, through its own endpoint).
  bool isAnonymous(int conversationId) =>
      summary(conversationId)?.anonymous != null;

  /// The direct conversation this anonymous one became, after its sender
  /// showed their profile (null while it's still anonymous).
  int? movedToDirect(int conversationId) => _movedToDirect[conversationId];

  // ---- what's on screen ----

  /// The conversation open on screen (its new messages are read at once and
  /// make no sound), while the app is in the foreground.
  int? _viewing;
  bool _foreground = true;

  bool _isViewing(int conversationId) =>
      _foreground && _viewing == conversationId;

  final Map<int, _Thread> _threads = {};

  // ---- shared locations (once) ----

  /// The latest position of each one-time shared location, as it arrived.
  final Map<int, SharedPosition> _positions = {};

  /// The latest position of a shared location: the newest that arrived,
  /// else the one that came with the message; none once stopped.
  SharedPosition? positionOf(ChatMessage message) {
    final share = message.location;
    if (share == null || share.stopped) return null;
    return _positions[message.id] ?? share.position;
  }

  /// Shares where I am now, once. Throws what went wrong (no permission,
  /// the backend) for the caller to show.
  Future<void> shareLocation(int conversationId, Profile recipient) async {
    final here = await location.current();
    final reply = replyingTo(conversationId);
    final saved = await _call((t) => service.shareLocation(t,
        recipientId: recipient.backendId!,
        clientId: newClientId(),
        latitude: here.latitude,
        longitude: here.longitude,
        accuracy: here.accuracy,
        replyToId: reply?.id));
    if (saved == null) return;
    _doneReplying(conversationId, reply);
    _positions[saved.id!] = _shared(here);
    _threads
        .putIfAbsent(conversationId, () => _Thread()..loaded = true)
        .upsert(saved);
    _touchSummary(conversationId, recipient, saved, unreadDelta: 0);
    notifyListeners();
  }

  // ---- replies ----

  /// The message I'm replying to in each conversation (the banner above
  /// the message box); the next message I send there replies to it.
  final Map<int, ChatMessage> _replying = {};

  ChatMessage? replyingTo(int conversationId) => _replying[conversationId];

  /// Starts replying to [message] (null: stop replying).
  void setReplyingTo(int conversationId, ChatMessage? message) {
    if (message == null || message.id == null) {
      if (_replying.remove(conversationId) == null) return;
    } else {
      _replying[conversationId] = message;
    }
    notifyListeners();
  }

  /// Sent (an album, a location): stop replying, unless I've already
  /// picked another message meanwhile.
  void _doneReplying(int conversationId, ChatMessage? reply) {
    if (reply != null && identical(_replying[conversationId], reply)) {
      _replying.remove(conversationId);
    }
  }

  /// The quote for the message being sent now, and stops replying.
  ReplyPreview? _takeReply(int conversationId) {
    final message = _replying.remove(conversationId);
    return message == null ? null : ReplyPreview.of(message);
  }

  // ---- reactions ----

  /// Reacts to a text, photo or video with [emoji] (one each: it replaces
  /// mine), or removes my reaction when it's the one I already have. Shown
  /// at once; put back as it was (and rethrown) if the backend says no.
  Future<void> react(ChatMessage message, String emoji) async {
    if (!message.canReact) return;
    final remove = message.myReaction == emoji;
    final others = [
      for (final r in message.reactions)
        if (!r.fromMe) r
    ];
    _upsert(
        message.conversationId,
        message.copyWith(reactions: [
          ...others,
          if (!remove) MessageReaction(emoji: emoji, fromMe: true),
        ]));
    try {
      final saved = await _call(
          (t) => service.react(t, message.id!, remove ? null : emoji));
      if (saved != null) _upsert(message.conversationId, saved);
    } catch (_) {
      _upsert(message.conversationId, message);
      rethrow;
    }
  }

  /// I stop sharing a location: they can't see it any more.
  Future<void> stopSharingLocation(ChatMessage message) async {
    _positions.remove(message.id);
    notifyListeners();
    final saved =
        await _call((t) => service.stopSharingLocation(t, message.id!));
    if (saved != null) _upsert(message.conversationId, saved);
  }

  static SharedPosition _shared(DevicePosition p) => SharedPosition(
      latitude: p.latitude,
      longitude: p.longitude,
      accuracy: p.accuracy,
      at: DateTime.now());

  // ---- live location sessions ----

  /// Active sessions I'm sharing in, by message id.
  final Map<int, _LiveSession> _sessions = {};
  final Map<int, LivePositions> _livePositions = {};

  /// Something to tell the user about live sharing (e.g. location access
  /// was turned off), shown once by the chat screen.
  String? liveProblem;

  LivePositions livePositionsOf(int messageId) =>
      _livePositions[messageId] ?? const LivePositions();

  /// The live session I'm sharing in this conversation (for the banner).
  ChatMessage? liveSessionIn(int conversationId) {
    for (final session in _sessions.values) {
      if (session.message.conversationId == conversationId) {
        return session.message;
      }
    }
    return null;
  }

  /// Asks the other person to share live locations (nothing is shared
  /// until they accept). Throws what the backend says.
  Future<void> requestLiveLocation(
      int conversationId, Profile recipient) async {
    final reply = replyingTo(conversationId);
    final saved = await _call((t) => service.requestLiveLocation(t,
        recipientId: recipient.backendId!,
        clientId: newClientId(),
        replyToId: reply?.id));
    if (saved == null) return;
    _doneReplying(conversationId, reply);
    _threads
        .putIfAbsent(conversationId, () => _Thread()..loaded = true)
        .upsert(saved);
    _touchSummary(conversationId, recipient, saved, unreadDelta: 0);
    notifyListeners();
  }

  /// Location access was taken away: every live session I'm in ends for
  /// both (as when the location can't be read), and nothing more is sent.
  Future<void> stopAllLiveSharing() async {
    final live = [for (final s in _sessions.values) s.message];
    if (live.isEmpty) return;
    liveProblem = 'Location access was turned off, so live sharing stopped.';
    for (final m in live) {
      try {
        await stopLiveLocation(m, reason: 'permission');
      } on BackendException catch (error) {
        debugPrint('Live location stop: ${error.message}');
        unawaited(refreshMessage(m.conversationId, m.id!));
      }
    }
  }

  Future<void> acceptLiveLocation(ChatMessage m) => _liveAction(m, 'accept');
  Future<void> declineLiveLocation(ChatMessage m) => _liveAction(m, 'decline');
  Future<void> cancelLiveLocation(ChatMessage m) => _liveAction(m, 'cancel');

  /// Ends it for both ([reason] "permission" when my location access went
  /// away). My sharing stops at once.
  Future<void> stopLiveLocation(ChatMessage m, {String? reason}) {
    _endLocal(m.id!);
    notifyListeners();
    return _liveAction(m, 'stop', reason: reason);
  }

  Future<void> _liveAction(ChatMessage m, String action,
      {String? reason}) async {
    final saved = await _call(
        (t) => service.liveLocationAction(t, m.id!, action, reason: reason));
    if (saved != null) _upsert(m.conversationId, saved);
  }

  /// Both latest positions (when the map opens, or sharing (re)starts).
  Future<void> refreshLivePositions(ChatMessage m) async {
    try {
      final positions =
          await _call((t) => service.fetchLivePositions(t, m.id!));
      if (positions == null || !_sessions.containsKey(m.id)) return;
      final known = livePositionsOf(m.id!);
      _livePositions[m.id!] = LivePositions(
          me: known.me ?? positions.me, them: positions.them ?? known.them);
      notifyListeners();
    } catch (error) {
      debugPrint('Live positions not loaded: $error');
    }
  }

  /// Starts or stops my sharing to match each live message's state: only
  /// while it's active (so an ended one never resumes on its own).
  void _reconcileLive(Iterable<ChatMessage> messages) {
    for (final m in messages) {
      final info = m.liveLocation;
      if (info == null || m.id == null) continue;
      if (info.active) {
        final session = _sessions[m.id!];
        if (session == null && !_endedHere.contains(m.id)) {
          _startSession(m);
        } else {
          session?.message = m;
        }
      } else if (_sessions.containsKey(m.id) ||
          _livePositions.containsKey(m.id)) {
        _endLocal(m.id!);
      }
    }
  }

  void _endLocal(int messageId) {
    _sessions.remove(messageId)?.cancel();
    _livePositions.remove(messageId);
    _endedHere.add(messageId);
  }

  /// Sessions that ended on this device: never started again, even when a
  /// copy of the message from before the end (still "active") arrives.
  final Set<int> _endedHere = {};

  static const _liveMinMove = 25;
  static const _liveEvery = Duration(seconds: 10);

  /// Shares my position while the session is active: when I moved
  /// [_liveMinMove] metres (at most every [_liveEvery]), plus a heartbeat
  /// so I'm not counted offline while standing still.
  Future<void> _startSession(ChatMessage m) async {
    final session = _sessions[m.id!] = _LiveSession(m);
    unawaited(refreshLivePositions(m));
    final DevicePosition here;
    try {
      here = await location.current();
    } catch (error) {
      return _locationLost(session, error);
    }
    if (!identical(_sessions[m.id], session)) return; // ended meanwhile
    await _sendPosition(session, here);
    if (!identical(_sessions[m.id], session)) return; // it was refused
    session.heartbeat =
        Timer.periodic(m.liveLocation!.heartbeat, (_) => _beat(session));
    session.moves = location.watch(minDistance: _liveMinMove).listen((p) {
      session.latest = p;
      _maybeSend(session);
    }, onError: (Object error) => _locationLost(session, error));
  }

  /// Location access went away: tell them, and end it for both (never keep
  /// showing a stale position as live).
  Future<void> _locationLost(_LiveSession session, Object error) async {
    if (!identical(_sessions[session.message.id], session)) return;
    liveProblem = error is LocationException
        ? error.message
        : 'Your location couldn\u2019t be read, so live sharing stopped.';
    try {
      await stopLiveLocation(session.message, reason: 'permission');
    } on BackendException catch (error) {
      // e.g. it had already ended: show it as the backend has it
      debugPrint('Live location stop: ${error.message}');
      unawaited(
          refreshMessage(session.message.conversationId, session.message.id!));
    }
  }

  void _maybeSend(_LiveSession session) {
    final p = session.latest;
    final sent = session.sent;
    if (p == null || (sent != null && p.distanceTo(sent) < _liveMinMove)) {
      return;
    }
    if (session.cooldown != null) {
      session.waiting = true; // the newest goes out after the cooldown
      return;
    }
    _sendPosition(session, p);
  }

  Future<void> _sendPosition(_LiveSession session, DevicePosition p) async {
    session.sent = p;
    session.waiting = false;
    session.cooldown?.cancel();
    session.cooldown = Timer(_liveEvery, () {
      session.cooldown = null;
      if (session.waiting) _maybeSend(session);
    });
    final id = session.message.id!;
    _livePositions[id] = livePositionsOf(id).copyWith(me: _shared(p));
    notifyListeners();
    try {
      await _call((t) => service.sendLivePosition(t, id,
          latitude: p.latitude, longitude: p.longitude, accuracy: p.accuracy));
    } on BackendException catch (error) {
      _ended(session, error);
    } catch (error) {
      debugPrint('Live position not sent: $error');
    }
  }

  Future<void> _beat(_LiveSession session) async {
    try {
      await _call((t) => service.liveHeartbeat(t, session.message.id!));
    } on BackendException catch (error) {
      _ended(session, error);
    } catch (error) {
      debugPrint('Live heartbeat failed: $error');
    }
  }

  /// The backend says it's over (stopped elsewhere, or I was offline too
  /// long): stop sharing and show why.
  void _ended(_LiveSession session, BackendException error) {
    if (error is SessionRejectedException) return;
    _endLocal(session.message.id!);
    unawaited(
        refreshMessage(session.message.conversationId, session.message.id!));
    notifyListeners();
  }

  // ---- typing ----

  /// Conversations where the other person is typing (each drops after
  /// [_typingShownFor] without a new event).
  final Map<int, Timer> _typing = {};
  static const _typingShownFor = Duration(seconds: 6);

  /// When I last said I'm typing, per conversation (sent every few seconds
  /// at most).
  final Map<int, DateTime> _typingSent = {};
  static const _typingEvery = Duration(seconds: 3);

  bool isTyping(int conversationId) => _typing.containsKey(conversationId);

  /// My message box has text ([active]) or was cleared. Only tells the
  /// other person when it changes, or every few seconds while typing.
  Future<void> notifyTyping(int conversationId, bool active) async {
    final last = _typingSent[conversationId];
    if (active) {
      if (last != null && DateTime.now().difference(last) < _typingEvery) {
        return;
      }
      _typingSent[conversationId] = DateTime.now();
    } else {
      if (last == null) return; // never said I was typing
      _typingSent.remove(conversationId);
    }
    try {
      await _call((t) => service.typing(t, conversationId, active));
    } catch (error) {
      debugPrint('Typing not sent: $error');
    }
  }

  /// The other person's live position (in memory only).
  void _handleLivePosition(Map<String, dynamic> event) {
    final messageId = event['message_id'];
    final latitude = event['latitude'];
    final longitude = event['longitude'];
    if (messageId is! int || latitude is! num || longitude is! num) return;
    if (!_sessions.containsKey(messageId)) return; // not sharing: ignore
    _livePositions[messageId] = livePositionsOf(messageId).copyWith(
        them: SharedPosition(
            latitude: latitude.toDouble(),
            longitude: longitude.toDouble(),
            accuracy: (event['accuracy'] as num?)?.toDouble(),
            at: DateTime.now()));
    notifyListeners();
  }

  /// It ended (either of us stopped, or went offline): stop sharing now.
  void _handleLiveEnded(Map<String, dynamic> event) {
    final messageId = event['message_id'];
    final conversationId = event['conversation_id'];
    if (messageId is! int || conversationId is! int) return;
    _endLocal(messageId);
    notifyListeners();
    unawaited(refreshMessage(conversationId, messageId));
  }

  /// Their shared location's position (kept in memory only).
  void _handleLocation(Map<String, dynamic> event) {
    final messageId = event['message_id'];
    final latitude = event['latitude'];
    final longitude = event['longitude'];
    if (messageId is! int || latitude is! num || longitude is! num) return;
    _positions[messageId] = SharedPosition(
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
        accuracy: (event['accuracy'] as num?)?.toDouble(),
        at: DateTime.now());
    notifyListeners();
  }

  void _handleTyping(Map<String, dynamic> event) {
    final conversationId = event['conversation_id'];
    if (conversationId is! int) return;
    _typing.remove(conversationId)?.cancel();
    if (event['active'] != false) {
      _typing[conversationId] = Timer(_typingShownFor, () {
        _typing.remove(conversationId);
        notifyListeners();
      });
    }
    notifyListeners();
  }

  final Set<int> _sounded = {};

  List<ChatMessage> messagesOf(int conversationId) =>
      _threads[conversationId]?.messages ?? const [];
  bool hasOlder(int conversationId) =>
      _threads[conversationId]?.hasMore ?? false;

  /// Loading older messages failed (see [loadOlder] with `retry`).
  bool olderFailed(int conversationId) =>
      _threads[conversationId]?.olderFailed ?? false;
  bool isLoaded(int conversationId) =>
      _threads[conversationId]?.loaded ?? false;

  /// Why the conversation's messages couldn't be loaded (null if they could).
  String? loadErrorOf(int conversationId) => _threads[conversationId]?.error;

  // ---- loading ----

  Future<T?> _call<T>(Future<T> Function(String token) request) async {
    final current = token();
    if (current == null) return null;
    try {
      return await request(current);
    } on SessionRejectedException {
      onSessionRejected?.call();
      return null;
    }
  }

  /// The conversation list (its first page; older pages already loaded
  /// stay, unless [fresh]) and unread counts.
  Future<void> refresh({bool fresh = false}) async {
    loading = true;
    loadError = null;
    notifyListeners();
    // the Anonymous tab loads alongside, on its own: Direct never waits
    // for it (nor fails with it)
    final anonymous = _anonymousRefresh = refreshAnonymous(fresh: fresh);
    unawaited(anonymous);
    try {
      final page = await _call(service.fetchConversations);
      if (page != null) {
        final (list, next) =
            _withFirstPage(conversations, _directNext, page, keepOlder: !fresh);
        conversations = list;
        _directNext = next;
        _directUnreadElsewhere = max(0, page.unreadTotal - _unreadIn(list));
      }
    } catch (error) {
      loadError = error is BackendException
          ? error.message
          : 'Check your connection and try again.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// [page] (a new first page) in place of the list's start. With
  /// [keepOlder], the older pages already loaded stay after it (and where
  /// they end is still the next page); otherwise it's just this page.
  (List<ConversationSummary>, String?) _withFirstPage(
      List<ConversationSummary>? loaded,
      String? loadedNext,
      ConversationPage page,
      {required bool keepOlder}) {
    final first = page.conversations;
    if (!keepOlder || page.nextBefore == null || loaded == null) {
      return ([...first], page.nextBefore);
    }
    final oldest = first.isEmpty ? null : first.last.lastMessage?.sentAt;
    final ids = {for (final c in first) c.id};
    final older = [
      for (final c in loaded)
        if (!ids.contains(c.id) &&
            oldest != null &&
            (c.lastMessage?.sentAt.isBefore(oldest) ?? true))
          c
    ];
    // nothing older was loaded: the page's own next one
    return ([...first, ...older], older.isEmpty ? page.nextBefore : loadedNext);
  }

  /// The next page of the Direct (or Anonymous) list, as it's scrolled.
  Future<void> loadMore({required bool anonymous}) async {
    final next = anonymous ? _anonymousNext : _directNext;
    if (next == null ||
        (anonymous ? _loadingMoreAnonymous : _loadingMoreDirect)) {
      return;
    }
    anonymous ? _loadingMoreAnonymous = true : _loadingMoreDirect = true;
    try {
      final page = await _call((t) => anonymous
          ? service.fetchAnonymousConversations(t, before: next)
          : service.fetchConversations(t, before: next));
      if (page == null) return;
      final list =
          anonymous ? (anonymousConversations ??= []) : (conversations ??= []);
      final known = {for (final c in list) c.id};
      // one that moved to the top meanwhile is already listed
      final arrived = [
        for (final c in page.conversations)
          if (!known.contains(c.id)) c
      ];
      list.addAll(arrived);
      if (anonymous) {
        _anonymousNext = page.nextBefore;
        _anonymousUnreadElsewhere =
            max(0, _anonymousUnreadElsewhere - _unreadIn(arrived));
      } else {
        _directNext = page.nextBefore;
        _directUnreadElsewhere =
            max(0, _directUnreadElsewhere - _unreadIn(arrived));
      }
    } catch (error) {
      debugPrint('More conversations not loaded: $error');
    } finally {
      anonymous ? _loadingMoreAnonymous = false : _loadingMoreDirect = false;
      notifyListeners();
    }
  }

  /// The Anonymous tab's load started by the last [refresh].
  Future<void>? _anonymousRefresh;

  /// Chats gone because of an unmatch (until it's removed again): an open
  /// chat screen shows it's closed instead of a message box.
  final Set<int> _gone = {};

  bool isGone(int conversationId) => _gone.contains(conversationId);

  /// Both lists again, from their first page; chats that were listed and
  /// aren't now are gone (only those the new first pages cover: older ones
  /// can't tell yet).
  Future<void> _refreshAfterUnmatch() async {
    final before = [...?conversations, ...?anonymousConversations];
    await refresh(fresh: true);
    await _anonymousRefresh;
    final after = {
      for (final c in [...?conversations, ...?anonymousConversations]) c.id
    };
    bool covered(ConversationSummary c) {
      final anonymous = c.anonymous != null;
      if (!hasMore(anonymous: anonymous)) return true;
      final list = (anonymous ? anonymousConversations : conversations) ?? [];
      final oldest = list.isEmpty ? null : list.last.lastMessage?.sentAt;
      final at = c.lastMessage?.sentAt;
      return oldest != null && at != null && !at.isBefore(oldest);
    }

    _gone
      ..addAll([
        for (final c in before)
          if (!after.contains(c.id) && covered(c)) c.id
      ])
      ..removeAll(after);
    notifyListeners();
  }

  /// The Anonymous tab's conversations (also loaded by [refresh]).
  Future<void> refreshAnonymous({bool fresh = false}) async {
    anonymousLoadError = null;
    try {
      final page = await _call(service.fetchAnonymousConversations);
      if (page != null) {
        final (list, next) = _withFirstPage(
            anonymousConversations, _anonymousNext, page,
            keepOlder: !fresh);
        anonymousConversations = list;
        _anonymousNext = next;
        _anonymousUnreadElsewhere = max(0, page.unreadTotal - _unreadIn(list));
        // listed now that they have messages
        _started.removeWhere((id, _) => list.any((c) => c.id == id));
      }
    } catch (error) {
      anonymousLoadError = error is BackendException
          ? error.message
          : 'Check your connection and try again.';
    }
    notifyListeners();
  }

  // ---- anonymous messaging ----

  /// The anonymous sender, as I (the recipient) may see them.
  Future<AnonymousProfile?> anonymousProfile(int conversationId) =>
      _call((t) => service.fetchAnonymousProfile(t, conversationId));

  /// Ask the anonymous sender to show their profile. Throws what the
  /// backend says.
  Future<AnonymousProfile?> requestReveal(int conversationId) async {
    final profile =
        await _call((t) => service.requestReveal(t, conversationId));
    if (profile?.reveal case final reveal?) {
      final current = summary(conversationId);
      if (current != null) _replaceSummary(current.copyWith(reveal: reveal));
      notifyListeners();
    }
    return profile;
  }

  /// The anonymous sender answers: accepted, the chat becomes a direct one;
  /// declined, they're blocked by the other person. Throws what the backend
  /// says.
  Future<RevealAnswer?> answerReveal(int conversationId, bool accept) async {
    final answer =
        await _call((t) => service.answerReveal(t, conversationId, accept));
    if (answer?.directConversationId case final direct?) {
      _becameDirect(conversationId, direct);
    }
    await refresh();
    return answer;
  }

  void _becameDirect(int anonymousId, int directId) {
    _movedToDirect[anonymousId] = directId;
    if (directId != anonymousId) {
      // merged into the direct conversation: it loads again with them
      _threads.remove(directId);
      _threads.remove(anonymousId);
    } else {
      // the same conversation: its senders are shown from now on
      _threads.remove(anonymousId);
    }
  }

  Future<void> reportAnonymous(int conversationId,
          {required String reason, String? details}) =>
      _call((t) => service.reportAnonymous(t, conversationId,
          reason: reason, details: details));

  /// My Anonymous messaging setting, as saved. Throws what the backend says.
  Future<bool?> setAnonymousMessaging(bool enabled) =>
      _call((t) => service.setAnonymousMessaging(t, enabled));

  /// Message on their profile: the id of our direct conversation, or of my
  /// anonymous one with them (started the first time). Throws what the
  /// backend says (a block, an unmatch, their pending reveal request).
  Future<int?> messageTarget(Profile other) async {
    final userId = other.backendId;
    if (userId == null) return null;
    final target = await _call((t) => service.startConversation(t, userId));
    if (target == null) return null;
    final anonymous = target.anonymous;
    if (anonymous != null && summary(anonymous.id) == null) {
      _started[anonymous.id] = anonymous;
      notifyListeners();
    }
    return target.conversationId;
  }

  // ---- unmatching ----

  /// I unmatch them (someone I know): our chats leave both lists. Throws
  /// what the backend says.
  Future<void> unmatch(int userId) async {
    await _call((t) => service.unmatch(t, userId));
    await _refreshAfterUnmatch();
  }

  /// I unmatch the other member of this anonymous chat.
  Future<void> unmatchAnonymous(int conversationId) async {
    await _call((t) => service.setAnonymousUnmatch(t, conversationId, true));
    await _refreshAfterUnmatch();
  }

  /// My Unmatched Users list.
  Future<List<UnmatchedPerson>?> unmatches() => _call(service.fetchUnmatches);

  /// Their profile, opened from my Unmatched Users list.
  Future<Profile?> unmatchedProfile(int userId) =>
      _call((t) => service.fetchUnmatchedProfile(t, userId));

  /// Takes them off my list ([userId]; or, someone I only know anonymously,
  /// by their conversation). Throws what the backend says.
  Future<void> removeUnmatch(
      {int? userId, int? anonymousConversationId}) async {
    if (userId != null) {
      await _call((t) => service.removeUnmatch(t, userId));
    } else if (anonymousConversationId != null) {
      await _call((t) =>
          service.setAnonymousUnmatch(t, anonymousConversationId, false));
    }
    await _refreshAfterUnmatch();
  }

  /// The newest page, the first time the conversation is opened.
  Future<void> load(int conversationId) async {
    final thread = _threads.putIfAbsent(conversationId, _Thread.new);
    if (thread.loaded) {
      // opened again: what's new, and fresh links for what's shown (preview
      // links only last a while); it still shows what it has if this fails
      try {
        await catchUp(conversationId);
        await _refreshNewest(conversationId);
      } catch (error) {
        debugPrint('Refreshing conversation $conversationId failed: $error');
      }
      return;
    }
    if (thread.error != null) {
      thread.error = null;
      notifyListeners();
    }
    try {
      final page = await _call((t) => service.fetchMessages(t, conversationId));
      if (page == null) return;
      thread
        ..merge(page.messages)
        ..hasMore = page.hasMore
        ..loaded = true;
      _reconcileLive(page.messages);
    } catch (error) {
      thread.error = error is BackendException
          ? error.message
          : 'Check your connection and try again.';
    }
    notifyListeners();
  }

  /// Older messages, when scrolling up.
  /// The page before the oldest message I have. After a failure it only
  /// tries again when asked to ([retry]: the user tapped).
  Future<void> loadOlder(int conversationId, {bool retry = false}) async {
    final thread = _threads[conversationId];
    final oldest = thread?.oldestId;
    if (thread == null ||
        !thread.hasMore ||
        thread.loadingOlder ||
        (thread.olderFailed && !retry) ||
        oldest == null) {
      return;
    }
    thread
      ..loadingOlder = true
      ..olderFailed = false;
    try {
      final page = await _call(
          (t) => service.fetchMessages(t, conversationId, before: oldest));
      if (page != null) {
        thread
          ..merge(page.messages)
          ..hasMore = page.hasMore;
      }
    } catch (error) {
      thread.olderFailed = true;
      debugPrint('Older messages not loaded: $error');
    } finally {
      thread.loadingOlder = false;
      notifyListeners();
    }
  }

  /// Only what's newer than the newest message I have (not the history).
  Future<void> catchUp(int conversationId) async {
    final thread = _threads[conversationId];
    if (thread == null || !thread.loaded) return;
    var more = true;
    while (more) {
      final page = await _call((t) => service.fetchMessages(t, conversationId,
          after: thread.newestId ?? 0));
      if (page == null) return;
      thread.merge(page.messages);
      _reconcileLive(page.messages);
      more = page.hasMore && page.messages.isNotEmpty;
    }
    notifyListeners();
  }

  /// The newest page again, for what changed on messages I already have.
  Future<void> _refreshNewest(int conversationId) async {
    final thread = _threads[conversationId];
    if (thread == null || !thread.loaded) return;
    final page = await _call((t) => service.fetchMessages(t, conversationId));
    if (page == null) return;
    thread.merge(page.messages);
    _reconcileLive(page.messages);
    notifyListeners();
  }

  /// After a reconnect or coming back to the foreground: no sounds here.
  Future<void> sync() async {
    await refresh();
    final viewing = _viewing;
    if (viewing != null) {
      try {
        await catchUp(viewing);
        await _refreshNewest(viewing); // read flags missed while away
      } catch (error) {
        debugPrint('Catching up conversation $viewing failed: $error');
      }
      await markRead(viewing);
    }
  }

  // ---- reading ----

  void setViewing(int? conversationId) {
    _viewing = conversationId;
    if (conversationId != null) unawaited(markRead(conversationId));
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    final viewing = _viewing;
    if (foreground && viewing != null) unawaited(markRead(viewing));
  }

  Future<void> markRead(int conversationId) async {
    final current = summary(conversationId);
    if (current == null || current.unreadCount == 0) return;
    _replaceSummary(current.copyWith(unreadCount: 0));
    notifyListeners();
    try {
      await _call((t) => service.markRead(t, conversationId));
    } catch (error) {
      debugPrint('Marking conversation $conversationId read failed: $error');
    }
  }

  // ---- sending ----

  /// Shows my message at once, then saves it.
  Future<void> send(int conversationId, Profile recipient, String body) {
    final text = body.trim();
    if (text.isEmpty) return Future.value();
    return _showAndSend(conversationId, recipient, body: text);
  }

  /// A GIF or sticker picked in the GIF picker: shown at once, then saved.
  Future<void> sendGif(int conversationId, Profile recipient, ChatGif gif) =>
      _showAndSend(conversationId, recipient, gif: gif);

  /// GIFs or stickers for the GIF picker (trending when [query] is empty;
  /// null when signed out).
  Future<GifPage?> gifs(
          {required bool stickers, String query = '', int offset = 0}) =>
      _call((t) => service.fetchGifs(t,
          stickers: stickers, query: query, offset: offset));

  /// My text or GIF message, in the chat at once, then saved.
  Future<void> _showAndSend(int conversationId, Profile recipient,
      {String body = '', ChatGif? gif}) {
    final anonymous = isAnonymous(conversationId);
    if (recipient.backendId == null && !anonymous) return Future.value();
    final pending = ChatMessage(
      id: null,
      conversationId: conversationId,
      fromMe: true,
      body: body,
      sentAt: DateTime.now(),
      clientId: newClientId(),
      type: gif == null ? ChatMessageType.text : ChatMessageType.gif,
      gif: gif,
      replyTo: _takeReply(conversationId),
    );
    _threads
        .putIfAbsent(conversationId, () => _Thread()..loaded = true)
        .add(pending);
    _touchSummary(conversationId, recipient, pending, unreadDelta: 0);
    notifyListeners();
    return anonymous
        ? _deliverAnonymous(pending)
        : _deliver(pending, recipient.backendId!);
  }

  /// Shows my photo or video at once (with its upload progress), then sends
  /// it; the backend processes it.
  Future<void> sendMedia(
      int conversationId, Profile recipient, LocalUpload upload) {
    if (recipient.backendId == null) return Future.value();
    final pending = ChatMessage(
      id: null,
      conversationId: conversationId,
      fromMe: true,
      body: '',
      sentAt: DateTime.now(),
      clientId: newClientId(),
      type: upload.isVideo ? ChatMessageType.video : ChatMessageType.image,
      upload: upload,
      replyTo: _takeReply(conversationId),
    );
    _threads
        .putIfAbsent(conversationId, () => _Thread()..loaded = true)
        .add(pending);
    _touchSummary(conversationId, recipient, pending, unreadDelta: 0);
    notifyListeners();
    return _deliverMedia(pending, recipient.backendId!);
  }

  /// Sends a failed message again with the same client id (stored once).
  Future<void> retry(int conversationId, Profile recipient, String clientId) {
    final thread = _threads[conversationId];
    final failed = thread?.byClientId(clientId);
    final anonymous = isAnonymous(conversationId);
    if (thread == null ||
        failed == null ||
        !failed.failed ||
        (recipient.backendId == null && !anonymous)) {
      return Future.value();
    }
    final again = failed.copyWith(
        failed: false,
        clearError: true,
        upload: failed.upload?.withProgress(0));
    thread.replace(failed, again);
    notifyListeners();
    if (anonymous) return _deliverAnonymous(again);
    return again.upload != null
        ? _deliverMedia(again, recipient.backendId!)
        : _deliver(again, recipient.backendId!);
  }

  Future<void> _deliverMedia(ChatMessage pending, int recipientId) async {
    final thread = _threads[pending.conversationId]!;
    final upload = pending.upload!;
    var shown = 0.0;
    void progress(double sent) {
      // a step at a time, not a rebuild per chunk
      if (sent < 1 && sent - shown < 0.05) return;
      shown = sent;
      final mine = thread.byClientId(pending.clientId!);
      if (mine == null || !mine.pending) return;
      thread.replace(mine, mine.copyWith(upload: upload.withProgress(sent)));
      notifyListeners();
    }

    try {
      final saved = await _call((t) => service.sendMedia(t,
          recipientId: recipientId,
          bytes: upload.bytes,
          filename: upload.filename,
          clientId: pending.clientId!,
          replyToId: pending.replyTo?.id,
          onProgress: progress));
      if (saved == null) return;
      thread.confirm(pending.clientId!, saved);
      final current = summary(pending.conversationId);
      if (current != null &&
          current.lastMessage?.clientId == pending.clientId) {
        _replaceSummary(current.copyWith(lastMessage: saved));
      }
    } catch (error) {
      debugPrint('Media not sent: $error');
      final mine = thread.byClientId(pending.clientId!);
      if (mine != null && mine.pending) {
        thread.replace(
            mine,
            mine.copyWith(
                failed: true,
                error: error is BackendException ? error.message : null));
      }
    }
    notifyListeners();
  }

  /// Offers one of my albums; the trade card appears in the chat. Throws
  /// what the backend says (e.g. not my album) for the trade flow to show.
  Future<void> offerAlbum(int conversationId, Profile recipient, int albumId,
      {required String clientId}) async {
    final reply = replyingTo(conversationId);
    final saved = await _call((t) => service.offerAlbum(t,
        recipientId: recipient.backendId!,
        albumId: albumId,
        clientId: clientId,
        replyToId: reply?.id));
    if (saved == null) return;
    _doneReplying(conversationId, reply);
    _threads
        .putIfAbsent(conversationId, () => _Thread()..loaded = true)
        .upsert(saved);
    _touchSummary(conversationId, recipient, saved, unreadDelta: 0);
    notifyListeners();
  }

  /// I choose one of my albums in return: the trade is completed.
  Future<void> respondToTrade(
      int conversationId, AlbumTrade trade, int albumId) async {
    final saved =
        await _call((t) => service.respondToTrade(t, trade.id, albumId));
    if (saved != null) _upsert(conversationId, saved);
  }

  Future<void> cancelTrade(int conversationId, AlbumTrade trade) async {
    final saved = await _call((t) => service.cancelTrade(t, trade.id));
    if (saved != null) _upsert(conversationId, saved);
  }

  /// Access to the actual photo or video (the recipient's first open starts
  /// its countdown). Throws [MediaExpiredException] once it has expired; the
  /// message is then refreshed to show that.
  Future<MediaAccess?> openMedia(ChatMessage message) async {
    try {
      final access =
          await _call((t) => service.openMedia(t, message.attachment!.id));
      // the countdown may have just started: show its deadline
      if (access != null && !message.fromMe) {
        unawaited(refreshMessage(message.conversationId, message.id!));
      }
      return access;
    } on MediaExpiredException {
      unawaited(refreshMessage(message.conversationId, message.id!));
      rethrow;
    }
  }

  /// The other person's album of a completed trade (my first open starts
  /// my countdown). Throws [MediaExpiredException] once it has expired; the
  /// card is then refreshed to show that.
  Future<TradedAlbumAccess?> viewTradedAlbum(ChatMessage message) async {
    try {
      final access =
          await _call((t) => service.viewTradedAlbum(t, message.trade!.id));
      // the countdown may have just started: show it on the card
      if (access != null) {
        unawaited(refreshMessage(message.conversationId, message.id!));
      }
      return access;
    } on MediaExpiredException {
      unawaited(refreshMessage(message.conversationId, message.id!));
      rethrow;
    }
  }

  /// The viewer is still open (keeps its session, and the paused countdown).
  Future<void> viewHeartbeat(MediaView view) async {
    try {
      await _call((t) => service.viewHeartbeat(t, view.token));
    } catch (error) {
      debugPrint('Viewer heartbeat failed: $error');
    }
  }

  /// The viewer was closed: its media can't be loaded any more and the
  /// recipient's countdown starts (the card is refreshed to show it).
  Future<void> endView(MediaView view, ChatMessage message) async {
    try {
      await _call((t) => service.endView(t, view.token));
    } catch (error) {
      debugPrint('Closing the viewer failed: $error');
    }
    if (message.id != null) {
      await refreshMessage(message.conversationId, message.id!);
    }
  }

  /// Fetches one message again (its links, trade status or expiry).
  Future<void> refreshMessage(int conversationId, int messageId) async {
    try {
      final fresh = await _call((t) => service.fetchMessage(t, messageId));
      if (fresh != null) _upsert(conversationId, fresh);
    } catch (error) {
      debugPrint('Message $messageId could not be refreshed: $error');
    }
  }

  void _upsert(int conversationId, ChatMessage message) {
    _reconcileLive([message]);
    if (message.location?.stopped ?? false) _positions.remove(message.id);
    final thread = _threads[conversationId];
    if (thread != null && thread.loaded) thread.upsert(message);
    final current = summary(conversationId);
    if (current?.lastMessage?.id == message.id) {
      _replaceSummary(current!.copyWith(lastMessage: message));
    }
    notifyListeners();
  }

  Future<void> _deliver(ChatMessage pending, int recipientId) async {
    final thread = _threads[pending.conversationId]!;
    try {
      final saved = await _call((t) => service.send(t,
          recipientId: recipientId,
          body: pending.body,
          clientId: pending.clientId!,
          replyToId: pending.replyTo?.id,
          gifId: pending.gif?.id));
      if (saved == null) return;
      thread.confirm(pending.clientId!, saved);
      final current = summary(pending.conversationId);
      if (current != null &&
          current.lastMessage?.clientId == pending.clientId) {
        _replaceSummary(current.copyWith(lastMessage: saved));
      }
    } catch (error) {
      debugPrint('Message not sent: $error');
      final mine = thread.byClientId(pending.clientId!);
      if (mine != null && mine.pending) {
        thread.replace(mine, mine.copyWith(failed: true));
      }
    }
    notifyListeners();
  }

  /// Text or a GIF in an anonymous conversation (by conversation: the
  /// anonymous side's id is never known here).
  Future<void> _deliverAnonymous(ChatMessage pending) async {
    final thread = _threads[pending.conversationId]!;
    try {
      final saved = await _call((t) => service.sendAnonymous(t,
          conversationId: pending.conversationId,
          body: pending.body,
          clientId: pending.clientId!,
          replyToId: pending.replyTo?.id,
          gifId: pending.gif?.id));
      if (saved == null) return;
      thread.confirm(pending.clientId!, saved);
      final current = summary(pending.conversationId);
      if (current != null &&
          current.lastMessage?.clientId == pending.clientId) {
        _replaceSummary(current.copyWith(lastMessage: saved));
      }
    } catch (error) {
      debugPrint('Anonymous message not sent: $error');
      final mine = thread.byClientId(pending.clientId!);
      if (mine != null && mine.pending) {
        thread.replace(
            mine,
            mine.copyWith(
                failed: true,
                error: error is BackendException ? error.message : null));
      }
      // e.g. they asked to see my profile meanwhile: the list says so
      if (error is BackendException) unawaited(refresh());
    }
    notifyListeners();
  }

  /// A new client id for a message, an album offer or a story reply (kept and
  /// reused if it has to be sent again, so it is stored once).
  String newClientId() => List.generate(
      16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  // ---- live events (from the WebSocket) ----

  /// A `message.new` event for me: added once, counted unread unless I'm
  /// looking at it, and announced with the sound once.
  /// A block between me and this person was made or lifted (either side).
  void Function(int userId)? onBlockChanged;

  void handleEvent(Map<String, dynamic> event) {
    if (event['type'] == 'block.changed') {
      final userId = event['user_id'];
      if (userId is int) onBlockChanged?.call(userId);
      unawaited(refresh()); // the chat list shows it
      return;
    }
    if (event['type'] == 'unmatch.changed') {
      unawaited(_refreshAfterUnmatch()); // their chats leave (or come back)
      return;
    }
    if (event['type'] == 'anonymous.reveal_requested') {
      unawaited(refresh());
      return;
    }
    if (event['type'] == 'anonymous.reveal_answered') {
      final id = event['conversation_id'];
      final direct = event['direct_conversation_id'];
      if (event['status'] == 'accepted' && id is int && direct is int) {
        _becameDirect(id, direct);
      }
      unawaited(refresh());
      return;
    }
    if (event['type'] == 'message.read') return _handleRead(event);
    if (event['type'] == 'message.updated') return _handleUpdated(event);
    if (event['type'] == 'typing') return _handleTyping(event);
    if (event['type'] == 'location') return _handleLocation(event);
    if (event['type'] == 'live_location.position') {
      return _handleLivePosition(event);
    }
    if (event['type'] == 'live_location.ended') return _handleLiveEnded(event);
    if (event['type'] != 'message.new') return;
    final ChatMessage message;
    try {
      message = ChatMessage.fromJson(event['message'] as Map<String, dynamic>);
    } catch (_) {
      return;
    }
    final conversationId = message.conversationId;
    // their message arrived: they've stopped typing
    _typing.remove(conversationId)?.cancel();
    final thread = _threads[conversationId];
    final alreadyShown = thread?.hasId(message.id!) ?? false;
    if (thread != null && thread.loaded && !alreadyShown) thread.add(message);

    final viewing = _isViewing(conversationId);
    final current = summary(conversationId);
    if (current == null) {
      unawaited(refresh()); // a new conversation: the list has its details
    } else if (!alreadyShown) {
      _replaceSummary(current.copyWith(
          lastMessage: message,
          unreadCount: viewing ? 0 : current.unreadCount + 1));
      _moveToTop(conversationId);
    }
    if (viewing) unawaited(_markReadNow(conversationId));
    if (!viewing && !alreadyShown && _sounded.add(message.id!)) playSound();
    notifyListeners();
    // events carry no links: fetch the photo's preview or the trade's covers
    if (!alreadyShown && message.type != ChatMessageType.text) {
      unawaited(refreshMessage(conversationId, message.id!));
    }
  }

  /// A message changed (a trade answered, a photo opened or expired): fetch
  /// it if it's shown. No sound, no unread change.
  void _handleUpdated(Map<String, dynamic> event) {
    final conversationId = event['conversation_id'];
    final messageId = event['message_id'];
    if (conversationId is! int || messageId is! int) return;
    final shown = _threads[conversationId]?.hasId(messageId) ?? false;
    final listed = summary(conversationId)?.lastMessage?.id == messageId;
    if (shown || listed) unawaited(refreshMessage(conversationId, messageId));
  }

  /// They read my messages in this conversation, up to `read_up_to`.
  void _handleRead(Map<String, dynamic> event) {
    final conversationId = event['conversation_id'];
    final upTo = event['read_up_to'];
    if (conversationId is! int || upTo is! int) return;
    _threads[conversationId]?.markMineRead(upTo);
    final current = summary(conversationId);
    final last = current?.lastMessage;
    if (current != null &&
        last != null &&
        last.fromMe &&
        last.id != null &&
        last.id! <= upTo) {
      _replaceSummary(current.copyWith(lastMessage: last.copyWith(read: true)));
    }
    notifyListeners();
  }

  Future<void> _markReadNow(int conversationId) async {
    try {
      await _call((t) => service.markRead(t, conversationId));
    } catch (error) {
      debugPrint('Marking conversation $conversationId read failed: $error');
    }
  }

  // ---- list upkeep ----

  void _touchSummary(int conversationId, Profile other, ChatMessage last,
      {required int unreadDelta}) {
    final current = summary(conversationId);
    // an anonymous conversation stays in the Anonymous tab
    final List<ConversationSummary> list = current?.anonymous != null
        ? (anonymousConversations ??= [])
        : (conversations ??= []);
    _started.remove(conversationId);
    final updated = current == null
        ? ConversationSummary(
            id: conversationId, other: other, lastMessage: last, unreadCount: 0)
        : current.copyWith(
            lastMessage: last, unreadCount: current.unreadCount + unreadDelta);
    list.removeWhere((c) => c.id == conversationId);
    list.insert(0, updated);
  }

  void _replaceSummary(ConversationSummary updated) {
    if (_started.containsKey(updated.id)) _started[updated.id] = updated;
    for (final list in [conversations, anonymousConversations]) {
      if (list == null) continue;
      final i = list.indexWhere((c) => c.id == updated.id);
      if (i >= 0) list[i] = updated;
    }
  }

  void _moveToTop(int conversationId) {
    for (final list in [conversations, anonymousConversations]) {
      if (list == null) continue;
      final i = list.indexWhere((c) => c.id == conversationId);
      if (i > 0) list.insert(0, list.removeAt(i));
    }
  }

  /// When the session ends: nothing of this user stays in memory.
  void clear() {
    for (final session in _sessions.values) {
      session.cancel();
    }
    _sessions.clear();
    _livePositions.clear();
    _endedHere.clear();
    liveProblem = null;
    _positions.clear();
    for (final timer in _typing.values) {
      timer.cancel();
    }
    _typing.clear();
    _typingSent.clear();
    conversations = null;
    loadError = null;
    anonymousConversations = null;
    anonymousLoadError = null;
    _directNext = _anonymousNext = null;
    _directUnreadElsewhere = _anonymousUnreadElsewhere = 0;
    _started.clear();
    _movedToDirect.clear();
    _gone.clear();
    _threads.clear();
    _sounded.clear();
    _viewing = null;
    notifyListeners();
  }
}

/// A live location session I'm sharing in, while it's active.
class _LiveSession {
  _LiveSession(this.message);

  ChatMessage message;
  DevicePosition? latest;
  DevicePosition? sent;
  StreamSubscription<DevicePosition>? moves;
  Timer? heartbeat;

  /// Sent recently: the next send waits for it ([waiting]: one is due).
  Timer? cooldown;
  bool waiting = false;

  void cancel() {
    moves?.cancel();
    heartbeat?.cancel();
    cooldown?.cancel();
  }
}

/// One conversation's messages: confirmed ones in id order, then my pending.
class _Thread {
  final List<ChatMessage> messages = [];
  bool hasMore = false;
  bool loaded = false;
  bool loadingOlder = false;
  String? error;

  /// Loading older messages failed: it waits for a tap to retry (it isn't
  /// tried again on every rebuild).
  bool olderFailed = false;

  int? get oldestId {
    for (final m in messages) {
      if (m.id != null) return m.id;
    }
    return null;
  }

  int? get newestId {
    for (final m in messages.reversed) {
      if (m.id != null) return m.id;
    }
    return null;
  }

  bool hasId(int id) => messages.any((m) => m.id == id);

  ChatMessage? byClientId(String clientId) {
    for (final m in messages) {
      if (m.clientId == clientId) return m;
    }
    return null;
  }

  void add(ChatMessage message) {
    messages.add(message);
    _sort();
  }

  void replace(ChatMessage old, ChatMessage updated) {
    final i = messages.indexOf(old);
    if (i >= 0) messages[i] = updated;
  }

  /// Adds messages not shown yet (a saved copy of my pending one replaces
  /// it); ones already shown take the server's newer state (read, a trade's
  /// status, a photo's expiry and links).
  void merge(Iterable<ChatMessage> incoming) {
    for (final m in incoming) {
      if (hasId(m.id!)) {
        final i = messages.indexWhere((s) => s.id == m.id);
        // a read stays read, even if this copy is older
        messages[i] = messages[i].read && !m.read ? m.copyWith(read: true) : m;
        continue;
      }
      final pending = m.clientId == null ? null : byClientId(m.clientId!);
      if (pending != null) messages.remove(pending);
      messages.add(m);
    }
    _sort();
  }

  /// The message, replacing the shown copy (same id), or added.
  void upsert(ChatMessage message) => merge([message]);

  void markMineRead(int upTo) {
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      if (m.fromMe && m.id != null && m.id! <= upTo && !m.read) {
        messages[i] = m.copyWith(read: true);
      }
    }
  }

  /// My send was saved: the pending copy becomes the saved one (unless a
  /// sync already brought the saved one in).
  void confirm(String clientId, ChatMessage saved) {
    final pending = byClientId(clientId);
    if (pending != null && pending.pending) messages.remove(pending);
    if (!hasId(saved.id!)) messages.add(saved);
    _sort();
  }

  void _sort() {
    // confirmed by id; my pending ones after them, in the order sent
    messages.sort((a, b) {
      if (a.id != null && b.id != null) return a.id!.compareTo(b.id!);
      if (a.id != null) return -1;
      if (b.id != null) return 1;
      return a.sentAt.compareTo(b.sentAt);
    });
  }
}

/// Provides [MessagingState] to the screens below; null without a backend.
class MessagingScope extends InheritedNotifier<MessagingState> {
  const MessagingScope(
      {super.key, required MessagingState? state, required super.child})
      : super(notifier: state);

  /// Rebuilds the caller on changes.
  static MessagingState? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MessagingScope>()?.notifier;

  static MessagingState? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MessagingScope>()?.notifier;
}
