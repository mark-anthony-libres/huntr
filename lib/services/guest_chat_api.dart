import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/google_oauth_config.dart';
import 'huntr_backend.dart' show BackendException, SessionRejectedException;

/// Guest chats (a guest link: people not on HUNTR chat anonymously with its
/// owner). A guest chat is an ordinary anonymous chat: the guest gets a
/// login for a hidden account that reaches only that chat, and both sides
/// use the anonymous chat itself. This is the rest: the link, starting a
/// chat, and ending, deleting or blocking one.

/// The chat ended, or doesn't exist (any more).
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

/// A chat just started: the guest's login (kept by the browser) and the
/// anonymous conversation.
class GuestStart {
  const GuestStart({required this.token, required this.conversationId});

  final String token;
  final int conversationId;
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
    // the chat ended (or is gone)
    if (response.statusCode == 410 ||
        (response.statusCode == 404 && path.startsWith('/guest/chat'))) {
      throw const GuestChatEndedException();
    }
    // a guest's login that stopped (its chat ended): as ended
    if (response.statusCode == 401 && path.startsWith('/guest/chat')) {
      throw const GuestChatEndedException();
    }
    if (token != null &&
        (response.statusCode == 401 || response.statusCode == 403)) {
      throw const SessionRejectedException();
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

  /// Ends a guest chat now (kept to read).
  Future<void> hostEnd(String token, int conversationId) =>
      _send('POST', '/guest-chats/$conversationId/end', token: token);

  /// Deletes a guest chat with everything in it.
  Future<void> hostDelete(String token, int conversationId) =>
      _send('DELETE', '/guest-chats/$conversationId', token: token);

  /// Deletes it; its guest can't start another one for a day.
  Future<void> block(String token, int conversationId) =>
      _send('POST', '/guest-chats/$conversationId/block', token: token);

  // ---- the guest ----

  Future<GuestLinkCard> linkCard(String code) async =>
      GuestLinkCard.fromJson(_data(await _send('GET', '/guest/links/$code')));

  /// A new chat: the guest's login and the conversation.
  Future<GuestStart> start(String code) async {
    final data = _data(await _send('POST', '/guest/links/$code/chats',
        body: {'agreed': true}));
    return GuestStart(
        token: data['token'] as String,
        conversationId: data['conversation_id'] as int);
  }

  /// The guest's chat (its conversation), while it's open; ended:
  /// [GuestChatEndedException].
  Future<int> guestChat(String guestToken) async {
    final data = _data(await _send('GET', '/guest/chat', token: guestToken));
    if (data['ended'] == true) throw const GuestChatEndedException();
    return data['conversation_id'] as int;
  }

  /// The guest ends it.
  Future<void> guestEnd(String guestToken) =>
      _send('DELETE', '/guest/chat', token: guestToken);

  /// Signed in now: the guest chat (its login [guestToken]) moves to my
  /// account; the conversation's id.
  Future<int> join(String token, String guestToken) async {
    final data = _data(await _send('POST', '/guest/chat/join',
        token: token, guestToken: guestToken));
    return data['id'] as int;
  }
}
