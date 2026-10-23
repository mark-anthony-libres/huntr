import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'presence_socket.dart';

Future<PresenceSocket> connectSocket(Uri url) {
  final socket = web.WebSocket(url.toString());
  final opened = Completer<PresenceSocket>();
  final messages = StreamController<String>();
  socket.onopen = ((web.Event _) {
    if (!opened.isCompleted) opened.complete(_WebSocket(socket, messages));
  }).toJS;
  socket.onmessage = ((web.MessageEvent event) {
    final data = event.data;
    if (data.isA<JSString>()) messages.add((data as JSString).toDart);
  }).toJS;
  socket.onerror = ((web.Event _) {
    if (!opened.isCompleted) {
      opened.completeError(StateError('Could not connect.'));
    }
  }).toJS;
  socket.onclose = ((web.Event _) {
    if (!opened.isCompleted) opened.completeError(StateError('Closed.'));
    messages.close();
  }).toJS;
  return opened.future;
}

class _WebSocket implements PresenceSocket {
  _WebSocket(this._socket, this._messages);
  final web.WebSocket _socket;
  final StreamController<String> _messages;

  @override
  Stream<String> get messages => _messages.stream;

  @override
  void send(String message) => _socket.send(message.toJS);

  @override
  Future<void> close() async => _socket.close();
}
