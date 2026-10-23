import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'photo_cache_store.dart';

PhotoCacheStore createDeviceStore(String name) =>
    FilePhotoCacheStore(directory: () async {
      final base = await getApplicationCacheDirectory();
      return Directory('${base.path}${Platform.pathSeparator}$name');
    });

/// Files `{folder}/{id}.webp` (e.g. `profile_photos/12.webp`) in the app's
/// cache directory. That directory isn't backed up (iOS) and the system may
/// clear it when space runs low; a cleared photo is simply downloaded again.
class FilePhotoCacheStore implements PhotoCacheStore {
  FilePhotoCacheStore({required Future<Directory> Function() directory})
      : _directory = directory;

  final Future<Directory> Function() _directory;

  Future<File> _file(int photoId, {String suffix = ''}) async {
    final directory = await _directory();
    return File(
        '${directory.path}${Platform.pathSeparator}$photoId.webp$suffix');
  }

  @override
  Future<Uint8List?> read(int photoId) async {
    final file = await _file(photoId);
    return await file.exists() ? file.readAsBytes() : null;
  }

  @override
  Future<void> write(int photoId, Uint8List bytes) async {
    await (await _directory()).create(recursive: true);
    // Written next to it, then renamed: a half-written photo is never read.
    final partial = await _file(photoId, suffix: '.tmp');
    await partial.writeAsBytes(bytes, flush: true);
    await partial.rename((await _file(photoId)).path);
  }

  @override
  Future<void> delete(int photoId) async {
    final file = await _file(photoId);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> retainOnly(Set<int> photoIds) async {
    final directory = await _directory();
    if (!await directory.exists()) return;
    await for (final entry in directory.list()) {
      final name = entry.uri.pathSegments.last;
      final id = name.endsWith('.webp')
          ? int.tryParse(name.substring(0, name.length - 5))
          : null; // leftovers, e.g. a .tmp from an interrupted write
      if (id == null || !photoIds.contains(id)) await entry.delete();
    }
  }

  @override
  Future<void> clear() async {
    final directory = await _directory();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}
