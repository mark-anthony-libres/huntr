import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/google_oauth_config.dart';
import 'huntr_backend.dart'
    show BackendException, ChatGif, GifPage, SessionRejectedException;

/// Guest chats (a guest link: people not on HUNTR chat anonymously with its
/// owner). The guest's side is public and opened by a secret only their
/// browser holds; the host's side is signed in.

/// The chat ended (no message from the guest for a while) or doesn't exist.
class GuestChatEndedException implements Exception {
  const GuestChatEndedException();
}

/// My guest link (null [code] until made) and the anonymous name guests see.
class GuestLinkInfo {
  const GuestLinkInfo({
    required this.code,
    required this.isOn,
    required this.name,
    required this.avatar,
    required this.idleMinutes,
  });

  factory GuestLinkInfo.fromJson(Map<String, dynamic> json) {
    final link = json['link'] as Map<String, dynamic>?;
    return GuestLinkInfo(
      code: link?['code'] as String?,
      isOn: link?['is_on'] as bool? ?? false,
      name: json['name'] as String,
      avatar: json['avatar'] as String,
      idleMinutes: json['idle_minutes'] as int? ?? 10,
    );
  }

  final String? code;
  final bool isOn;
  final String name;
  final String avatar;
  final int idleMinutes;

  /// The link to share (huntr.online/g/<code>).
  String? get url => code == null ? null : guestLinkUrl(code!);
}

/// The public address of a guest link.
String guestLinkUrl(String code) => 'https://huntr.online/g/$code';

/// The host as a guest link's page shows them: an anonymous name and animal.
class GuestLinkCard {
  const GuestLinkCard(
      {required this.name, required this.avatar, required this.idleMinutes});

  factory GuestLinkCard.fromJson(Map<String, dynamic> json) => GuestLinkCard(
      name: json['name'] as String,
      avatar: json['avatar'] as String,
      idleMinutes: json['idle_minutes'] as int? ?? 10);

  final String name;
  final String avatar;
  final int idleMinutes;
}

/// One message in a guest chat: text, or a GIF/sticker. [id] is null while
/// mine is being sent; [failed] when it didn't go through.
class GuestChatMessage {
  const GuestChatMessage({
    required this.id,
    required this.mine,
    required this.text,
    required this.sentAt,
    required this.clientId,
    this.gif,
    this.failed = false,
  });

