import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../config/google_oauth_config.dart';
import '../huntr_backend.dart';
import 'presence_socket.dart';

/// Keeps me shown as online while the app is open: one WebSocket to the
/// backend's presence (`/api/ws`, see the backend's presence README).
///
/// It says `online` while the app is in the foreground and `idle` when it
/// goes to the background, sends a heartbeat as the server asks, and
/// reconnects (waiting longer each time) when the connection drops. It only
/// reports my own presence; others' status comes with the lists that show
/// them.
class PresenceService {
  PresenceService({
    Future<String> Function(String token)? ticket,
    Future<Uri> Function(String ticket)? address,
    Future<PresenceSocket> Function(Uri url)? connect,
  })  : _ticket = ticket ?? _fetchTicket,
        _address = address ?? _socketAddress,
        _connect = connect ?? PresenceSocket.connect;

  /// Other events on this connection (e.g. `message.new`) go here.
  void Function(Map<String, dynamic> event)? onEvent;

  /// After each (re)connect, to catch up on anything missed meanwhile.
  void Function()? onConnected;

  final Future<String> Function(String token) _ticket;
  final Future<Uri> Function(String ticket) _address;
  final Future<PresenceSocket> Function(Uri url) _connect;

  static Future<String> _fetchTicket(String token) async => fetchWsTicket(
      backendUrl: await GoogleOAuthConfig.loadBackendUrl(), token: token);

  static Future<Uri> _socketAddress(String ticket) async =>
      presenceSocketUrl(await GoogleOAuthConfig.loadBackendUrl(), ticket);

  String? _token;
  PresenceSocket? _socket;
  Timer? _heartbeat;
  Timer? _retry;
  bool _foreground = true;
  int _failures = 0;

  /// True while a connection is open (for tests and diagnostics).
  bool get connected => _socket != null;

  /// Starts (once per session) for the signed-in user.
  void start(String token) {
    if (_token == token) return;
    stop();
    _token = token;
    _open();
  }

  /// Ends it, e.g. when the session ends.
  void stop() {
    _token = null;
    _retry?.cancel();
    _heartbeat?.cancel();
    final socket = _socket;
    _socket = null;
    unawaited(socket?.close());
  }

  /// The app came to the foreground (true) or went to the background.
  void setForeground(bool foreground) {
    if (_foreground == foreground) return;
    _foreground = foreground;
    _send({'type': foreground ? 'online' : 'idle'});
  }

  Future<void> _open() async {
    final token = _token;
    if (token == null) return;
    try {
      final socket = await _connect(await _address(await _ticket(token)));
      if (_token != token) {
        await socket.close(); // stopped meanwhile
        return;
      }
      _socket = socket;
      _failures = 0;
      socket.messages.listen(_received, onDone: () => _closed(socket));
      onConnected?.call();
    } on SessionRejectedException {
      stop(); // signed out elsewhere; the app's session handling takes over
    } catch (error) {
      debugPrint('Presence could not connect: $error');
      _scheduleRetry(token);
    }
  }

  void _received(String text) {
    final Object? message;
    try {
      message = jsonDecode(text);
    } on FormatException {
      return;
    }
    if (message is! Map<String, dynamic>) return;
    if (message['type'] != 'presence.hello') return onEvent?.call(message);
    final seconds = (message['heartbeat_seconds'] as num?)?.toInt() ?? 60;
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(Duration(seconds: seconds),
        (_) => _send({'type': 'heartbeat', 'active': _foreground}));
    _send({'type': _foreground ? 'online' : 'idle'});
  }

  void _closed(PresenceSocket socket) {
    if (!identical(_socket, socket)) return;
    _socket = null;
    _heartbeat?.cancel();
    final token = _token;
    if (token != null) _scheduleRetry(token);
  }

  /// Waits 2, 4, 8 ... up to 60 seconds between tries.
  void _scheduleRetry(String token) {
    if (_token != token) return;
    _failures++;
    final seconds = (1 << _failures.clamp(1, 6)).clamp(2, 60);
    _retry?.cancel();
    _retry = Timer(Duration(seconds: seconds), _open);
  }

  void _send(Map<String, Object> message) {
    try {
      _socket?.send(jsonEncode(message));
    } catch (error) {
      debugPrint('Presence message not sent: $error');
    }
  }
}
