import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'photo_cache_store.dart';

PhotoCacheStore createDeviceStore(String name) =>
    IndexedDbPhotoCacheStore(storeName: name);

/// IndexedDB database `huntr_photo_cache`, one object store per collection
/// (`profile_photos`, `album_media`): the picture bytes keyed by id. The
/// browser may clear it when space runs low; a cleared picture is simply
/// downloaded again.
class IndexedDbPhotoCacheStore implements PhotoCacheStore {
  IndexedDbPhotoCacheStore(
      {this.databaseName = 'huntr_photo_cache', required this.storeName});

  final String databaseName;
  final String storeName;

  /// Every collection's store, all created when the database is opened.
  static const storeNames = ['profile_photos', 'album_media'];

  Future<web.IDBDatabase>? _database;

  Future<web.IDBDatabase> _open() => _database ??= _openDatabase();

  Future<web.IDBDatabase> _openDatabase() {
    final opened = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(databaseName, 2);
    request.onupgradeneeded = ((web.Event _) {
      final database = request.result as web.IDBDatabase;
      for (final name in storeNames) {
        if (!database.objectStoreNames.contains(name)) {
          database.createObjectStore(name);
        }
      }
    }).toJS;
    request.onsuccess = ((web.Event _) =>
        opened.complete(request.result as web.IDBDatabase)).toJS;
    request.onerror = ((web.Event _) {
      _database = null; // try again next time
      opened.completeError(StateError('The photo cache could not be opened.'));
    }).toJS;
    return opened.future;
  }

  /// Runs one request in its own transaction and waits for the transaction
  /// to complete, so a write is stored before this returns.
  Future<JSAny?> _run(String mode,
      web.IDBRequest Function(web.IDBObjectStore store) request) async {
    final database = await _open();
    final transaction = database.transaction(storeName.toJS, mode);
    final running = request(transaction.objectStore(storeName));
    final done = Completer<JSAny?>();
    transaction.oncomplete =
        ((web.Event _) => done.complete(running.result)).toJS;
    transaction.onerror = ((web.Event _) =>
        done.completeError(StateError('A photo cache request failed.'))).toJS;
    transaction.onabort = ((web.Event _) =>
        done.completeError(StateError('A photo cache request failed.'))).toJS;
    return done.future;
  }

  @override
  Future<Uint8List?> read(int photoId) async {
    final result = await _run('readonly', (store) => store.get(photoId.toJS));
    return result == null ? null : (result as JSUint8Array).toDart;
  }

  @override
  Future<void> write(int photoId, Uint8List bytes) =>
      _run('readwrite', (store) => store.put(bytes.toJS, photoId.toJS));

  @override
  Future<void> delete(int photoId) =>
      _run('readwrite', (store) => store.delete(photoId.toJS));

  @override
  Future<void> retainOnly(Set<int> photoIds) async {
    final keys = await _run('readonly', (store) => store.getAllKeys());
    for (final key in (keys as JSArray<JSNumber>).toDart) {
      final id = key.toDartInt;
      if (!photoIds.contains(id)) await delete(id);
    }
  }

  @override
  Future<void> clear() => _run('readwrite', (store) => store.clear());
}
