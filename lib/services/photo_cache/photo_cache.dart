import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/models.dart';
import '../../widgets/photos/photo_file_check.dart';
import 'photo_cache_store.dart';

/// Where the bytes of a shown photo came from.
enum PhotoSource { deviceCache, network }

class CachedPhoto {
  const CachedPhoto(this.bytes, this.source);
  final Uint8List bytes;
  final PhotoSource source;
}

/// My two collections of stored pictures. Each has its own cache (and
/// device store), since their ids come from different tables and may repeat.
enum PhotoCollection { profile, album }

/// Looks up the fresh details (link) of a photo after its link expired;
/// null when the photo is no longer listed.
typedef RefreshPhoto = Future<StoredPhoto?> Function(int photoId);

/// One collection of my stored pictures on this device (profile photos, or
/// album photos and video thumbnails), keyed by id - never by the presigned
/// link, which changes on every refresh. A picture is downloaded only when it
/// isn't saved yet; a cropped photo has a new id, so it is a new entry.
///
/// Late downloads can't bring a picture back: removed or replaced ids are
/// retired, and ending the session starts a new generation.
class PhotoCache {
  PhotoCache({required this.store, http.Client? client})
      : _client = client ?? http.Client();

  final PhotoCacheStore store;
  final http.Client _client;

  /// Set by the screen that can reload the list (and so get fresh links).
  RefreshPhoto? refresh;

  final Map<int, CachedPhoto> _memory = {};
  final Map<int, Future<CachedPhoto?>> _loading = {};
  final Set<int> _retired = {};
  int _generation = 0;

  /// The photo if it's already in memory (no waiting).
  CachedPhoto? peek(int photoId) => _memory[photoId];

  /// The photo's bytes: from memory, the device, or (once at a time per
  /// photo) downloaded and saved. Null when it can't be loaded.
  Future<CachedPhoto?> load(StoredPhoto photo) {
    final known = _memory[photo.id];
    if (known != null) return SynchronousFuture(known);
    final running = _loading[photo.id];
    if (running != null) return running;
    late final Future<CachedPhoto?> loading;
    loading = _load(photo).whenComplete(() {
      // Not one started after a clear().
      if (identical(_loading[photo.id], loading)) _loading.remove(photo.id);
    });
    return _loading[photo.id] = loading;
  }

  Future<CachedPhoto?> _load(StoredPhoto photo) async {
    final generation = _generation;
    final saved = await _readSaved(photo.id);
    if (saved != null) return _remember(photo.id, saved, generation);

    final downloaded = await _download(photo);
    if (downloaded == null || !_current(photo.id, generation)) return null;
    try {
      await store.write(photo.id, downloaded.bytes);
      // Retired or signed out while it was being written: take it back.
      if (!_current(photo.id, generation)) await store.delete(photo.id);
    } catch (error) {
      debugPrint('Photo ${photo.id} could not be saved on the device: $error');
    }
    return _remember(photo.id, downloaded, generation);
  }

  Future<CachedPhoto?> _readSaved(int photoId) async {
    try {
      final bytes = await store.read(photoId);
      if (bytes == null) return null;
      if (detectImageType(bytes) == ImageFileType.webp) {
        return CachedPhoto(bytes, PhotoSource.deviceCache);
      }
      await store.delete(photoId); // damaged: download it again
    } catch (error) {
      debugPrint('Photo $photoId could not be read from the device: $error');
    }
    return null;
  }

  Future<CachedPhoto?> _download(StoredPhoto photo) async {
    try {
      var response = await _client.get(Uri.parse(photo.imageUrl));
      final refresh = this.refresh;
      if (response.statusCode == 403 && refresh != null) {
        // The link has most likely expired: get a fresh one, try once more.
        final fresh = await refresh(photo.id);
        if (fresh == null) return null;
        response = await _client.get(Uri.parse(fresh.imageUrl));
      }
      final bytes = response.bodyBytes;
      if (response.statusCode != 200 ||
          detectImageType(bytes) != ImageFileType.webp) {
        debugPrint('Photo ${photo.id} download failed: '
            '${response.statusCode}, ${bytes.length} bytes');
        return null;
      }
      return CachedPhoto(bytes, PhotoSource.network);
    } catch (error) {
      debugPrint('Photo ${photo.id} download failed: $error');
      return null;
    }
  }

  bool _current(int photoId, int generation) =>
      generation == _generation && !_retired.contains(photoId);

  CachedPhoto? _remember(int photoId, CachedPhoto photo, int generation) {
    if (!_current(photoId, generation)) return null;
    return _memory[photoId] = photo;
  }

  /// After a successful refresh: only the listed photos are kept.
  Future<void> keepOnly(Iterable<StoredPhoto> photos) async {
    final ids = {for (final photo in photos) photo.id};
    _memory.removeWhere((id, _) => !ids.contains(id));
    try {
      await store.retainOnly(ids);
    } catch (error) {
      debugPrint('Old photos could not be removed from the device: $error');
    }
  }

  /// After a photo was removed or replaced (confirmed by the backend).
  Future<void> retire(int photoId) async {
    _retired.add(photoId);
    _memory.remove(photoId);
    try {
      await store.delete(photoId);
    } catch (error) {
      debugPrint('Photo $photoId could not be removed from the device: $error');
    }
  }

  /// When the session ends or another account signs in.
  Future<void> clear() async {
    _generation++;
    _memory.clear();
    _loading.clear();
    try {
      await store.clear();
    } catch (error) {
      debugPrint('Photos could not be removed from the device: $error');
    }
  }
}