  factory GuestChatMessage.fromJson(Map<String, dynamic> json) {
    final isGif = json['type'] == 'gif';
    final body = json['body'];
    return GuestChatMessage(
      id: json['id'] as int,
      mine: json['mine'] as bool,
      text: isGif ? '' : body as String,
      gif: isGif ? ChatGif.fromJson(body as Map<String, dynamic>) : null,
      clientId: json['client_id'] as String,
      sentAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  final int? id;
  final bool mine;
  final String text;
  final ChatGif? gif;
  final String clientId;
  final DateTime sentAt;
  final bool failed;

  /// A line for a chat list.
  String get preview => gif == null
      ? text
      : gif!.isSticker
          ? 'Sticker'
          : 'GIF';

  GuestChatMessage copyWith({bool? failed}) => GuestChatMessage(
      id: id,
      mine: mine,
      text: text,
      gif: gif,
      clientId: clientId,
      sentAt: sentAt,
      failed: failed ?? this.failed);
}

/// A guest chat as either side sees it: the other's anonymous name and
/// animal, mine, when it ends, the last message and how many are unread.
class GuestChatSummary {
  const GuestChatSummary({
    required this.id,
    required this.name,
    required this.avatar,
    required this.myName,
    required this.myAvatar,
    required this.endsAt,
    required this.idleMinutes,
    required this.lastMessage,
    required this.unread,
    required this.theyReadUpTo,
    this.ended = false,
    this.deletesAt,
  });

  factory GuestChatSummary.fromJson(Map<String, dynamic> json) {
    final last = json['last_message'] as Map<String, dynamic>?;
    return GuestChatSummary(
      id: json['id'] as int,
      name: json['name'] as String,
      avatar: json['avatar'] as String,
      myName: json['my_name'] as String,
      myAvatar: json['my_avatar'] as String,
      endsAt: DateTime.parse(json['ends_at'] as String).toLocal(),
      idleMinutes: json['idle_minutes'] as int? ?? 10,
      lastMessage: last == null ? null : GuestChatMessage.fromJson(last),
      unread: json['unread'] as int? ?? 0,
      theyReadUpTo: json['read_up_to'] as int?,
      ended: json['ended'] as bool? ?? false,
      deletesAt: json['deletes_at'] == null
          ? null
          : DateTime.parse(json['deletes_at'] as String).toLocal(),
    );
  }

  final int id;
  final String name;
  final String avatar;
  final String myName;
  final String myAvatar;
  final DateTime endsAt;
  final int idleMinutes;
  final GuestChatMessage? lastMessage;
  final int unread;

  /// The newest of my messages they've read.
  final int? theyReadUpTo;

  /// It ended: the guest can't open it; its host can read it (not answer)
  /// until [deletesAt].
  final bool ended;
  final DateTime? deletesAt;

  /// Whole minutes left (at least 1 while it's open).
  int minutesLeft(DateTime now) {
    final left = endsAt.difference(now);
    if (left.isNegative) return 0;
    return (left.inSeconds / 60).ceil().clamp(1, idleMinutes);
  }

  GuestChatSummary copyWith(
          {GuestChatMessage? lastMessage,
          int? unread,
          DateTime? endsAt,
          int? theyReadUpTo,
          bool? ended}) =>
      GuestChatSummary(
          id: id,
          name: name,
          avatar: avatar,
          myName: myName,
          myAvatar: myAvatar,
          endsAt: endsAt ?? this.endsAt,
          idleMinutes: idleMinutes,
          lastMessage: lastMessage ?? this.lastMessage,
          unread: unread ?? this.unread,
          theyReadUpTo: theyReadUpTo ?? this.theyReadUpTo,
          ended: ended ?? this.ended,
          deletesAt: deletesAt);
}

/// A chat and its messages.
class GuestChatPage {
  const GuestChatPage({required this.chat, required this.messages});

  factory GuestChatPage.fromJson(Map<String, dynamic> json) => GuestChatPage(
        chat: GuestChatSummary.fromJson(json['chat'] as Map<String, dynamic>),
        messages: [
          for (final m in json['messages'] as List<dynamic>)
            GuestChatMessage.fromJson(m as Map<String, dynamic>),
        ],
      );

  final GuestChatSummary chat;
  final List<GuestChatMessage> messages;
}

/// A chat just started: its secret (kept by the browser) and the chat.
class GuestStart {
  const GuestStart({required this.token, required this.chat});

  final String token;
  final GuestChatSummary chat;
}

/// The guest chat API, for both sides.
class GuestChatApi {
  GuestChatApi({http.Client? client, String? backendUrl})
      : _client = client,
        _backendUrl = backendUrl;

  final http.Client? _client;

  /// The backend's address (the app's config unless given, e.g. in tests).
  final String? _backendUrl;

  Future<String> _url() async =>
      _backendUrl ?? await GoogleOAuthConfig.loadBackendUrl();

  Future<Map<String, dynamic>> _send(String method, String path,
      {String? token, String? guestToken, Object? body}) async {
    final base = (await _url()).replaceAll(RegExp(r'/+$'), '');
    final request = http.Request(method, Uri.parse('$base$path'))
      ..headers.addAll({
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
        if (guestToken != null) 'X-Guest-Token': guestToken,
      });
    if (body != null) request.body = jsonEncode(body);
    final client = _client ?? http.Client();
    final http.Response response;
    try {
      response = await http.Response.fromStream(await client.send(request));
    } on http.ClientException {
      throw const BackendException('Could not reach the Huntr server.');
    } finally {
      if (_client == null) client.close();
    }
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    if (token != null &&
        (response.statusCode == 401 || response.statusCode == 403)) {
      throw const SessionRejectedException();
    }
    // the chat ended (or its secret opens nothing anymore)
    if (response.statusCode == 410 ||
        (response.statusCode == 404 && path.startsWith('/guest/chat')) ||
        (response.statusCode == 404 && path.startsWith('/guest-chats/'))) {
      throw const GuestChatEndedException();
    }
    String? message;
    try {
      final detail = (jsonDecode(response.body) as Map)['detail'];
      if (detail is String && detail.isNotEmpty) message = detail;
    } catch (_) {}
    throw BackendException(response.statusCode >= 500 || message == null
        ? 'Something went wrong on our side. Please try again in a moment.'
        : message);
  }

  Map<String, dynamic> _data(Map<String, dynamic> body) =>
      body['data'] as Map<String, dynamic>;

  // ---- the host ----

  Future<GuestLinkInfo> myLink(String token) async => GuestLinkInfo.fromJson(
      _data(await _send('GET', '/guest-link', token: token)));

  /// A new link (the old one stops working, its chats end).
  Future<GuestLinkInfo> newLink(String token) async => GuestLinkInfo.fromJson(
      _data(await _send('POST', '/guest-link', token: token)));

  Future<GuestLinkInfo> setLinkOn(String token, bool on) async =>
      GuestLinkInfo.fromJson(_data(await _send('PUT', '/guest-link/on',
          token: token, body: {'on': on})));

  Future<List<GuestChatSummary>> myChats(String token) async {
    final body = await _send('GET', '/guest-chats', token: token);
    return [
      for (final c in body['data'] as List<dynamic>)
        GuestChatSummary.fromJson(c as Map<String, dynamic>),
    ];
  }

  Future<GuestChatPage> hostMessages(String token, int chatId,
          {int? after}) async =>
      GuestChatPage.fromJson(_data(await _send('GET',
          '/guest-chats/$chatId/messages${after == null ? '' : '?after=$after'}',
          token: token)));

  Future<GuestChatMessage> hostSend(String token, int chatId,
          {String? body, String? gifId, required String clientId}) async =>
      GuestChatMessage.fromJson(_data(await _send(
          'POST', '/guest-chats/$chatId/messages',
          token: token,
          body: {'body': body, 'gif_id': gifId, 'client_id': clientId})));

  Future<void> hostRead(String token, int chatId, int upTo) =>
      _send('POST', '/guest-chats/$chatId/read',
          token: token, body: {'up_to': upTo});

  Future<void> block(String token, int chatId) =>
      _send('POST', '/guest-chats/$chatId/block', token: token);

  /// Ends it now (kept to read).
  Future<void> hostEnd(String token, int chatId) =>
      _send('POST', '/guest-chats/$chatId/end', token: token);

  /// Deletes it with its messages.
  Future<void> hostDelete(String token, int chatId) =>
      _send('DELETE', '/guest-chats/$chatId', token: token);

  // ---- the guest ----

  Future<GuestLinkCard> linkCard(String code) async =>
      GuestLinkCard.fromJson(_data(await _send('GET', '/guest/links/$code')));

  Future<GuestStart> start(String code) async {
    final data = _data(await _send('POST', '/guest/links/$code/chats',
        body: {'agreed': true}));
    return GuestStart(
        token: data['token'] as String,
        chat: GuestChatSummary.fromJson(data['chat'] as Map<String, dynamic>));
  }

  Future<GuestChatPage> guestChat(String guestToken, {int? after}) async =>
      GuestChatPage.fromJson(_data(await _send(
          'GET', '/guest/chat${after == null ? '' : '?after=$after'}',
          guestToken: guestToken)));

  Future<GuestChatMessage> guestSend(String guestToken,
          {String? body, String? gifId, required String clientId}) async =>
      GuestChatMessage.fromJson(_data(await _send(
          'POST', '/guest/chat/messages',
          guestToken: guestToken,
          body: {'body': body, 'gif_id': gifId, 'client_id': clientId})));

  Future<void> guestRead(String guestToken, int upTo) =>
      _send('POST', '/guest/chat/read',
          guestToken: guestToken, body: {'up_to': upTo});

  Future<void> guestEnd(String guestToken) =>
      _send('DELETE', '/guest/chat', guestToken: guestToken);

  Future<GifPage> guestGifs(String guestToken,
      {required bool stickers, String query = '', int offset = 0}) async {
    final kind = stickers ? 'sticker' : 'gif';
    final path = query.isEmpty
        ? '/guest/gifs/trending?kind=$kind&offset=$offset'
        : '/guest/gifs/search?kind=$kind&offset=$offset&q=${Uri.encodeQueryComponent(query)}';
    return GifPage.fromJson(
        _data(await _send('GET', path, guestToken: guestToken)));
  }

  /// Signed in now: the chat moves into our mutual anonymous conversation;
  /// its id.
  Future<int> join(String token, String guestToken) async {
    final data = _data(await _send('POST', '/guest/chat/join',
        token: token, guestToken: guestToken));
    return data['id'] as int;
  }
}
