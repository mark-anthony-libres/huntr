import 'presence_socket_stub.dart'
    if (dart.library.io) 'presence_socket_io.dart'
    if (dart.library.js_interop) 'presence_socket_web.dart';

/// One open WebSocket: text messages in and out. dart:io's WebSocket on
/// Android and iOS, the browser's on the web.
abstract class PresenceSocket {
  /// Opens [url]; throws when it can't.
  static Future<PresenceSocket> connect(Uri url) => connectSocket(url);

  /// Incoming text messages; done when the socket closes.
  Stream<String> get messages;

  void send(String message);

  Future<void> close();
}
