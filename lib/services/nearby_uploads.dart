import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'huntr_backend.dart'
    show BackendException, NearbyMedia, SessionRejectedException;
import 'nearby_service.dart';

/// A Threads photo or video on its way from this device: how much is sent
/// (0-1), why it failed, or (once stored on the backend) what it is now.
/// Its file is kept in memory until then, so a failed one can be sent
/// again.
class NearbyUpload {
  NearbyUpload._(this.mediaId, this.bytes, this.filename, this.isVideo);

  final int mediaId;
  final bool isVideo;
  Uint8List? bytes;
  String filename;
  double sent = 0;
  String? error;

  /// Stored on the backend (`queued`): compressed there from now on.
  NearbyMedia? stored;

  http.Client? _client;

  bool get sending => _client != null;
}

/// Threads photos and videos on their way from this device. One starts
/// when it's chosen in the composer, and carries on app-wide - after Post
/// too, while I'm elsewhere in the app - so the post can go up at once.
/// Only while the app is open: closing it stops what isn't sent yet (the
/// post shows that, and it can be added again).
class NearbyUploads extends ChangeNotifier {
  NearbyUploads(this._service, {this.onSessionRejected});

  final NearbyService _service;

  /// The session ended while sending (signed out on the backend).
  final VoidCallback? onSessionRejected;

  final _uploads = <int, NearbyUpload>{};
  final _removed = <int>{};

  NearbyUpload? of(int mediaId) => _uploads[mediaId];

  /// Removed here (it may still be on a post that was loaded before).
  bool removed(int mediaId) => _removed.contains(mediaId);

  /// A photo or video I chose: written on the backend (to post at once),
  /// and its file sent from now on.
  Future<NearbyMedia> choose(String token,
      {required Uint8List bytes,
      required String filename,
      required bool isVideo}) async {
    final media = await _service.reserveMedia(token, isVideo: isVideo);
    final upload =
        _uploads[media.id] = NearbyUpload._(media.id, bytes, filename, isVideo);
    unawaited(_send(token, upload));
    return media;
  }

  /// Sends a failed one again (its file is still here).
  void retry(String token, int mediaId) {
    final upload = _uploads[mediaId];
    if (upload == null || upload.sending || upload.bytes == null) return;
    unawaited(_send(token, upload));
  }

  /// A file for one whose upload didn't finish before the app was closed
  /// (chosen again).
  void addAgain(String token, int mediaId,
      {required Uint8List bytes,
      required String filename,
      required bool isVideo}) {
    _uploads[mediaId]?._client?.close();
    final upload =
        _uploads[mediaId] = NearbyUpload._(mediaId, bytes, filename, isVideo);
    unawaited(_send(token, upload));
  }

  /// Stops sending it and removes it on the backend (with whatever is
  /// stored there). One the backend can't remove now goes with its cleanup.
  Future<void> remove(String token, int mediaId) async {
    _uploads.remove(mediaId)?._client?.close();
    _removed.add(mediaId);
    notifyListeners();
    try {
      await _service.removeMedia(token, mediaId);
    } on SessionRejectedException {
      onSessionRejected?.call();
    } catch (error) {
      debugPrint('Thread media $mediaId not removed: $error');
    }
  }

  /// Signed out: everything stops.
  void clear() {
    for (final upload in _uploads.values) {
      upload._client?.close();
    }
    _uploads.clear();
    _removed.clear();
    notifyListeners();
  }

  Future<void> _send(String token, NearbyUpload upload) async {
    final client = upload._client = http.Client();
    upload
      ..sent = 0
      ..error = null;
    notifyListeners();
    // only whole percents are shown: told when one goes by
    var shown = 0;
    try {
      final stored = await _service.uploadMedia(token,
          mediaId: upload.mediaId,
          bytes: upload.bytes!,
          filename: upload.filename, onProgress: (sent) {
        upload.sent = sent;
        final percent = (sent * 100).floor();
        if (percent != shown && _uploads[upload.mediaId] == upload) {
          shown = percent;
          notifyListeners();
        }
      }, client: client);
      upload
        ..stored = stored
        ..bytes = null;
    } on SessionRejectedException {
      upload.error = "It didn't upload: you're signed out.";
      onSessionRejected?.call();
    } catch (error) {
      upload.error = error is BackendException
          ? _shown(error)
          : "It didn't upload. Check your connection and try again.";
    } finally {
      if (upload._client == client) upload._client = null;
      client.close();
    }
    if (_uploads[upload.mediaId] == upload) notifyListeners();
  }

  /// The backend's reason, or (not reached) a plain one.
  static String _shown(BackendException error) =>
      error.message == 'Could not reach the Huntr server.'
          ? "It didn't upload. Check your connection and try again."
          : error.message;
}
