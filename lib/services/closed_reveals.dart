import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Reveal outcomes closed in a chat (their banner, e.g. "You both stay
/// anonymous"), remembered on this device: by conversation and outcome, so
/// a new answer later shows again.
class ClosedReveals {
  ClosedReveals._();

  static const _key = 'huntr_closed_reveals';
  static const _storage = FlutterSecureStorage();

  static final _closed = <String>{};
  static Future<void>? _loading;

  static String _id(int conversationId, String outcome) =>
      '$conversationId:$outcome';

  /// Reads what was closed before (once; later calls wait for the same read).
  static Future<void> load() => _loading ??= () async {
        try {
          final saved = await _storage.read(key: _key);
          if (saved != null && saved.isNotEmpty) {
            _closed.addAll(saved.split(','));
          }
        } catch (_) {
          // no storage here: closed only while the app is open
        }
      }();

  static bool isClosed(int conversationId, String outcome) =>
      _closed.contains(_id(conversationId, outcome));

  static Future<void> close(int conversationId, String outcome) async {
    _closed.add(_id(conversationId, outcome));
    try {
      await _storage.write(key: _key, value: _closed.join(','));
    } catch (_) {
      // kept for this run only
    }
  }
}
