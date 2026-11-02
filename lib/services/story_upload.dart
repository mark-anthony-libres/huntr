import 'package:flutter/foundation.dart';

import 'huntr_backend.dart';

/// The story being posted in the background: Share goes straight back, and
/// the stories row and Me show how far it is, then the new story (or what
/// went wrong, with Try again). One at a time.
class StoryUpload extends ChangeNotifier {
  Future<void> Function(void Function(double sent) onProgress)? _send;

  /// How much of the file is sent (0-1; 1: the server is getting it ready);
  /// null when nothing is being posted.
  double? get progress => _progress;
  double? _progress;

  /// Why the last one wasn't posted (it can be tried again).
  String? get error => _error;
  String? _error;

  /// Counts the stories posted, so lists of mine know to load again.
  int get posted => _posted;
  int _posted = 0;

  bool get active => _progress != null;

  /// Posts with [send] (it reports the share sent); true once it's up.
  Future<bool> start(
      Future<void> Function(void Function(double sent) onProgress) send) {
    _send = send;
    return _run();
  }

  /// The last one again, after it failed.
  Future<bool> retry() => _send == null || active ? Future.value(false) : _run();

  /// Forget a failed one.
  void dismiss() {
    _send = null;
    _error = null;
    notifyListeners();
  }

  Future<bool> _run() async {
    _progress = 0;
    _error = null;
    notifyListeners();
    try {
      await _send!((sent) {
        _progress = sent;
        notifyListeners();
      });
      _send = null;
      _posted++;
      return true;
    } on BackendException catch (e) {
      _error = e.message;
      return false;
    } catch (_) {
      _error = "Your story wasn't posted. Check your connection and try again.";
      return false;
    } finally {
      _progress = null;
      notifyListeners();
    }
  }
}

final storyUpload = StoryUpload();
