import 'dart:typed_data';

import 'photo_cache_store_stub.dart'
    if (dart.library.io) 'photo_cache_store_io.dart'
    if (dart.library.js_interop) 'photo_cache_store_web.dart';

/// Where one collection of my pictures is kept on this device, by id: files
/// on Android and iOS (folder [name]), IndexedDB on the web (object store
/// [name]).
abstract class PhotoCacheStore {
  /// The store for this platform, e.g. `profile_photos` or `album_media`.
  factory PhotoCacheStore.device(String name) => createDeviceStore(name);

  /// The saved bytes of the photo, or null when it isn't saved.
  Future<Uint8List?> read(int photoId);

  /// Saves the photo, replacing any earlier copy only once fully written.
  Future<void> write(int photoId, Uint8List bytes);

  Future<void> delete(int photoId);

  /// Deletes every photo except these.
  Future<void> retainOnly(Set<int> photoIds);

  /// Deletes every photo.
  Future<void> clear();
}

/// Keeps photos in memory only (tests, and platforms without storage).
class MemoryPhotoCacheStore implements PhotoCacheStore {
  final Map<int, Uint8List> photos = {};

  @override
  Future<Uint8List?> read(int photoId) async => photos[photoId];

  @override
  Future<void> write(int photoId, Uint8List bytes) async =>
      photos[photoId] = bytes;

  @override
  Future<void> delete(int photoId) async => photos.remove(photoId);

  @override
  Future<void> retainOnly(Set<int> photoIds) async =>
      photos.removeWhere((id, _) => !photoIds.contains(id));

  @override
  Future<void> clear() async => photos.clear();
}
