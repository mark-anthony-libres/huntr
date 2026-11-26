import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../services/guest_chat_api.dart';
import '../services/huntr_backend.dart'
    show BackendException, ChatGif, GifPage, SessionRejectedException;

typedef GuestGifLoader = Future<GifPage?> Function(
    {required bool stickers, String query, int offset});

final _random = Random.secure();

String newGuestClientId() => List.generate(
    16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

/// One guest chat, for either side (the host signed in, or the guest by the
/// secret their browser holds): its messages, sending text and GIFs, read
/// marks, and catching up every [pollEvery]. The calls differ by side; what
/// the chat does doesn't.
class GuestChatController extends ChangeNotifier {
  GuestChatController({
    required Future<GuestChatPage> Function(int? after) fetch,
    required Future<GuestChatMessage> Function(
            {String? body, String? gifId, required String clientId})
        post,
    this.read,
    this.gifs,
    this.pollEvery = const Duration(seconds: 3),
    this.onEnded,
  })  : _fetch = fetch,
        _post = post;

  final Future<GuestChatPage> Function(int? after) _fetch;
  final Future<GuestChatMessage> Function(
      {String? body, String? gifId, required String clientId}) _post;
  final Future<void> Function(int upTo)? read;

  /// GIF search for this side.
  final GuestGifLoader? gifs;
  final Duration pollEvery;

  /// The chat ended (said once).
  final VoidCallback? onEnded;

  GuestChatSummary? chat;
  final List<GuestChatMessage> messages = [];
  bool ended = false;

  /// The guest joined HUNTR: the chat moved to this anonymous conversation.
  int? joinedConversationId;
  bool loading = true;
  String? error;
  Timer? _poll;
  bool _disposed = false;
  int _readSent = 0;

  int? get _newestId {
    for (final m in messages.reversed) {
      if (m.id != null) return m.id;
    }
    return null;
  }

  Future<void> start() async {
    await refresh();
    _poll = Timer.periodic(pollEvery, (_) => refresh());
  }

  /// Catches up: new messages (and the chat's ends-at).
  Future<void> refresh() async {
    if (ended || _disposed) return;
    try {
      final page = await _fetch(_newestId);
      if (_disposed) return;
      chat = page.chat;
      for (final message in page.messages) {
        _add(message);
      }
      loading = false;
      error = null;
      _notify();
      _markRead();
      // an ended chat (its host reading it): nothing more comes
      if (page.chat.ended) _end();
    } on GuestChatEndedException {
      _end();
    } on SessionRejectedException {
      rethrow;
    } catch (e) {
      loading = false;
      error = e is BackendException
          ? e.message
          : 'Check your connection and try again.';
      _notify();
    }
  }

  /// A message that came live (the host's apps get one per guest message).
  void addIncoming(GuestChatMessage message, GuestChatSummary? summary) {
    if (summary != null) chat = summary;
    _add(message);
    _notify();
    _markRead();
  }

  void _add(GuestChatMessage message) {
    final i = messages.indexWhere((m) =>
        (m.id != null && m.id == message.id) || m.clientId == message.clientId);
    if (i >= 0) {
      messages[i] = message;
    } else {
      messages.add(message);
    }
  }

  void _markRead() {
    final newest = messages.where((m) => !m.mine && m.id != null);
    if (newest.isEmpty || read == null) return;
    final upTo = newest.last.id!;
    if (upTo <= _readSent) return;
    _readSent = upTo;
    unawaited(read!(upTo).catchError((_) {}));
  }

  Future<void> sendText(String text) => _send(body: text.trim());

  Future<void> sendGif(ChatGif gif) => _send(gif: gif);

  /// Shown at once, then saved; a failure marks it to try again.
  Future<void> _send({String? body, ChatGif? gif, String? clientId}) async {
    if (ended || ((body == null || body.isEmpty) && gif == null)) return;
    final id = clientId ?? newGuestClientId();
    final pending = GuestChatMessage(
        id: null,
        mine: true,
        text: body ?? '',
        gif: gif,
        clientId: id,
        sentAt: DateTime.now());
    _add(pending);
    _notify();
    try {
      final saved = await _post(body: body, gifId: gif?.id, clientId: id);
      _add(saved);
      // a guest's message gives the chat its full time again
      await refresh();
    } on GuestChatEndedException {
      _end();
    } catch (_) {
      _add(pending.copyWith(failed: true));
    }
    _notify();
  }

  /// Tries a failed message again (the same client id: stored once).
  Future<void> retry(GuestChatMessage failed) => _send(
      body: failed.gif == null ? failed.text : null,
      gif: failed.gif,
      clientId: failed.clientId);

  void markEnded({int? joinedConversationId}) {
    this.joinedConversationId ??= joinedConversationId;
    _end();
  }

  void _end() {
    if (ended) return;
    ended = true;
    _poll?.cancel();
    _notify();
    onEnded?.call();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    super.dispose();
  }
}

/// The host's side: my guest link, my guest chats (in the Anonymous tab),
/// kept current by live events.
class GuestChatsState extends ChangeNotifier {
  GuestChatsState(
      {required this.api, required this.token, this.onSessionRejected});

  final GuestChatApi api;
  final String? Function() token;
  final VoidCallback? onSessionRejected;

  GuestLinkInfo? link;
  List<GuestChatSummary> chats = const [];

  /// Open chat screens, by chat id (live messages go straight to them).
  final Map<int, GuestChatController> _open = {};

  int get unread =>
      chats.where((c) => !c.ended).fold(0, (sum, c) => sum + c.unread);

  Future<T?> _call<T>(Future<T> Function(String token) call) async {
    final t = token();
    if (t == null) return null;
    try {
      return await call(t);
    } on SessionRejectedException {
      onSessionRejected?.call();
      return null;
    }
  }

  Future<void> refresh() async {
    try {
      final loaded = await _call(api.myChats);
      if (loaded == null) return;
      chats = loaded;
      notifyListeners();
    } catch (_) {
      // kept as they were; the next refresh tries again
    }
  }

  Future<GuestLinkInfo?> loadLink() async {
    final loaded = await _call(api.myLink);
    if (loaded != null) {
      link = loaded;
      notifyListeners();
    }
    return loaded;
  }

  /// A new link (the old one stops working; its chats end).
  Future<GuestLinkInfo?> newLink() async {
    final made = await _call(api.newLink);
    if (made != null) {
      link = made;
      await refresh();
      notifyListeners();
    }
    return made;
  }

  Future<void> setLinkOn(bool on) async {
    final changed = await _call((t) => api.setLinkOn(t, on));
    if (changed != null) {
      link = changed;
      notifyListeners();
    }
  }

  /// A chat screen's controller (the host's side; [gifs]: my GIF search).
  GuestChatController open(int chatId, {GuestGifLoader? gifs}) {
    final controller = GuestChatController(
      fetch: (after) async =>
          (await _call((t) => api.hostMessages(t, chatId, after: after)))!,
      post: ({String? body, String? gifId, required String clientId}) async =>
          (await _call((t) => api.hostSend(t, chatId,
              body: body, gifId: gifId, clientId: clientId)))!,
      read: (upTo) async {
        await _call((t) => api.hostRead(t, chatId, upTo));
        _setUnread(chatId, 0);
      },
      gifs: gifs,
      // live events bring new messages; this only catches up after a gap
      pollEvery: const Duration(seconds: 15),
      // ended (seen while open): kept in the list, to read
      onEnded: () => _markEnded(chatId),
    );
    _open[chatId] = controller;
    return controller;
  }

  void close(int chatId, GuestChatController controller) {
    if (_open[chatId] == controller) _open.remove(chatId);
  }

  Future<void> block(int chatId) async {
    await _call((t) => api.block(t, chatId));
    _drop(chatId);
  }

  /// Ends it now: kept to read.
  Future<void> end(int chatId) async {
    await _call((t) => api.hostEnd(t, chatId));
    _markEnded(chatId);
  }

  /// Deletes it with its messages.
  Future<void> delete(int chatId) async {
    await _call((t) => api.hostDelete(t, chatId));
    _drop(chatId);
  }

  /// Ended: still listed (to read), and an open screen stops sending.
  void _markEnded(int chatId) {
    _open[chatId]?.markEnded();
    // already listed as ended: stays where it is
    if (chats.any((c) => c.id == chatId && c.ended)) return;
    final ended = [
      for (final c in chats)
        if (c.id == chatId) c.copyWith(ended: true)
    ];
    if (ended.isEmpty) return;
    // open ones first, then ended ones
    chats = [
      ...chats.where((c) => c.id != chatId && !c.ended),
      ...ended,
      ...chats.where((c) => c.id != chatId && c.ended),
    ];
    notifyListeners();
  }

  void _setUnread(int chatId, int unread) {
    chats = [
      for (final c in chats) c.id == chatId ? c.copyWith(unread: unread) : c
    ];
    notifyListeners();
  }

  void _drop(int chatId, {int? joinedConversationId}) {
    _open.remove(chatId)?.markEnded(joinedConversationId: joinedConversationId);
    chats = chats.where((c) => c.id != chatId).toList();
    notifyListeners();
  }

  /// A live event: guest.started / message / read / ended / joined.
  void handleEvent(Map<String, dynamic> event) {
    final type = event['type'];
    if (type is! String || !type.startsWith('guest.')) return;
    switch (type) {
      case 'guest.message':
        final chatJson = event['chat'];
        final messageJson = event['message'];
        if (chatJson is! Map<String, dynamic> ||
            messageJson is! Map<String, dynamic>) {
          return;
        }
        final summary = GuestChatSummary.fromJson(chatJson);
        final message = GuestChatMessage.fromJson(messageJson);
        final open = _open[summary.id];
        open?.addIncoming(message, summary);
        final rest = chats.where((c) => c.id != summary.id);
        chats = [open == null ? summary : summary.copyWith(unread: 0), ...rest];
        notifyListeners();
      case 'guest.ended':
        final id = event['chat_id'];
        if (id is int) _markEnded(id);
      case 'guest.removed':
      case 'guest.joined':
        final id = event['chat_id'];
        final moved = event['conversation_id'];
        if (id is int) {
          _drop(id, joinedConversationId: moved is int ? moved : null);
        }
      default:
        unawaited(refresh());
    }
  }

  void clear() {
    link = null;
    chats = const [];
    _open.clear(); // their screens close them
    notifyListeners();
  }
}

class GuestChatsScope extends InheritedNotifier<GuestChatsState> {
  const GuestChatsScope(
      {super.key, required GuestChatsState? state, required super.child})
      : super(notifier: state);

  static GuestChatsState? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GuestChatsScope>()?.notifier;

  static GuestChatsState? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<GuestChatsScope>()?.notifier;
}
