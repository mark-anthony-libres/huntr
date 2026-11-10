import 'package:web/web.dart' as web;

/// In a browser, a video is a page element over the app, and a tap on it
/// (a phone's touch especially) goes to that element, not to the app. The
/// app never uses the browser's own video controls (they're always off),
/// so videos take no taps at all: a tap on one reaches the app (open full
/// screen, pause, mute). Once, at start.
void letAppTakeVideoTaps() {
  final style = web.document.createElement('style')
    ..textContent = 'video { pointer-events: none; }';
  web.document.head?.append(style);
}
