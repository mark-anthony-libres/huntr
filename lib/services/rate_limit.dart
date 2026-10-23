import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Whether the backend is refusing my requests for now (HTTP 429): too many
/// requests in a short time. Every endpoint is refused until [until], so the
/// app shows one full-screen notice instead of an error on each screen.
class RateLimitGate extends ChangeNotifier {
  DateTime? _until;

  /// When requests are accepted again (null: they are now).
  DateTime? get until => _until;

  bool get active => _until != null && DateTime.now().isBefore(_until!);

  /// The backend said 429; [retryAfter] is its `Retry-After`.
  void limited(Duration retryAfter) {
    final until = DateTime.now().add(retryAfter);
    if (_until != null && !until.isAfter(_until!)) return;
    _until = until;
    notifyListeners();
  }

  /// The wait is over.
  void clear() {
    if (_until == null) return;
    _until = null;
    notifyListeners();
  }
}

/// The app's one gate (backend calls report 429s to it).
final rateLimitGate = RateLimitGate();

/// When the server doesn't say: its block lasts 5 minutes.
const _defaultWait = Duration(minutes: 5);

/// A 429 response: how long to wait (its `Retry-After` seconds).
Duration retryAfterOf(http.Response response) {
  final seconds = int.tryParse(response.headers['retry-after'] ?? '');
  return seconds == null || seconds <= 0
      ? _defaultWait
      : Duration(seconds: seconds);
}
