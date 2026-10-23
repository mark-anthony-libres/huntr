import 'dart:io';

import 'presence_socket.dart';

Future<PresenceSocket> connectSocket(Uri url) async =>
    _IoSocket(await WebSocket.connect(url.toString()));

class _IoSocket implements PresenceSocket {
  _IoSocket(this._socket);
  final WebSocket _socket;

  @override
  Stream<String> get messages =>
      _socket.where((m) => m is String).cast<String>();

  @override
  void send(String message) => _socket.add(message);

  @override
  Future<void> close() => _socket.close();
}
